param(
    [ValidateSet('start','rebuild','stop','status','logs')][string]$Action = 'start',
    [switch]$NoBrowser
)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$projectName = 'resume-zhiguang'
function Test-DockerReady {
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = (Get-Command docker -ErrorAction Stop).Source
    $info.Arguments = 'info --format "{{.ServerVersion}}"'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($info)
    try {
        if (-not $process.WaitForExit(5000)) { $process.Kill(); return $false }
        return $process.ExitCode -eq 0
    } finally { $process.Dispose() }
}
function Invoke-Compose {
    & docker compose --project-name $projectName @args
    if ($LASTEXITCODE -ne 0) { throw "Docker Compose failed ($LASTEXITCODE). See the output above." }
}
try {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Install Docker Desktop with the WSL 2 / Linux containers backend first: https://docs.docker.com/desktop/setup/install/windows-install/'
    }
    # Docker BuildKit's client-side registry authentication needs the Windows proxy too.
    if (-not $env:HTTPS_PROXY) {
        $proxy = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
        if ($proxy.ProxyEnable -eq 1 -and $proxy.ProxyServer -match '^[a-zA-Z0-9.-]+:[0-9]+$') {
            $env:HTTPS_PROXY = 'http://' + $proxy.ProxyServer
            if (-not $env:HTTP_PROXY) { $env:HTTP_PROXY = $env:HTTPS_PROXY }
        }
    }
    if (-not (Test-DockerReady)) {
        $desktop = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
        if ($Action -in @('start','rebuild') -and (Test-Path -LiteralPath $desktop)) {
            Write-Host 'Starting Docker Desktop...'
            Start-Process -FilePath $desktop -WindowStyle Hidden
            $deadline = (Get-Date).AddSeconds(180)
            do {
                Start-Sleep -Seconds 3
                if (Test-DockerReady) { break }
            } while ((Get-Date) -lt $deadline)
        }
        if (-not (Test-DockerReady)) { throw 'Docker Engine is unavailable. Open Docker Desktop and resolve its startup error, then run this script again. No project data has been deleted.' }
    }
    if (-not (Test-Path -LiteralPath '.env')) { Copy-Item -LiteralPath '.env.example' -Destination '.env' }
    switch ($Action) {
        { $_ -in @('start','rebuild') } {
            Invoke-Compose config --quiet
            Write-Host 'First launch downloads images and builds the application; this can take several minutes.'
            if ($Action -eq 'rebuild') { Invoke-Compose build }
            Invoke-Compose up --detach --wait --wait-timeout 480
            $binding = (& docker compose --project-name $projectName port frontend 80).Trim()
            if ($LASTEXITCODE -ne 0 -or -not $binding) { throw 'Cannot determine the web address.' }
            $url = 'http://' + $binding
            Write-Host "Ready: $url" -ForegroundColor Green
            Write-Host 'Demo login: demo@example.com / DemoPass123! (local demo only)'
            if (-not $NoBrowser) { Start-Process $url }
        }
        'stop' { Invoke-Compose down; Write-Host 'Stopped. Database volumes and credentials are preserved.' }
        'status' { Invoke-Compose ps --all }
        'logs' { Invoke-Compose logs --tail 120 --follow }
    }
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host 'Troubleshooting: run status.cmd or logs.cmd. See ONE-CLICK.md.'
    exit 1
}
