{
  lib,
  buildDotnetModule,
  fetchFromGitHub,
  dotnetCorePackages,
  SDL2,
  libsecret,
  glib,
  gnutls,
  aria2,
  steam,
  gst_all_1,
  copyDesktopItems,
  makeDesktopItem,
  makeWrapper,
  useSteamRun ? true,
}:

let
  rev = "1.2.1";
in
buildDotnetModule rec {
  pname = "XIVLauncher";
  version = rev;

  src = fetchFromGitHub {
    owner = "goatcorp";
    repo = "XIVLauncher.Core";
    inherit rev;
    hash = "sha256-bGHUDPUrohcc/lLE647cicaEIYo9t1/anc2VeMJlsGc=";
    fetchSubmodules = true;
  };

  nativeBuildInputs = [
    copyDesktopItems
    makeWrapper
  ];

  buildInputs = with gst_all_1; [
    gstreamer
    gst-plugins-base
    gst-plugins-good
    gst-plugins-bad
    gst-plugins-ugly
    gst-libav
  ];

  projectFile = "src/XIVLauncher.Core/XIVLauncher.Core.csproj";
  nugetDeps = ./deps.json; # File generated with `nix-build -A xivlauncher.passthru.fetch-deps`

  # please do not unpin these even if they match the defaults, xivlauncher is sensitive to .NET versions
  dotnet-sdk = dotnetCorePackages.sdk_8_0;
  dotnet-runtime = dotnetCorePackages.runtime_8_0;

  dotnetFlags = [
    "-p:BuildHash=${rev}"
    "-p:PublishSingleFile=false"
  ];

  postPatch = ''
    substituteInPlace lib/FFXIVQuickLauncher/src/XIVLauncher.Common/Game/Patch/Acquisition/Aria/AriaHttpPatchAcquisition.cs \
      --replace-fail 'ariaPath = "aria2c"' 'ariaPath = "${aria2}/bin/aria2c"'
  '';

  postInstall = ''
    mkdir -p $out/share/pixmaps
    cp src/XIVLauncher.Core/Resources/logo.png $out/share/pixmaps/xivlauncher.png
  '';

  postFixup =
    lib.optionalString useSteamRun (
      let
        steam-run =
          (steam.override {
            extraPkgs = pkgs: [ pkgs.libunwind ];
            extraProfile = ''
              unset TZ
            '';
          }).run;
      in
      ''
        substituteInPlace $out/bin/XIVLauncher.Core \
          --replace-fail 'exec' 'exec ${steam-run}/bin/steam-run'
      ''
    )
    + ''
      wrapProgram $out/bin/XIVLauncher.Core --prefix GST_PLUGIN_SYSTEM_PATH_1_0 ":" "$GST_PLUGIN_SYSTEM_PATH_1_0"
      # the reference to aria2 gets mangled as UTF-16LE and isn't detectable by nix: https://github.com/NixOS/nixpkgs/issues/220065
      mkdir -p $out/nix-support
      echo ${aria2} >> $out/nix-support/depends
    '';

  executables = [ "XIVLauncher.Core" ];

  runtimeDeps = [
    SDL2
    libsecret
    glib
    gnutls
  ];

  desktopItems = [
    (makeDesktopItem {
      name = "xivlauncher";
      exec = "XIVLauncher.Core";
      icon = "xivlauncher";
      desktopName = "XIVLauncher";
      comment = meta.description;
      categories = [ "Game" ];
      startupWMClass = "XIVLauncher.Core";
    })
  ];

  meta = with lib; {
    description = "Custom launcher for FFXIV";
    homepage = "https://github.com/goatcorp/XIVLauncher.Core";
    license = licenses.gpl3;
    maintainers = with maintainers; [
      keysmashes
      witchof0x20
    ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "XIVLauncher.Core";
  };
}
