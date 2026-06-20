#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${1:-https://github.com/nexu-io/open-design.git}"
TARGET_DIR="${2:-open-design}"

echo "=== Open Design + OpenCode CLI Setup ==="
echo ""

# ── Prerequisites ────────────────────────────────────
if ! command -v docker &>/dev/null; then
  echo "[FAIL] Docker not found"
  exit 1
fi
if ! docker compose version &>/dev/null; then
  echo "[FAIL] Docker Compose not found"
  exit 1
fi

# ── Clone ────────────────────────────────────────────
if [ ! -d "$TARGET_DIR" ]; then
  echo "[INFO] Cloning $REPO_URL ..."
  git clone "$REPO_URL" "$TARGET_DIR"
  cd "$TARGET_DIR/deploy"
else
  echo "[INFO] $TARGET_DIR exists, reusing"
  cd "$TARGET_DIR/deploy"
fi

# ── .env ─────────────────────────────────────────────
if [ ! -f .env ]; then
  cp .env.example .env
  echo "[INFO] Created .env"
fi

# ── Token ────────────────────────────────────────────
TOKEN=$(openssl rand -hex 32 2>/dev/null || node -e "console.log(require('crypto').randomBytes(32).toString('hex'))")
echo "[INFO] OD_API_TOKEN=$TOKEN"

if grep -q '^OD_API_TOKEN=' .env; then
  sed -i.bak "s/^OD_API_TOKEN=.*/OD_API_TOKEN=$TOKEN/" .env && rm -f .env.bak
else
  echo "OD_API_TOKEN=$TOKEN" >> .env
fi

# ── Build ────────────────────────────────────────────
echo "[INFO] Building images ..."
docker compose build

# ── Start ────────────────────────────────────────────
echo "[INFO] Starting services ..."
docker compose up -d

# ── Wait ─────────────────────────────────────────────
echo "[INFO] Waiting for daemon (up to 60s) ..."
for i in $(seq 1 30); do
  sleep 2
  STATUS=$(docker inspect open-design --format '{{.State.Health.Status}}' 2>/dev/null || echo "starting")
  if [ "$STATUS" = "healthy" ]; then
    echo " healthy"
    break
  fi
  printf "."
done
echo ""

# ── Verify ───────────────────────────────────────────
echo ""
echo "=== Verification ==="
HEALTH=$(curl -sf http://127.0.0.1:7456/api/health) && echo "[OK] /api/health → $HEALTH" || echo "[FAIL] /api/health"
VERSION=$(curl -sf http://127.0.0.1:7456/api/version) && echo "[OK] /api/version → $VERSION" || echo "[FAIL] /api/version"

# ── Done ─────────────────────────────────────────────
echo ""
echo "=== Setup Complete ==="
echo "Web UI:  http://127.0.0.1:7456"
echo "Token:   $TOKEN"
echo ""
echo "OpenCode CLI:"
echo "  docker compose exec tools opencode run 'your prompt'"
echo ""
echo "od CLI:"
echo "  docker compose exec tools od daemon status"
