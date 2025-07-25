{
  lib,
  mkDerivation,

  cmake,
  extra-cmake-modules,
  makeWrapper,
  shared-mime-info,

  fetchpatch,
  qtbase,
  qtsvg,
  qttools,
  qtwebengine,
  qtxmlpatterns,

  poppler,

  karchive,
  kcompletion,
  kconfig,
  kcoreaddons,
  kcrash,
  kdoctools,
  ki18n,
  kiconthemes,
  kio,
  knewstuff,
  kparts,
  kpty,
  ktexteditor,
  ktextwidgets,
  kxmlgui,
  syntax-highlighting,

  libspectre,

  # Backends. Set to null if you want to omit from the build
  withAnalitza ? true,
  analitza,
  wtihJulia ? true,
  julia,
  withQalculate ? true,
  libqalculate,
  withLua ? true,
  luajit,
  withPython ? true,
  python3,
  withR ? true,
  R,
  withSage ? true,
  sage,
  sage-with-env ? sage.with-env,
}:

mkDerivation {
  pname = "cantor";

  nativeBuildInputs = [
    cmake
    extra-cmake-modules
    makeWrapper
    shared-mime-info
    qttools
  ];

  buildInputs = [
    qtbase
    qtsvg
    qtwebengine
    qtxmlpatterns

    poppler

    karchive
    kcompletion
    kconfig
    kcoreaddons
    kcrash
    kdoctools
    ki18n
    kiconthemes
    kio
    knewstuff
    kparts
    kpty
    ktexteditor
    ktextwidgets
    kxmlgui
    syntax-highlighting

    libspectre
  ]
  # backends
  ++ lib.optional withAnalitza analitza
  ++ lib.optional wtihJulia julia
  ++ lib.optional withQalculate libqalculate
  ++ lib.optional withLua luajit
  ++ lib.optional withPython python3
  ++ lib.optional withR R
  ++ lib.optional withSage sage-with-env;

  qtWrapperArgs = [
    "--prefix PATH : ${placeholder "out"}/bin"
  ]
  ++ lib.optional withSage "--prefix PATH : ${sage-with-env}/bin";

  # Causes failures on Hydra and ofborg from some reason
  enableParallelBuilding = false;

  patches = [
    # fix build for julia 1.1 from upstream
    (fetchpatch {
      url = "https://github.com/KDE/cantor/commit/ed9525ec7895c2251668d11218f16f186db48a59.patch?full_index=1";
      hash = "sha256-paq0e7Tl2aiUjBf1bDHLLUpShwdCQLICNTPNsXSoe5M=";
    })
  ];

  meta = {
    description = "Front end to powerful mathematics and statistics packages";
    homepage = "https://cantor.kde.org/";
    license = with lib.licenses; [
      bsd3
      cc0
      gpl2Only
      gpl2Plus
      gpl3Only
    ];
    maintainers = with lib.maintainers; [ hqurve ];
  };
}
