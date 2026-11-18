# Run the upstream native turn regression against the *packaged* interpreter,
# business services, skills and executable. Model transport is deterministic.
$ErrorActionPreference='Stop'
$base = (Resolve-Path '.work/app').Path
$src = (Get-Item '.work/OpenDirector-*' | Select-Object -First 1).FullName
$env:PATH = "$base\git\cmd;$base\media;$env:PATH"
$env:PYTHONUTF8='1'
$env:OPENDIRECTOR_REAL_CLI='1'
$env:OPENDIRECTOR_REAL_CLI_WORKER='1'
# Test tools are added only after NSIS has finished and never enter the installer.
& "$base\python\python.exe" -m pip install pytest==9.1.1
if ($LASTEXITCODE) { throw 'pytest installation failed' }
Push-Location $src
try {
  & "$base\python\python.exe" -m pytest -q 'tests/test_native_runtime.py::test_real_opencode_default_hello_saves_direct_reply[plain]' 'tests/test_native_runtime.py::test_real_opencode_native_skill_and_gateway_write[False-default]' *> "$base\..\agent-test.txt"
  $status=$LASTEXITCODE
  Get-Content "$base\..\agent-test.txt" -Tail 45
  if ($status) {
    Get-Content "$base\..\agent-test.txt" -Tail 10 | ForEach-Object { Write-Output "::warning::$_" }; throw 'Native bundled Agent regression failed'
  }
} finally { Pop-Location }
