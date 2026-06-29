#!/bin/bash

# ============================================================
# IGRIS AWS EC2 Server Setup Script
# Ubuntu 22.04 LTS — installs Docker, deploys backend
# ============================================================
set -e

echo ""
echo "╔══════════════════════════════════════╗"
echo "║   IGRIS Server Setup — Starting...   ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── 1. System update ─────────────────────────────────────────
echo "▶  Updating system packages..."
sudo apt-get update -y -q
sudo apt-get install -y -q unzip curl ca-certificates

# ── 2. Install Docker (modern method, Ubuntu 22.04+) ─────────
if ! command -v docker &> /dev/null; then
    echo "▶  Installing Docker..."
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    echo "deb [arch=$(dpkg --print-architecture) \
signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update -y -q
    sudo apt-get install -y -q docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin

    # Allow ubuntu user to run docker without sudo
    sudo usermod -aG docker ubuntu
    echo "✅ Docker installed."
else
    echo "✅ Docker already installed: $(docker --version)"
fi

# ── 3. Docker Compose CLI plugin check ───────────────────────
if ! docker compose version &> /dev/null; then
    echo "▶  Installing Docker Compose plugin..."
    sudo apt-get install -y -q docker-compose-plugin
fi
echo "✅ Docker Compose: $(docker compose version)"

# ── 4. Open firewall port 8080 ───────────────────────────────
echo "▶  Configuring UFW firewall..."
sudo ufw allow 8080/tcp 2>/dev/null || true
sudo ufw allow OpenSSH 2>/dev/null || true
echo "✅ Firewall configured."

# ── 5. Extract backend zip ───────────────────────────────────
echo "▶  Extracting backend files..."
# Fix any existing permissions that might block unzip
if [ -d ~/igris_backend ]; then
    echo "▶  Fixing existing folder permissions..."
    chmod -R u+rwX ~/igris_backend 2>/dev/null || true
fi
mkdir -p ~/igris_backend
unzip -o ~/igris_backend.zip -d ~/igris_backend || true
rm -f ~/igris_backend.zip

# Ensure proper permissions after unzip (Windows ZIP files might lose +x on directories)
echo "▶  Ensuring correct file and directory permissions..."
find ~/igris_backend -path "*/node_modules" -prune -o -type d -exec chmod 755 {} + 2>/dev/null || true
find ~/igris_backend -path "*/node_modules" -prune -o -type f -exec chmod 644 {} + 2>/dev/null || true

# The zip is created from backend/* so files land directly in igris_backend/
BACKEND_DIR=~/igris_backend

if [ ! -f "$BACKEND_DIR/package.json" ]; then
    echo "❌ ERROR: package.json not found in $BACKEND_DIR"
    echo "   Contents of $BACKEND_DIR:"
    ls -la "$BACKEND_DIR"
    exit 1
fi
echo "✅ Files extracted to $BACKEND_DIR"

# ── 6. Start Docker containers ───────────────────────────────
echo "▶  Building and starting Docker containers..."
cd "$BACKEND_DIR"

# Use newgrp to pick up the docker group (in case this is the first install)
sudo docker compose -f docker-compose.prod.yml down --remove-orphans 2>/dev/null || true
sudo docker compose -f docker-compose.prod.yml build --no-cache
sudo docker compose -f docker-compose.prod.yml up -d

# ── 7. Wait for backend to be healthy ────────────────────────
echo "▶  Waiting for backend to become ready..."
MAX_WAIT=60
WAITED=0
until curl -sf http://localhost:8080/health &>/dev/null || [ $WAITED -ge $MAX_WAIT ]; do
    sleep 3
    WAITED=$((WAITED + 3))
    echo "   ... waiting ($WAITED s)"
done

if curl -sf http://localhost:8080/health &>/dev/null; then
    echo "✅ Backend is healthy!"
else
    echo "⚠️  Backend health check timed out — check logs:"
    sudo docker compose -f docker-compose.prod.yml logs --tail=40
fi

# ── 8. Summary ───────────────────────────────────────────────
echo ""
echo "╔═══════════════════════════════════════════════╗"
echo "║          ✅  DEPLOYMENT SUCCESSFUL!            ║"
echo "║                                               ║"
PUBLIC_IP=$(curl -sf http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "YOUR-EC2-IP")
echo "║  Backend URL:  http://${PUBLIC_IP}:8080/api    ║"
echo "║  Health:       http://${PUBLIC_IP}:8080/health ║"
echo "║                                               ║"
echo "║  Update your mobile app backend URL above!    ║"
echo "╚═══════════════════════════════════════════════╝"
echo ""
