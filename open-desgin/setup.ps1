param(
    [string]$RepoUrl = "https://github.com/nexu-io/open-design.git",
    [string]$TargetDir = "open-design",
    [switch]$SkipClone
)

$ErrorActionPreference = "Stop"

Write-Host "=== Open Design + OpenCode CLI Setup ===" -ForegroundColor Cyan
Write-Host ""

# ── Kiểm tra Docker ──────────────────────────────────
$needDocker = $false
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "[FAIL] Docker not found. Install Docker Desktop first." -ForegroundColor Red
    $needDocker = $true
}
if (-not (Get-Command docker compose -ErrorAction SilentlyContinue)) {
    Write-Host "[FAIL] Docker Compose not found." -ForegroundColor Red
    $needDocker = $true
}
if ($needDocker) { exit 1 }

# ── Clone / vào thư mục ──────────────────────────────
if (-not $SkipClone) {
    if (Test-Path $TargetDir) {
        Write-Host "[WARN] $TargetDir already exists. Use -SkipClone to reuse." -ForegroundColor Yellow
        $go = Read-Host "Overwrite? (y/N)"
        if ($go -ne "y") { exit 0 }
        Remove-Item -Recurse -Force $TargetDir
    }
    Write-Host "[INFO] Cloning $RepoUrl ..." -ForegroundColor Green
    git clone $RepoUrl $TargetDir
    if (-not $?) { Write-Host "[FAIL] Clone failed" -ForegroundColor Red; exit 1 }
    Set-Location "$TargetDir/deploy"
} else {
    if (-not (Test-Path "deploy/docker-compose.yml")) {
        Set-Location deploy -ErrorAction Stop
    }
    Write-Host "[INFO] Using existing directory: $(Get-Location)" -ForegroundColor Green
}

# ── File .env ────────────────────────────────────────
if (-not (Test-Path ".env")) {
    Copy-Item ".env.example" ".env"
    Write-Host "[INFO] Created .env from .env.example" -ForegroundColor Green
}

# ── Sinh token ───────────────────────────────────────
$token = ""
if (Get-Command node -ErrorAction SilentlyContinue) {
    $token = node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
} else {
    $token = -join ((48..57) + (97..102) | Get-Random -Count 64 | ForEach-Object { [char]$_ })
}
Write-Host "[INFO] Generated OD_API_TOKEN: $token" -ForegroundColor Green

$envContent = Get-Content ".env" -Raw
if ($envContent -match 'OD_API_TOKEN=.+') {
    $envContent = $envContent -replace 'OD_API_TOKEN=.+', "OD_API_TOKEN=$token"
} elseif ($envContent -match 'OD_API_TOKEN=$') {
    $envContent = $envContent -replace 'OD_API_TOKEN=$', "OD_API_TOKEN=$token"
} else {
    $envContent += "`nOD_API_TOKEN=$token"
}
Set-Content ".env" -Value $envContent
Write-Host "[INFO] Updated OD_API_TOKEN in .env" -ForegroundColor Green

# ── Build images ─────────────────────────────────────
Write-Host "[INFO] Building Docker images..." -ForegroundColor Cyan
docker compose build
if (-not $?) { Write-Host "[FAIL] Build failed" -ForegroundColor Red; exit 1 }

# ── Start services ──────────────────────────────────
Write-Host "[INFO] Starting services..." -ForegroundColor Cyan
docker compose up -d
if (-not $?) { Write-Host "[FAIL] Start failed" -ForegroundColor Red; exit 1 }

# ── Chờ daemon healthy ──────────────────────────────
Write-Host "[INFO] Waiting for daemon (up to 60s)..." -ForegroundColor Cyan
$healthy = $false
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 2
    $status = docker compose ps --format json open-design 2>$null | ConvertFrom-Json
    if ($status.State -eq "running" -and $status.Health -eq "healthy") {
        $healthy = $true
        break
    }
    Write-Host "." -NoNewline
}
if (-not $healthy) {
    Write-Host ""
    Write-Host "[FAIL] Daemon not healthy. Check logs: docker compose logs open-design" -ForegroundColor Red
    exit 1
}

# ── Verify ──────────────────────────────────────────
Write-Host "" -ForegroundColor Green
Write-Host "=== Verification ===" -ForegroundColor Cyan

$health = curl.exe -s http://127.0.0.1:7456/api/health 2>$null
if ($health) {
    Write-Host "[OK] /api/health → $health" -ForegroundColor Green
} else {
    Write-Host "[FAIL] /api/health not responding" -ForegroundColor Red
}

$version = curl.exe -s http://127.0.0.1:7456/api/version 2>$null
if ($version) {
    Write-Host "[OK] /api/version → $version" -ForegroundColor Green
}

# ── Done ─────────────────────────────────────────────
Write-Host ""
Write-Host "=== Setup Complete ===" -ForegroundColor Cyan
Write-Host "Web UI:  http://127.0.0.1:7456" -ForegroundColor Yellow
Write-Host "Token:   $token" -ForegroundColor Yellow
Write-Host ""
Write-Host "OpenCode CLI:" -ForegroundColor White
Write-Host "  docker compose exec tools opencode run 'your prompt'" -ForegroundColor Gray
Write-Host ""
Write-Host "od CLI:" -ForegroundColor White
Write-Host "  docker compose exec tools od daemon status" -ForegroundColor Gray
