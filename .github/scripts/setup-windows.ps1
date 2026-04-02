# Path: .github/scripts/setup-windows.ps1
# Mục đích: Setup môi trường cho Windows runner
#   1. Cài Docker Linux engine bên trong WSL2
#   2. Cài + chạy ttyd trong WSL2 (expose web terminal)
#   3. WSL2 tự forward port 7681 ra Windows host
#      → Caddy (trong WSL2 Docker) proxy vào host.docker.internal:7681
$ErrorActionPreference = "Stop"

# ── Helper: chạy bash trong WSL2 Ubuntu ──────────────────────────────
function Invoke-WSL {
    param([string]$Script)
    wsl -d Ubuntu -- bash -c $Script
    if ($LASTEXITCODE -ne 0) {
        throw "WSL2 command failed (exit $LASTEXITCODE)"
    }
}

# ── Lấy WSL_WORKSPACE từ GITHUB_ENV (đã set bởi detect-os.sh) ────────
$wslWorkspace = $env:WSL_WORKSPACE
if (-not $wslWorkspace) {
    throw "WSL_WORKSPACE is not set. Did detect-os.sh run successfully?"
}
Write-Host "WSL_WORKSPACE: $wslWorkspace"

# ════════════════════════════════════════════════════════════════════
#  PHẦN 1 — Kiểm tra WSL2
# ════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "=== [setup-windows] Checking WSL2 ==="
wsl --status
wsl -l -v

# Kiểm tra Ubuntu có sẵn không
$distros = wsl -l --quiet 2>$null
if ($distros -notmatch "Ubuntu") {
    Write-Host "Ubuntu not found, installing..."
    wsl --install -d Ubuntu --no-launch
    # Chờ distro khởi tạo
    Start-Sleep -Seconds 20
    Write-Host "✅ Ubuntu installed"
}
else {
    Write-Host "✅ Ubuntu already available"
}

# ════════════════════════════════════════════════════════════════════
#  PHẦN 2 — Cài Docker Engine bên trong WSL2
# ════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "=== [setup-windows] Installing Docker Engine in WSL2 ==="

Invoke-WSL @'
  set -euo pipefail
  export DEBIAN_FRONTEND=noninteractive

  if command -v docker &>/dev/null; then
    echo "Docker already installed: $(docker --version)"
  else
    echo "Installing Docker Engine via get.docker.com..."
    sudo apt-get update -qq
    curl -fsSL https://get.docker.com | sudo sh
    echo "✅ Docker installed: $(docker --version)"
  fi

  # Start dockerd nếu chưa chạy
  if sudo docker info &>/dev/null 2>&1; then
    echo "dockerd already running"
  else
    echo "Starting dockerd..."
    sudo dockerd > /tmp/dockerd.log 2>&1 &
    # Chờ dockerd sẵn sàng (tối đa 30s)
    for i in $(seq 1 30); do
      sudo docker info &>/dev/null 2>&1 && break
      sleep 1
    done
    sudo docker info &>/dev/null 2>&1 \
      && echo "✅ dockerd is running" \
      || { echo "❌ dockerd failed to start"; cat /tmp/dockerd.log; exit 1; }
  fi

  sudo docker info | grep -E "OSType|Server Version"
'@

Write-Host "✅ Docker Linux engine ready in WSL2"

# ════════════════════════════════════════════════════════════════════
#  PHẦN 3 — Cài + chạy ttyd trong WSL2
# ════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "=== [setup-windows] Installing and starting ttyd in WSL2 ==="

Invoke-WSL @'
  set -euo pipefail

  # Cài ttyd nếu chưa có
  if command -v ttyd &>/dev/null; then
    echo "ttyd already installed"
  else
    echo "Installing ttyd..."
    # Thử apt trước
    sudo apt-get install -y ttyd 2>/dev/null && echo "✅ ttyd via apt" || {
      # Fallback: download binary từ GitHub releases
      TTYD_VER="1.7.7"
      echo "Downloading ttyd binary v${TTYD_VER}..."
      sudo curl -fsSL \
        "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VER}/ttyd.x86_64" \
        -o /usr/local/bin/ttyd
      sudo chmod +x /usr/local/bin/ttyd
      echo "✅ ttyd binary installed"
    }
  fi

  # Stop instance cũ nếu có
  pkill -x ttyd 2>/dev/null && echo "Stopped existing ttyd" || true
  sleep 1

  # Start ttyd mới
  echo "Starting ttyd on 0.0.0.0:7681..."
  nohup ttyd \
    -W \
    -p 7681 \
    -t fontSize=15 \
    -t "theme={\"background\":\"#1e1e1e\"}" \
    bash \
    > /tmp/ttyd.log 2>&1 &

  sleep 2

  # Verify
  if pgrep -x ttyd > /dev/null; then
    echo "✅ ttyd running (PID=$(pgrep -x ttyd))"
  else
    echo "❌ ttyd failed to start"
    cat /tmp/ttyd.log
    exit 1
  fi

  ss -tlnp | grep 7681 \
    && echo "✅ Port 7681 listening in WSL2" \
    || echo "⚠️  Port 7681 not detected yet (may still be starting)"
'@

# ── Verify port forward từ Windows host (WSL2 auto port-forward) ─────
Write-Host ""
Write-Host "=== [setup-windows] Verifying port 7681 from Windows host ==="
Start-Sleep -Seconds 3
$portCheck = netstat -ano 2>$null | Select-String ":7681"
if ($portCheck) {
    Write-Host "✅ Port 7681 visible from Windows host"
    Write-Host $portCheck
}
else {
    Write-Host "⚠️  Port 7681 not yet visible from Windows host"
    Write-Host "    WSL2 auto port-forward may take a moment — continuing..."
}

Write-Host ""
Write-Host "✅ [setup-windows] All done"