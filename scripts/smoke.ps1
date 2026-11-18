$ErrorActionPreference='Stop'
trap { Write-Output ("::error::Smoke line {0}: {1}" -f $_.InvocationInfo.ScriptLineNumber,$_.Exception.Message); exit 1 }
$installer = (Get-ChildItem delivery/*.exe).FullName
$root = Join-Path $env:LOCALAPPDATA 'Programs\OpenDirector'
$tempRoot=[IO.Path]::GetTempPath()
$env:OPENDIRECTOR_ROOT = Join-Path $tempRoot 'OpenDirector 测试 projects'
function Run-Installer($package=$installer) { if ((Start-Process $package -ArgumentList '/S' -Wait -PassThru).ExitCode -ne 0) { throw 'Silent installation failed' } }
if ($env:OD_PREVIOUS_INSTALLER) { Run-Installer $env:OD_PREVIOUS_INSTALLER } else { Run-Installer }
New-Item -ItemType Directory -Force .work | Out-Null
# Seed a dummy model through the real store, never a user key. Compare exact
# bytes across upgrade + uninstall, outside the installed resources.
& "$root\app\python\python.exe" -I -c "from opendirector.installation import data_root; from opendirector.infrastructure.model_configs import ModelConfigs; ModelConfigs(data_root()).save('agent','http://127.0.0.1:18919/v1','offline-fixture','fake-test-key')"
if ($LASTEXITCODE) { throw 'Model fixture failed' }
$settings=Join-Path $env:OPENDIRECTOR_ROOT '.opendirector\models.json'
$hash=(Get-FileHash $settings).Hash
$env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS='--remote-debugging-port=19222'
npm install --prefix scripts --no-save --no-package-lock playwright-core@1.56.1
if ($LASTEXITCODE) { throw 'Smoke driver setup failed' }
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class DesktopProbe {
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hwnd, uint msg, IntPtr wparam, IntPtr lparam);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
}
'@
function Test-UI($phase) {
    $modern=(Get-Content "$root\app\VERSION").Trim() -notmatch '^0\.1\.4-desktop\.[123]$'
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
        if ($LASTEXITCODE) { Get-Content "$env:LOCALAPPDATA\OpenDirector\Desktop\desktop.log" -Tail 12 -ErrorAction SilentlyContinue | ForEach-Object { Write-Output "::warning::$_" }; throw "UI probe failed: $phase" }
        if ($modern) {
            $proc.Refresh()
            # SC_CLOSE is the title-bar X. A bare WM_CLOSE from CloseMainWindow
            # is categorized by WinForms as a Task Manager shutdown, not UserClosing.
            $window=$proc.MainWindowHandle
            if (($window -eq [IntPtr]::Zero) -or ![DesktopProbe]::IsWindowVisible($window) -or ![DesktopProbe]::PostMessage($window,0x112,[IntPtr]0xF060,[IntPtr]::Zero)) { throw 'Could not request window close' }
            $until=[DateTime]::UtcNow.AddSeconds(5)
            while ([DesktopProbe]::IsWindowVisible($window) -and [DateTime]::UtcNow -lt $until) { Start-Sleep -Milliseconds 100 }
            if ($proc.HasExited -or [DesktopProbe]::IsWindowVisible($window)) { throw "Close did not hide main HWND; exited=$($proc.HasExited)" }
            $second=Start-Process "$root\app\OpenDirector.exe" -PassThru
            if (!$second.WaitForExit(5000) -or $second.ExitCode -ne 0) { throw 'Second launch did not hand off' }
            $until=[DateTime]::UtcNow.AddSeconds(5)
            # WinForms may recreate the native handle on Show. Identity is the
            # same live process + its visible OpenDirector main form, not HWND equality.
            do {
                $proc.Refresh(); $restored=$proc.MainWindowHandle
                if ($proc.MainWindowTitle -eq 'OpenDirector' -and [DesktopProbe]::IsWindowVisible($restored)) { break }
                Start-Sleep -Milliseconds 100
            } while ([DateTime]::UtcNow -lt $until)
            if (![DesktopProbe]::IsWindowVisible($restored) -or $proc.MainWindowTitle -ne 'OpenDirector') { throw "Second launch failed to restore window; original=$window current=$restored title=$($proc.MainWindowTitle) exited=$($proc.HasExited)" }
            $before=(Get-FileHash "$root\app\OpenDirector.exe").Hash
            $blocked=Start-Process $installer -ArgumentList '/S' -Wait -PassThru
            if (!$blocked.ExitCode -or $before -ne (Get-FileHash "$root\app\OpenDirector.exe").Hash -or $proc.HasExited) { throw 'Live install was not refused safely' }
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
# Broken user-selected root: startup must fail with actionable native diagnostics,
# not open an empty canvas or destroy the inaccessible workspace.
$validRoot=$env:OPENDIRECTOR_ROOT
$env:OPENDIRECTOR_ROOT=(New-TemporaryFile).FullName
try {
    $bad=Start-Process "$root\app\OpenDirector.exe" -PassThru
    $until=[DateTime]::UtcNow.AddSeconds(75)
    do {
        $message=(Get-Content "$env:LOCALAPPDATA\OpenDirector\Desktop\desktop.log" -Tail 15) -match 'Local service did not start.*服务启动失败'
        if ($message) { break }; Start-Sleep -Milliseconds 300
    } while ([DateTime]::UtcNow -lt $until)
    if (!$message) { throw 'Missing bilingual startup failure diagnostic' }
} finally {
    if ($bad -and !$bad.HasExited) { $bad.Kill(); $bad.WaitForExit() }
    Remove-Item -LiteralPath $env:OPENDIRECTOR_ROOT; $env:OPENDIRECTOR_ROOT=$validRoot
}
# An independent shell registration installed by another application is not ours.
$cmd='HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\OpenDirector-CLI.exe'
New-Item $cmd -Force | Out-Null
Set-Item $cmd -Value 'C:\independent\OpenDirector-CLI.exe'
$projectFiles=@(Get-ChildItem $env:OPENDIRECTOR_ROOT -File -Recurse)
if (!$projectFiles.Count) { throw 'No project files to preserve' }
Start-Process "$root\Uninstall.exe" -ArgumentList '/S',("_?="+$root) -Wait
if (Test-Path "$root\app\OpenDirector.exe") { throw 'Uninstall failed' }
foreach ($f in $projectFiles) { if (!(Test-Path $f.FullName)) { throw 'Uninstall removed project data' } }

if ((Get-FileHash $settings).Hash -ne $hash) { throw 'Upgrade or uninstall changed credentials' }

if ((Get-Item $cmd).GetValue('') -ne 'C:\independent\OpenDirector-CLI.exe') { throw 'Uninstall removed independent CLI' }
Remove-Item $cmd
