#!/bin/bash
# ============================================================
# Driveway Detail Co — Server Setup Script
# Run once on a fresh Ubuntu 22.04+ DigitalOcean Droplet
# Usage: ssh root@your-droplet < deploy/setup-server.sh
# ============================================================
set -e

echo "=== Setting up Driveway Detail Co server ==="

# --- System updates ---
apt-get update && apt-get upgrade -y
apt-get install -y curl git nginx certbot python3-certbot-nginx \
  build-essential autoconf m4 libncurses5-dev libssl-dev \
  libwxgtk3.2-dev libwxgtk-webview3.2-dev libgl1-mesa-dev \
  libglu1-mesa-dev libpng-dev libssh-dev unixodbc-dev xsltproc fop

# --- Create deploy user ---
if ! id -u deploy &>/dev/null; then
  adduser --disabled-password --gecos "" deploy
  usermod -aG sudo deploy
  # Allow deploy user to restart the service without password
  echo "deploy ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart mobile_car_wash, /usr/bin/systemctl stop mobile_car_wash, /usr/bin/systemctl start mobile_car_wash, /usr/bin/systemctl is-active mobile_car_wash" > /etc/sudoers.d/deploy
fi

# --- Install Erlang & Elixir via asdf (as deploy user) ---
su - deploy << 'DEPLOY_SETUP'
git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.14.0
echo '. "$HOME/.asdf/asdf.sh"' >> ~/.bashrc
source ~/.asdf/asdf.sh

asdf plugin add erlang
asdf plugin add elixir

asdf install erlang 27.0
asdf install elixir 1.18.4-otp-27
asdf global erlang 27.0
asdf global elixir 1.18.4-otp-27
DEPLOY_SETUP

# --- App directory ---
mkdir -p /opt/mobile_car_wash
chown deploy:deploy /opt/mobile_car_wash

# --- Systemd service ---
cp /opt/mobile_car_wash/deploy/mobile_car_wash.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable mobile_car_wash

# --- Nginx ---
cp /opt/mobile_car_wash/deploy/nginx.conf /etc/nginx/sites-available/mobile_car_wash
ln -sf /etc/nginx/sites-available/mobile_car_wash /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# --- SSL (run after DNS points to this server) ---
echo ""
echo "=== Server setup complete! ==="
echo ""
echo "Next steps:"
echo "  1. Point DNS for drivewaydetail.co to this server's IP"
echo "  2. Copy .env to /opt/mobile_car_wash/.env and fill in values"
echo "  3. Run: certbot --nginx -d drivewaydetail.co -d www.drivewaydetail.co"
echo "  4. Add GitHub secrets: DEPLOY_HOST, DEPLOY_USER (deploy), DEPLOY_SSH_KEY"
echo "  5. Push to main — GitHub Actions will build and deploy"
echo ""
