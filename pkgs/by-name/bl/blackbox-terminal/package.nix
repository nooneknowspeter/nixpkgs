{
  lib,
  stdenv,
  fetchFromGitLab,
  fetchpatch,
  meson,
  ninja,
  pkg-config,
  vala,
  gtk4,
  vte-gtk4,
  json-glib,
  sassc,
  libadwaita,
  pcre2,
  libsixel,
  libxml2,
  librsvg,
  libgee,
  callPackage,
  python3,
  desktop-file-utils,
  wrapGAppsHook4,
  sixelSupport ? false,
}:

let
  marble = callPackage ./marble.nix { };
in
stdenv.mkDerivation rec {
  pname = "blackbox";
  version = "0.14.0";

  src = fetchFromGitLab {
    domain = "gitlab.gnome.org";
    owner = "raggesilver";
    repo = "blackbox";
    rev = "v${version}";
    hash = "sha256-ebwh9WTooJuvYFIygDBn9lYC7+lx9P1HskvKU8EX9jw=";
  };

  patches = [
    # Fix closing confirmation dialogs not showing
    (fetchpatch {
      url = "https://gitlab.gnome.org/raggesilver/blackbox/-/commit/3978c9b666d27adba835dd47cf55e21515b6d6d9.patch";
      hash = "sha256-L/Ci4YqYNzb3F49bUwEWSjzr03MIPK9A5FEJCCct+7A=";
    })

    # Fix build with GCC 14
    # https://gitlab.gnome.org/GNOME/vala/-/merge_requests/369#note_1986032
    # https://gitlab.gnome.org/raggesilver/blackbox/-/merge_requests/143
    (fetchpatch {
      url = "https://gitlab.gnome.org/raggesilver/blackbox/-/commit/2f45717f1c18f710d9b9fbf21830027c8f0794e7.patch";
      hash = "sha256-VlXttqOTbhD6Rp7ZODgsafOjeY+Lb5sZP277bC9ENXU=";
    })
  ];

  postPatch = ''
    substituteInPlace build-aux/meson/postinstall.py \
      --replace-fail 'gtk-update-icon-cache' 'gtk4-update-icon-cache'
    patchShebangs build-aux/meson/postinstall.py
  '';

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    vala
    sassc
    wrapGAppsHook4
    python3
    desktop-file-utils # For update-desktop-database
  ];
  buildInputs = [
    gtk4
    (vte-gtk4.overrideAttrs (
      old:
      {
        src = fetchFromGitLab {
          domain = "gitlab.gnome.org";
          owner = "GNOME";
          repo = "vte";
          rev = "3c8f66be867aca6656e4109ce880b6ea7431b895";
          hash = "sha256-vz9ircmPy2Q4fxNnjurkgJtuTSS49rBq/m61p1B43eU=";
        };
        patches = lib.optional (old ? patches) (lib.head old.patches);
        postPatch = (old.postPatch or "") + ''
          patchShebangs src/box_drawing_generate.sh
        '';
      }
      // lib.optionalAttrs sixelSupport {
        buildInputs = old.buildInputs ++ [ libsixel ];
        mesonFlags = old.mesonFlags ++ [ "-Dsixel=true" ];
      }
    ))
    json-glib
    marble
    libadwaita
    pcre2
    libxml2
    librsvg
    libgee
  ];

  mesonFlags = [ "-Dblackbox_is_flatpak=false" ];

  meta = {
    description = "Beautiful GTK 4 terminal";
    mainProgram = "blackbox";
    homepage = "https://gitlab.gnome.org/raggesilver/blackbox";
    changelog = "https://gitlab.gnome.org/raggesilver/blackbox/-/raw/v${version}/CHANGELOG.md";
    license = lib.licenses.gpl3Plus;
    maintainers = with lib.maintainers; [
      chuangzhu
      linsui
    ];
    platforms = lib.platforms.linux;
  };
}
