#!/usr/bin/env bash
# scripts/setup-vps.sh
# Run once on a fresh Hetzner/DigitalOcean Ubuntu 24.04 VPS as root.
# Usage: curl -fsSL https://raw.githubusercontent.com/.../setup-vps.sh | bash

set -euo pipefail

echo "==> Updating system packages..."
apt-get update && apt-get upgrade -y

echo "==> Installing Docker..."
curl -fsSL https://get.docker.com | sh
systemctl enable docker
systemctl start docker

echo "==> Installing docker compose plugin..."
apt-get install -y docker-compose-plugin

echo "==> Creating deploy user..."
useradd -m -s /bin/bash deploy || echo "User 'deploy' already exists"
usermod -aG docker deploy

echo "==> Setting up SSH for deploy user..."
mkdir -p /home/deploy/.ssh
# Paste your GitHub Actions public key here, or copy from root's authorized_keys
cp /root/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys
chown -R deploy:deploy /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
chmod 600 /home/deploy/.ssh/authorized_keys

echo "==> Creating app directories..."
mkdir -p /srv/engineerfamily
mkdir -p /srv/engineerfamily-preprod
chown -R deploy:deploy /srv/engineerfamily /srv/engineerfamily-preprod

echo "==> Configuring UFW firewall..."
apt-get install -y ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow http
ufw allow https
ufw --force enable

echo "==> Setting up log directory for Caddy..."
mkdir -p /var/log/caddy
# Caddy runs in Docker, logs go to container stdout by default.
# The Caddyfile 'log' directives write inside the container volume.

echo ""
echo "✅ VPS setup complete."
echo ""
echo "Next steps:"
echo "  1. Copy your .env file to /srv/engineerfamily/.env"
echo "  2. Add the GitHub Actions SSH public key to /home/deploy/.ssh/authorized_keys"
echo "  3. Push to main — the GitHub Action will do the first deploy"
echo ""
echo "To generate a Caddy basic-auth password hash, run:"
echo "  docker run --rm caddy:2-alpine caddy hash-password --plaintext 'yourpassword'"
