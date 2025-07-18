{ lib
, stdenv
, fetchFromGitHub
, makeWrapper
, pkg-config
, python3Packages
,
}:

stdenv.mkDerivation rec {
  pname = "talculate";
  version = "unstable-2025-07-16";

  src = fetchFromGitHub {
    owner = "nooneknowspeter";
    repo = "talculate";
    rev = "385270d881cd0ab20a7c4c0bfecf7106f72f0f10";
    hash = "sha256-uC6VX2cD+aY3aMt+2dOy5OhpmQEO1a2L+3vhl6z3J50=";
  };

  nativeBuildInputs = [
    makeWrapper
    pkg-config
    python3Packages.wrapPython
  ];

  buildInputs = with python3Packages; [
    python
    linkify-it-py
    markdown-it-py
    mdit-py-plugins
    mdurl
    platformdirs
    pygments
    pyperclip
    pyyaml
    rich
    textual
    typing-extensions
    uc-micro-py
    xdg
  ];

  postInstall = ''
    wrapPythonPrograms
  '';

  meta = {
    description = "A programmer oriented tui calculator. simple keys. minimal ui";
    homepage = "https://github.com/nooneknowspeter/talculate";
    license = lib.licenses.unfree;
    maintainers = with lib.maintainers; [
      nooneknowspeter
    ];
    mainProgram = "talculate";
    platforms = lib.platforms.all;
  };
}
