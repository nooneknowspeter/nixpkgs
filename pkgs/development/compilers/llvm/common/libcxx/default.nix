{
  lib,
  stdenv,
  llvm_meta,
  release_version,
  monorepoSrc ? null,
  src ? null,
  runCommand,
  cmake,
  lndir,
  ninja,
  python3,
  fixDarwinDylibNames,
  version,
  freebsd,
  cxxabi ? if stdenv.hostPlatform.isFreeBSD then freebsd.libcxxrt else null,
  libunwind,
  enableShared ? stdenv.hostPlatform.hasSharedLibraries,
  devExtraCmakeFlags ? [ ],
  substitute,
  fetchpatch,
}:

# external cxxabi is not supported on Darwin as the build will not link libcxx
# properly and not re-export the cxxabi symbols into libcxx
# https://github.com/NixOS/nixpkgs/issues/166205
# https://github.com/NixOS/nixpkgs/issues/269548
assert cxxabi == null || !stdenv.hostPlatform.isDarwin;
let
  cxxabiName = "lib${if cxxabi == null then "cxxabi" else cxxabi.libName}";
  runtimes = [ "libcxx" ] ++ lib.optional (cxxabi == null) "libcxxabi";

  # Note: useLLVM is likely false for Darwin but true under pkgsLLVM
  useLLVM = stdenv.hostPlatform.useLLVM or false;

  cxxabiCMakeFlags =
    lib.optionals (lib.versionAtLeast release_version "18") [
      (lib.cmakeBool "LIBCXXABI_USE_LLVM_UNWINDER" false)
    ]
    ++ lib.optionals (useLLVM && !stdenv.hostPlatform.isWasm) (
      if lib.versionAtLeast release_version "18" then
        [
          (lib.cmakeFeature "LIBCXXABI_ADDITIONAL_LIBRARIES" "unwind")
          (lib.cmakeBool "LIBCXXABI_USE_COMPILER_RT" true)
        ]
      else
        [
          (lib.cmakeBool "LIBCXXABI_USE_COMPILER_RT" true)
          (lib.cmakeBool "LIBCXXABI_USE_LLVM_UNWINDER" true)
        ]
    )
    ++ lib.optionals stdenv.hostPlatform.isWasm [
      (lib.cmakeBool "LIBCXXABI_ENABLE_THREADS" false)
      (lib.cmakeBool "LIBCXXABI_ENABLE_EXCEPTIONS" false)
    ]
    ++ lib.optionals (!enableShared || stdenv.hostPlatform.isWindows) [
      # Required on Windows due to https://github.com/llvm/llvm-project/issues/55245
      (lib.cmakeBool "LIBCXXABI_ENABLE_SHARED" false)
    ];

  cxxCMakeFlags = [
    (lib.cmakeFeature "LIBCXX_CXX_ABI" cxxabiName)
    (lib.cmakeBool "LIBCXX_ENABLE_SHARED" enableShared)
    # https://github.com/llvm/llvm-project/issues/55245
    (lib.cmakeBool "LIBCXX_ENABLE_STATIC_ABI_LIBRARY" stdenv.hostPlatform.isWindows)
  ]
  ++ lib.optionals (cxxabi == null && lib.versionAtLeast release_version "16") [
    # Note: llvm < 16 doesn't support this flag (or it's broken); handled in postInstall instead.
    # Include libc++abi symbols within libc++.a for static linking libc++;
    # dynamic linking includes them through libc++.so being a linker script
    # which includes both shared objects.
    (lib.cmakeBool "LIBCXX_STATICALLY_LINK_ABI_IN_STATIC_LIBRARY" true)
  ]
  ++ lib.optionals (cxxabi != null) [
    (lib.cmakeFeature "LIBCXX_CXX_ABI_INCLUDE_PATHS" "${lib.getDev cxxabi}/include")
  ]
  ++ lib.optionals (stdenv.hostPlatform.isMusl || stdenv.hostPlatform.isWasi) [
    (lib.cmakeFeature "LIBCXX_HAS_MUSL_LIBC" "1")
  ]
  ++
    lib.optionals
      (
        lib.versionAtLeast release_version "18"
        && !useLLVM
        && stdenv.hostPlatform.libc == "glibc"
        && !stdenv.hostPlatform.isStatic
      )
      [
        (lib.cmakeFeature "LIBCXX_ADDITIONAL_LIBRARIES" "gcc_s")
      ]
  ++ lib.optionals (lib.versionAtLeast release_version "18" && stdenv.hostPlatform.isFreeBSD) [
    # Name and documentation claim this is for libc++abi, but its man effect is adding `-lunwind`
    # to the libc++.so linker script. We want FreeBSD's so-called libgcc instead of libunwind.
    (lib.cmakeBool "LIBCXXABI_USE_LLVM_UNWINDER" false)
  ]
  ++ lib.optionals useLLVM [
    (lib.cmakeBool "LIBCXX_USE_COMPILER_RT" true)
  ]
  ++
    lib.optionals (useLLVM && !stdenv.hostPlatform.isFreeBSD && lib.versionAtLeast release_version "16")
      [
        (lib.cmakeFeature "LIBCXX_ADDITIONAL_LIBRARIES" "unwind")
      ]
  ++ lib.optionals stdenv.hostPlatform.isWasm [
    (lib.cmakeBool "LIBCXX_ENABLE_THREADS" false)
    (lib.cmakeBool "LIBCXX_ENABLE_FILESYSTEM" false)
    (lib.cmakeBool "LIBCXX_ENABLE_EXCEPTIONS" false)
  ]
  ++ lib.optionals (cxxabi != null && cxxabi.libName == "cxxrt") [
    (lib.cmakeBool "LIBCXX_ENABLE_NEW_DELETE_DEFINITIONS" true)
  ];

  cmakeFlags = [
    (lib.cmakeFeature "LLVM_ENABLE_RUNTIMES" (lib.concatStringsSep ";" runtimes))
  ]
  ++
    lib.optionals
      (
        stdenv.hostPlatform.isWasm
        || (lib.versions.major release_version == "12" && stdenv.hostPlatform.isDarwin)
      )
      [
        (lib.cmakeBool "CMAKE_CXX_COMPILER_WORKS" true)
      ]
  ++ lib.optionals stdenv.hostPlatform.isWasm [
    (lib.cmakeBool "CMAKE_C_COMPILER_WORKS" true)
    (lib.cmakeBool "UNIX" true) # Required otherwise libc++ fails to detect the correct linker
  ]
  ++ cxxCMakeFlags
  ++ lib.optionals (cxxabi == null) cxxabiCMakeFlags
  ++ devExtraCmakeFlags;

in

stdenv.mkDerivation (
  finalAttrs:
  {
    pname = "libcxx";
    inherit version cmakeFlags;

    src =
      if monorepoSrc != null then
        runCommand "libcxx-src-${version}" { inherit (monorepoSrc) passthru; } (
          ''
            mkdir -p "$out/llvm"
          ''
          + (lib.optionalString (lib.versionAtLeast release_version "14") ''
            cp -r ${monorepoSrc}/cmake "$out"
          '')
          + ''
            cp -r ${monorepoSrc}/libcxx "$out"
            cp -r ${monorepoSrc}/llvm/cmake "$out/llvm"
            cp -r ${monorepoSrc}/llvm/utils "$out/llvm"
          ''
          + (lib.optionalString (lib.versionAtLeast release_version "14") ''
            cp -r ${monorepoSrc}/third-party "$out"
          '')
          + (lib.optionalString (lib.versionAtLeast release_version "20") ''
            cp -r ${monorepoSrc}/libc "$out"
          '')
          + ''
            cp -r ${monorepoSrc}/runtimes "$out"
          ''
          + (lib.optionalString (cxxabi == null) ''
            cp -r ${monorepoSrc}/libcxxabi "$out"
          '')
        )
      else
        src;

    outputs = [
      "out"
      "dev"
    ];

    preConfigure = lib.optionalString stdenv.hostPlatform.isMusl ''
      patchShebangs utils/cat_files.py
    '';

    patches = lib.optionals (lib.versionOlder release_version "16") (
      lib.optional (lib.versions.major release_version == "15")
        # See:
        #   - https://reviews.llvm.org/D133566
        #   - https://github.com/NixOS/nixpkgs/issues/214524#issuecomment-1429146432
        # !!! Drop in LLVM 16+
        (
          fetchpatch {
            url = "https://github.com/llvm/llvm-project/commit/57c7bb3ec89565c68f858d316504668f9d214d59.patch";
            hash = "sha256-B07vHmSjy5BhhkGSj3e1E0XmMv5/9+mvC/k70Z29VwY=";
          }
        )
      ++ [
        (substitute {
          src = ../libcxxabi/wasm.patch;
          substitutions = [
            "--replace-fail"
            "/cmake/"
            "/llvm/cmake/"
          ];
        })
      ]
      ++ lib.optional stdenv.hostPlatform.isMusl (substitute {
        src = ./libcxx-0001-musl-hacks.patch;
        substitutions = [
          "--replace-fail"
          "/include/"
          "/libcxx/include/"
        ];
      })
    );

    nativeBuildInputs = [
      cmake
      ninja
      python3
    ]
    ++ lib.optional stdenv.hostPlatform.isDarwin fixDarwinDylibNames
    ++ lib.optional (cxxabi != null) lndir;

    buildInputs = [
      cxxabi
    ]
    ++ lib.optionals (useLLVM && !stdenv.hostPlatform.isWasm && !stdenv.hostPlatform.isFreeBSD) [
      libunwind
    ];

    # libc++.so is a linker script which expands to multiple libraries,
    # libc++.so.1 and libc++abi.so or the external cxxabi. ld-wrapper doesn't
    # support linker scripts so the external cxxabi needs to be symlinked in
    postInstall =
      lib.optionalString (cxxabi != null) ''
        lndir ${lib.getDev cxxabi}/include $dev/include/c++/v1
        lndir ${lib.getLib cxxabi}/lib $out/lib
        libcxxabi=$out/lib/lib${cxxabi.libName}.a
      ''
      # LIBCXX_STATICALLY_LINK_ABI_IN_STATIC_LIBRARY=ON doesn't work for LLVM < 16 or
      # external cxxabi libraries so merge libc++abi.a into libc++.a ourselves.

      # GNU binutils emits objects in LIFO order in MRI scripts so after the merge
      # the objects are in reversed order so a second MRI script is required so the
      # objects in the archive are listed in proper order (libc++.a, libc++abi.a)
      + lib.optionalString (cxxabi != null || lib.versionOlder release_version "16") ''
        libcxxabi=''${libcxxabi-$out/lib/libc++abi.a}
        if [[ -f $out/lib/libc++.a && -e $libcxxabi ]]; then
          $AR -M <<MRI
            create $out/lib/libc++.a
            addlib $out/lib/libc++.a
            addlib $libcxxabi
            save
            end
        MRI
          $AR -M <<MRI
            create $out/lib/libc++.a
            addlib $out/lib/libc++.a
            save
            end
        MRI
        fi
      '';

    passthru = {
      isLLVM = true;
    };

    meta = llvm_meta // {
      homepage = "https://libcxx.llvm.org/";
      description = "C++ standard library";
      longDescription = ''
        libc++ is an implementation of the C++ standard library, targeting C++11,
        C++14 and above.
      '';
      # "All of the code in libc++ is dual licensed under the MIT license and the
      # UIUC License (a BSD-like license)":
      license = with lib.licenses; [
        mit
        ncsa
      ];
    };
  }
  // (
    if (lib.versionOlder release_version "16" || lib.versionAtLeast release_version "17") then
      {
        postPatch =
          (lib.optionalString
            (lib.versionAtLeast release_version "14" && lib.versionOlder release_version "15")
            ''
              # fix CMake error when static and LIBCXXABI_USE_LLVM_UNWINDER=ON. aren't
              # building unwind so don't need to depend on it
              substituteInPlace libcxx/src/CMakeLists.txt \
                --replace-fail "add_dependencies(cxx_static unwind)" "# add_dependencies(cxx_static unwind)"
            ''
          )
          + ''
            cd runtimes
          '';
      }
    else
      {
        sourceRoot = "${finalAttrs.src.name}/runtimes";
      }
  )
)
