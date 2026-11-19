#Requires -Version 7.0
# Run only on the candidate acceptance VM AFTER the uninstall/retention check.
# Reuse its project and key fixture; do not manufacture a replacement workspace.
$ErrorActionPreference='Stop'
trap { Write-Output ("::error::Prior updater line {0}: {1}" -f $_.InvocationInfo.ScriptLineNumber,$_.Exception.Message); exit 1 }
$app=Join-Path $env:LOCALAPPDATA 'Programs\OpenDirector\app'
$env:OPENDIRECTOR_ROOT=Join-Path ([IO.Path]::GetTempPath()) 'OpenDirector 测试 projects'
$project=(Get-Content .work/check.json -Raw | ConvertFrom-Json).project
$settings=Join-Path $env:OPENDIRECTOR_ROOT '.opendirector\models.json'
$keyHash=(Get-FileHash $settings).Hash
$previous=(Get-Content delivery/candidate.json -Raw | ConvertFrom-Json).previous.version
$version=(Get-Content desktop/VERSION).Trim()
function Wait-Project($expected){
    $end=[DateTime]::UtcNow.AddSeconds(180)
    do {
        if ((Test-Path "$app\VERSION") -and (Get-Content "$app\VERSION").Trim() -eq $expected -and (Test-Path "$env:LOCALAPPDATA\OpenDirector\Desktop\session.bin")) {
            $result=& "$app\OpenDirector-CLI.exe" project list 2>$null
            if (!$LASTEXITCODE -and $project -in (($result | ConvertFrom-Json).projects.id)) { return }
        }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $end)
    throw "Did not reopen the preserved project on $expected"
}
if ((Start-Process $env:OD_PREVIOUS_INSTALLER -ArgumentList '/S' -Wait -PassThru).ExitCode) { throw 'Prior install failed' }
$hostProc=Start-Process "$app\OpenDirector.exe" -PassThru
try {
    Wait-Project $previous
    & "$app\python\python.exe" -I -X utf8 verification/stage_previous.py delivery $version $previous
    if ($LASTEXITCODE) { throw 'Old updater could not authenticate release' }
    & "$app\python\python.exe" -I -X utf8 "$app\update.py" --install $version $hostProc.Id
    if ($LASTEXITCODE) { throw 'Old updater rejected handoff' }
    Start-Sleep -Seconds 2
    if ((Get-Content "$app\VERSION").Trim() -ne $previous -or $hostProc.HasExited) { throw 'Installer did not wait for the running host' }
    # No fake parent and no force kill on the successful path. WM_CLOSE from
    # Process.CloseMainWindow is a non-title-bar shutdown in WinForms.
    $hostProc.Refresh()
    if (!$hostProc.CloseMainWindow() -or !$hostProc.WaitForExit(20000)) { throw 'Old desktop did not shut down' }
    Wait-Project $version
    if ((Get-FileHash $settings).Hash -ne $keyHash) { throw 'Automatic upgrade changed model credentials' }
    Write-Output "PASS: actual installed $previous updater → signed $version → parent exit → restarted desktop, same project ID and key file"
} finally {
    if (!$hostProc.HasExited) { $hostProc.Kill(); $hostProc.WaitForExit() }
}
