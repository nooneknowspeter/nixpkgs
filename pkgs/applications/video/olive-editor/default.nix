{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchpatch,
  pkg-config,
  which,
  frei0r,
  opencolorio,
  ffmpeg_6,
  cmake,
  wrapQtAppsHook,
  openimageio,
  openexr,
  portaudio,
  imath,
  qtwayland,
  qtmultimedia,
  qttools,
}:

let
  # https://github.com/olive-editor/olive/issues/2284
  # we patch support for 2.3+, but 2.5 fails
  openimageio' = openimageio.overrideAttrs (old: rec {
    version = "2.4.15.0";
    src = (
      old.src.override {
        tag = "v${version}";
        hash = "sha256-I2/JPmUBDb0bw7qbSZcAkYHB2q2Uo7En7ZurMwWhg/M=";
      }
    );

    # robin-map headers require c++17
    cmakeFlags = (old.cmakeFlags or [ ]) ++ [ (lib.cmakeFeature "CMAKE_CXX_STANDARD" "17") ];
  });
in

stdenv.mkDerivation {
  pname = "olive-editor";
  version = "unstable-2023-06-12";

  src = fetchFromGitHub {
    fetchSubmodules = true;
    owner = "olive-editor";
    repo = "olive";
    rev = "2036fffffd0e24b7458e724b9084ae99c9507c64";
    hash = "sha256-qee9/WTvTy5jWLowvZJOwAjrqznRhJR+u9dYsnCN/Qs=";
  };

  cmakeFlags = [
    "-DBUILD_QT6=1"
  ];

  patches = [
    (fetchpatch {
      # Taken from https://github.com/olive-editor/olive/pull/2294.
      name = "olive-editor-openimageio-2.3-compat.patch";
      url = "https://github.com/olive-editor/olive/commit/311eeb72944f93f873d1cd1784ee2bf423e1e7c2.patch";
      hash = "sha256-lswWn4DbXGH1qPvPla0jSgUJQXuqU7LQGHIPoXAE8ag=";
    })
  ];

  # https://github.com/olive-editor/olive/issues/2200
  postPatch = ''
    substituteInPlace ./app/node/project/serializer/serializer230220.cpp \
      --replace 'QStringRef' 'QStringView'
  '';

  nativeBuildInputs = [
    pkg-config
    which
    cmake
    wrapQtAppsHook
  ];

  buildInputs = [
    ffmpeg_6
    frei0r
    opencolorio
    openimageio'
    imath
    openexr
    portaudio
    qtwayland
    qtmultimedia
    qttools
  ];

  meta = with lib; {
    description = "Professional open-source NLE video editor";
    homepage = "https://www.olivevideoeditor.org/";
    downloadPage = "https://www.olivevideoeditor.org/download.php";
    license = licenses.gpl3;
    maintainers = [ maintainers.balsoft ];
    platforms = platforms.unix;
    # never built on aarch64-darwin since first introduction in nixpkgs
    broken = stdenv.hostPlatform.isDarwin && stdenv.hostPlatform.isAarch64;
    mainProgram = "olive-editor";
  };
}
