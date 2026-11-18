# Run the upstream native turn regression against the *packaged* interpreter,
# business services, skills and executable. Model transport is deterministic.
$ErrorActionPreference='Stop'
$base = if ($env:OD_TEST_APP) { $env:OD_TEST_APP } else { (Resolve-Path '.work/app').Path }
$src = (Get-Item '.work/OpenDirector-*' | Select-Object -First 1).FullName
$env:PATH = "$base\git\cmd;$base\media;$env:PATH"
$env:PYTHONUTF8='1'
$env:OPENDIRECTOR_REAL_CLI='1'
$env:OPENDIRECTOR_REAL_CLI_WORKER='1'
# Test tools are added only after NSIS has finished and never enter the installer.
& "$base\python\python.exe" -m pip install pytest==9.1.1
if ($LASTEXITCODE) { throw 'pytest installation failed' }
# The upstream fixture emits a POSIX single-quoted multiword argument. Use
# double quotes in the deterministic model response: cmd.exe accepts these too.
# Tool name, catalog checks, project mutation and receipt assertions stay intact.
$case = Join-Path $src 'tests/test_native_runtime.py'
$old = Get-Content -Raw -Encoding utf8 $case
$adjusted = $old.Replace("--text 'Real OpenCode plan'", '--text \"Real OpenCode plan\"')
if ($old -eq $adjusted) { throw 'Fixture command changed upstream' }
[IO.File]::WriteAllText($case, $adjusted, [Text.UTF8Encoding]::new($false))
$trace=Join-Path ([IO.Path]::GetTempPath()) 'OD-agent-probe'
Push-Location $src
try {
  & "$base\python\python.exe" -m pytest --basetemp $trace -q 'tests/test_native_runtime.py::test_real_opencode_default_hello_saves_direct_reply[plain]' 'tests/test_native_runtime.py::test_real_opencode_native_skill_and_gateway_write[False-default]' *> "$base\..\agent-test.txt"
  $status=$LASTEXITCODE
  Get-Content "$base\..\agent-test.txt" -Tail 45
  if ($status) {
    # Only report tool errors from this disposable test's fake-model traces.
    Get-ChildItem $trace -Filter '*.opencode.jsonl' -Recurse | ForEach-Object {
      Get-Content $_.FullName | ForEach-Object {
        $part=($_ | ConvertFrom-Json).native.part
        if ($part.tool -eq 'bash') { Write-Output ('::warning::CLI output: '+(($part.state.output + ' ' + $part.state.error) -replace '[\r\n]',' ').Substring(0,[Math]::Min(1500,($part.state.output + ' ' + $part.state.error).Length))) }
      }
    }
    Get-Content "$base\..\agent-test.txt" -Tail 10 | ForEach-Object { Write-Output "::warning::$_" }; throw 'Native bundled Agent regression failed'
  }
} finally { [IO.File]::WriteAllText($case,$old,[Text.UTF8Encoding]::new($false)); Pop-Location }
