{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  boto3,
  requests,
  setuptools,
  python,
}:

buildPythonPackage rec {
  pname = "metaflow";
  version = "2.15.20";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "Netflix";
    repo = "metaflow";
    tag = version;
    hash = "sha256-D4Pf2/xhEJ22kDmmxYS0PiT5k2BJ3CBfTJZ4GrvkI58=";
  };

  build-system = [
    setuptools
  ];

  dependencies = [
    boto3
    requests
  ];

  checkPhase = ''
    runHook preCheck

    export HOME="$TMPDIR"
    export USER="metaflow-test-user"

    pushd test/core
    ${python.interpreter} run_tests.py --num-parallel $NIX_BUILD_CORES \
      --tests FlowOptionsTest,BasicLogTest
    popd

    runHook postCheck
  '';

  pythonImportsCheck = [ "metaflow" ];

  meta = {
    description = "Open Source AI/ML Platform";
    homepage = "https://metaflow.org/";
    changelog = "https://github.com/Netflix/metaflow/releases/tag/${src.tag}";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [ kr7x ];
  };
}
