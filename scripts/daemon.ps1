# =============================================================================
# wechat-claude-code Windows daemon manager (PowerShell + Task Scheduler)
# Usage: powershell -ExecutionPolicy Bypass -File scripts/daemon.ps1 {start|stop|restart|status|logs}
#
# Uses schtasks.exe for non-admin compatibility.
# =============================================================================

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('start', 'stop', 'restart', 'status', 'logs')]
    [string]$Command
)

$ErrorActionPreference = 'Stop'

$TASK_NAME = 'wechat-claude-code'
$PROJECT_DIR = Resolve-Path (Join-Path $PSScriptRoot '..')
$DATA_DIR = if ($env:WCC_DATA_DIR) { $env:WCC_DATA_DIR } else { Join-Path $env:APPDATA 'wechat-claude-code' }
$NODE_BIN = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $NODE_BIN) {
    $NODE_BIN = Join-Path $env:ProgramFiles 'nodejs\node.exe'
}
if (-not (Test-Path $NODE_BIN)) {
    Write-Error "Cannot find node.exe. Please install Node.js >= 18."
    exit 1
}

$null = New-Item -ItemType Directory -Force -Path (Join-Path $DATA_DIR 'logs')

# =============================================================================
# Helpers
# =============================================================================

function Test-TaskExists {
    # Suppress stderr noise when task doesn't exist
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    schtasks /query /tn $TASK_NAME 2>&1 | Out-Null
    $ErrorActionPreference = $prev
    return ($LASTEXITCODE -eq 0)
}

function Invoke-Schtasks {
    # Run schtasks, suppress its verbose output, return $true on success
    # Must lower ErrorActionPreference because schtasks writes to stderr
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    $out = schtasks @args 2>&1
    $ErrorActionPreference = $prev
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "schtasks error: $out"
        return $false
    }
    return $true
}

# =============================================================================
# Start
# =============================================================================

function Start-Daemon {
    # Always recreate so the task uses the latest script path / node path
    if (Test-TaskExists) {
        Stop-Daemon
    }

    $scriptPath = Join-Path $PROJECT_DIR 'dist\main.js'
    $logFile = Join-Path $DATA_DIR 'logs\stdout.log'

    # Build schtasks /create command (non-admin compatible)
    # Use absolute paths so working directory does not matter
    # /sc ONLOGON = trigger on user logon
    # /f = force overwrite if exists
    $tr = "`"$NODE_BIN`" `"$scriptPath`" start >> `"$logFile`" 2>&1"

    $result = Invoke-Schtasks /create /tn $TASK_NAME /f /sc ONLOGON /delay 0000:30 `
        /tr $tr `
        /it `
        /ru $env:USERNAME

    if (-not $result) {
        # Fallback: try without /it (interactive)
        $result = Invoke-Schtasks /create /tn $TASK_NAME /f /sc ONLOGON /delay 0000:30 `
            /tr $tr `
            /ru $env:USERNAME
    }

    if (-not $result) {
        Write-Error "Failed to create scheduled task. Try running PowerShell as Administrator."
        exit 1
    }

    # Start immediately
    schtasks /run /tn $TASK_NAME 2>&1 | Out-Null

    Write-Host "Started wechat-claude-code daemon (Windows Task Scheduler)"
    Write-Host "  Task: $TASK_NAME"
    Write-Host "  Node: $NODE_BIN"
    Write-Host "  Dir:  $PROJECT_DIR"
    Write-Host "  Log:  $logFile"
}

# =============================================================================
# Stop
# =============================================================================

function Stop-Daemon {
    if (Test-TaskExists) {
        schtasks /end /tn $TASK_NAME 2>&1 | Out-Null
        schtasks /delete /tn $TASK_NAME /f 2>&1 | Out-Null
        Write-Host "Removed scheduled task: $TASK_NAME"
    } else {
        Write-Host "No scheduled task found"
    }

    # Kill any running node processes for this daemon
    $procs = Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" | Where-Object {
        $_.CommandLine -match [regex]::Escape($PROJECT_DIR)
    }
    if ($procs) {
        $procs | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        Write-Host "Stopped running node processes"
    }

    Write-Host "Stopped wechat-claude-code daemon"
}

# =============================================================================
# Restart
# =============================================================================

function Restart-Daemon {
    Stop-Daemon
    Start-Sleep -Seconds 1
    Start-Daemon
}

# =============================================================================
# Status
# =============================================================================

function Get-DaemonStatus {
    if (-not (Test-TaskExists)) {
        Write-Host "Not running (no scheduled task)"
        return
    }

    # Use CSV format to avoid locale-specific text parsing issues
    $csvLine = (schtasks /query /tn $TASK_NAME /fo CSV /nh 2>$null) | Where-Object { $_.Trim() } | Select-Object -First 1
    $statusText = "Unknown"
    if ($csvLine) {
        $parts = $csvLine.Trim('"') -split '","'
        if ($parts.Count -ge 3) {
            $statusText = $parts[2].Trim('"')
        }
    }
    Write-Host "Scheduled Task: $statusText"

    # Check process
    $procs = Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" | Where-Object {
        $_.CommandLine -match [regex]::Escape($PROJECT_DIR)
    }
    if ($procs) {
        Write-Host "Process: Running (PID: $($procs[0].ProcessId))"
    } else {
        Write-Host "Process: Not running"
    }
}

# =============================================================================
# Logs
# =============================================================================

function Show-Logs {
    $logDir = Join-Path $DATA_DIR 'logs'
    if (-not (Test-Path $logDir)) {
        Write-Host "No logs found"
        return
    }

    $latestBridge = Get-ChildItem $logDir -Filter 'bridge-*.log' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($latestBridge) {
        Write-Host "=== $($latestBridge.Name) (last 20 lines) ==="
        Get-Content $latestBridge.FullName -Tail 20 -Encoding UTF8
        Write-Host ""
    }

    foreach ($f in @('stdout.log', 'stderr.log')) {
        $path = Join-Path $logDir $f
        if (Test-Path $path) {
            Write-Host "=== $f (last 20 lines) ==="
            Get-Content $path -Tail 20 -Encoding UTF8
            Write-Host ""
        }
    }
}

# =============================================================================
# Dispatch
# =============================================================================

switch ($Command) {
    'start'   { Start-Daemon }
    'stop'    { Stop-Daemon }
    'restart' { Restart-Daemon }
    'status'  { Get-DaemonStatus }
    'logs'    { Show-Logs }
}
