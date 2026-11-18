$ErrorActionPreference='Stop'
$installer = (Get-ChildItem delivery/*.exe).FullName
$root = Join-Path $env:LOCALAPPDATA 'Programs\OpenDirector'
$tempRoot=[IO.Path]::GetTempPath()
$env:OPENDIRECTOR_ROOT = Join-Path $tempRoot 'OpenDirector 测试 projects'
function Run-Installer($package=$installer) { if ((Start-Process $package -ArgumentList '/S' -Wait -PassThru).ExitCode -ne 0) { throw 'Silent installation failed' } }
if ($env:OD_PREVIOUS_INSTALLER) { Run-Installer $env:OD_PREVIOUS_INSTALLER } else { Run-Installer }
New-Item -ItemType Directory -Force .work | Out-Null
# Seed a dummy model through the real store, never a user key. Compare exact
# bytes across upgrade + uninstall, outside the installed resources.
& "$root\app\python\python.exe" -I -c "from opendirector.installation import data_root; from opendirector.infrastructure.model_configs import ModelConfigs; ModelConfigs(data_root()).save('agent','http://127.0.0.1:1/v1','offline-fixture','fake-test-key')"
if ($LASTEXITCODE) { throw 'Model fixture failed' }
$settings=Join-Path $env:OPENDIRECTOR_ROOT '.opendirector\models.json'
$hash=(Get-FileHash $settings).Hash
$env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS='--remote-debugging-port=19222'
npm install --prefix scripts --no-save --no-package-lock playwright-core@1.56.1
if ($LASTEXITCODE) { throw 'Smoke driver setup failed' }
function Test-UI($phase) {
    $modern=(Get-Content "$root\app\VERSION").Trim() -eq '0.1.4-desktop.4'
    $occupied=$null
    if ($modern) {
        # This used to prevent OpenDirector from starting. Never accept a
        # connection: a successful GUI proves it reached the new listener.
        $occupied=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,48765)
        $occupied.Start()
    }
    $hostPath=$env:PATH
    try {
        $env:PATH="$env:SystemRoot\System32;$env:SystemRoot;$env:SystemRoot\System32\WindowsPowerShell\v1.0"
        $proc=Start-Process "$root\app\OpenDirector.exe" -PassThru
    } finally { $env:PATH=$hostPath }
    try {
        node scripts/smoke.mjs $phase
        if ($LASTEXITCODE) { Get-Content "$env:LOCALAPPDATA\OpenDirector\Desktop\desktop.log" -Tail 12 | ForEach-Object { Write-Output "::warning::$_" }; throw "UI probe failed: $phase" }
        if ($modern) {
            $proc.Refresh()
            if (!$proc.CloseMainWindow()) { throw 'Could not request window close' }
            Start-Sleep -Milliseconds 800
            $proc.Refresh()
            if ($proc.HasExited -or $proc.MainWindowHandle -ne 0) { throw 'Close must hide, not exit' }
            $second=Start-Process "$root\app\OpenDirector.exe" -PassThru
            if (!$second.WaitForExit(5000) -or $second.ExitCode -ne 0) { throw 'Second launch did not hand off' }
            $until=[DateTime]::UtcNow.AddSeconds(5)
            do { $proc.Refresh(); if ($proc.MainWindowHandle -ne 0) { break }; Start-Sleep -Milliseconds 100 } while ([DateTime]::UtcNow -lt $until)
            if ($proc.MainWindowHandle -eq 0) { throw 'Second launch did not restore window' }
            Write-Output 'PASS: occupied legacy port, authenticated desktop, hide and single-instance restore'
        }
    } finally {
        if ($occupied) { $occupied.Stop() }
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

if ((Get-FileHash $settings).Hash -ne $hash) { throw 'Upgrade or uninstall changed credentials' }
