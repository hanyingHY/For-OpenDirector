$ErrorActionPreference='Stop'
$installer = (Get-ChildItem delivery/*.exe).FullName
$root = Join-Path $env:LOCALAPPDATA 'Programs\OpenDirector'
$tempRoot=[IO.Path]::GetTempPath()
$env:OPENDIRECTOR_ROOT = Join-Path $tempRoot 'OpenDirector 测试 projects'
function Run-Installer { if ((Start-Process $installer -ArgumentList '/S' -Wait -PassThru).ExitCode -ne 0) { throw 'Silent installation failed' } }
Run-Installer
$env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS='--remote-debugging-port=19222'
npm install --prefix scripts --no-save --no-package-lock playwright-core@1.56.1
if ($LASTEXITCODE) { throw 'Smoke driver setup failed' }
function Test-UI($phase) {
    $proc=Start-Process "$root\app\OpenDirector.exe" -PassThru
    try {
        node scripts/smoke.mjs $phase
        if ($LASTEXITCODE) { Get-Content "$env:LOCALAPPDATA\OpenDirector\Desktop\desktop.log" -Tail 12 | ForEach-Object { Write-Output "::warning::$_" }; throw "UI probe failed: $phase" }
    } finally {
        if (!$proc.HasExited) { $proc.Kill(); $proc.WaitForExit() }
    }
}
Test-UI 'create'
# Simulate an interrupted host, then reinstall without deleting projects.
Run-Installer
# Upstream intentionally retains the last writer's lease for 60s on crash.
Start-Sleep -Seconds 61
Test-UI 'reopen'
$projectFiles=@(Get-ChildItem $env:OPENDIRECTOR_ROOT -File -Recurse)
if (!$projectFiles.Count) { throw 'No project files to preserve' }
Start-Process "$root\Uninstall.exe" -ArgumentList '/S',("_?="+$root) -Wait
if (Test-Path "$root\app\OpenDirector.exe") { throw 'Uninstall failed' }
foreach ($f in $projectFiles) { if (!(Test-Path $f.FullName)) { throw 'Uninstall removed project data' } }
