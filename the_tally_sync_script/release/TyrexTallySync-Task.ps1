param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Install", "Uninstall")]
    [string]$Action
)

$ErrorActionPreference = "Stop"
$TaskName = "TyrexTallySync"
$Folder = Split-Path -Parent $MyInvocation.MyCommand.Path
$Exe = Join-Path $Folder "TyrexTallySync.exe"
$EnvFile = Join-Path $Folder "tally_sync.env"

function Write-EnvKey([string]$Path, [string]$Key, [string]$Value) {
    $lines = @()
    if (Test-Path $Path) {
        $lines = Get-Content -Path $Path -ErrorAction SilentlyContinue | Where-Object { $_ -notmatch ("^" + [regex]::Escape($Key) + "=") }
    }
    $lines += "$Key=$Value"
    Set-Content -Path $Path -Value $lines -Encoding ASCII
}

if ($Action -eq "Uninstall") {
    Write-Host "Stopping Tyrex Tally Sync..."
    try { Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue } catch { }
    Get-Process -Name "TyrexTallySync" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    try {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
        Write-Host "Startup task removed."
    } catch {
        schtasks /Delete /TN $TaskName /F 2>$null | Out-Null
        Write-Host "Startup task was not found or already removed."
    }
    Write-Host "Uninstalled. The exe and tally_sync.log are still in this folder."
    exit 0
}

if (-not (Test-Path $Exe)) {
    throw "TyrexTallySync.exe was not found in $Folder"
}

$since = Get-Date -Format "yyyy-MM-dd"
$until = (Get-Date).AddYears(1).ToString("yyyy-MM-dd")

if (-not (Test-Path $EnvFile)) {
    @(
        "TALLY_HOST=localhost",
        "TALLY_PORT=9007",
        "TALLY_TIMEOUT=30"
    ) | Set-Content -Path $EnvFile -Encoding ASCII
}

Write-EnvKey $EnvFile "SYNC_SINCE" $since
Write-EnvKey $EnvFile "SYNC_UNTIL" $until
if (-not (Select-String -Path $EnvFile -Pattern "^SYNC_INTERVAL_SECONDS=" -Quiet)) {
    Write-EnvKey $EnvFile "SYNC_INTERVAL_SECONDS" "60"
}

try {
    $taskAction = New-ScheduledTaskAction -Execute $Exe -Argument "--watch" -WorkingDirectory $Folder
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -DontStopOnIdleEnd `
        -StartWhenAvailable `
        -ExecutionTimeLimit ([TimeSpan]::Zero) `
        -MultipleInstances IgnoreNew
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $TaskName -Action $taskAction -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
    try { Start-ScheduledTask -TaskName $TaskName } catch { }
} catch {
    Write-Host "ScheduledTask cmdlets failed: $($_.Exception.Message)"
    Write-Host "Trying schtasks fallback..."
    $tr = "`"$Exe`" --watch"
    $create = schtasks /Create /TN $TaskName /TR $tr /SC ONLOGON /RL LIMITED /F
    if ($LASTEXITCODE -ne 0) {
        throw "Could not create startup task. $($create | Out-String)"
    }
    schtasks /Run /TN $TaskName | Out-Null
}
Start-Process -FilePath $Exe -ArgumentList "--watch" -WorkingDirectory $Folder -WindowStyle Hidden

Write-Host ""
Write-Host "Installed Tyrex Tally Sync."
Write-Host "  Folder: $Folder"
Write-Host "  Starts at Windows logon / after restart"
Write-Host "  Syncs only while Tally is open with a company"
Write-Host "  Waits 1 minute between syncs"
Write-Host "  Job cards from $since through $until"
Write-Host "  Watcher stops after $until"
Write-Host "  Log: $(Join-Path $Folder 'tally_sync.log')"
Write-Host ""
Write-Host "Keep tally_sync.env in this folder. Set TALLY_PORT=9007 for cloud Tally."
