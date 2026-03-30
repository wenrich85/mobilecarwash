# Deployment Guide — Driveway Detail Co

DigitalOcean Droplet + GitHub Actions + systemd + Nginx.

## Architecture

```
GitHub (push to main)
  → GitHub Actions (build Elixir release)
    → SCP to Droplet
      → systemd restarts the service
        → Nginx reverse proxy (SSL via Let's Encrypt)
          → Phoenix app on port 4000
```

**Infrastructure:**
- **Droplet**: Ubuntu 22.04, 2GB RAM ($12/mo)
- **Managed PostgreSQL**: 1GB ($15/mo)
- **Spaces**: S3-compatible object storage for photos ($5/mo)
- **Domain**: drivewaydetail.co → Droplet IP

## Initial Setup

### 1. Create DigitalOcean Resources

1. **Droplet**: Ubuntu 22.04, Basic, 2GB RAM / 1 vCPU ($12/mo)
2. **Managed PostgreSQL**: Single node, 1GB ($15/mo)
   - Create database: `mobile_car_wash`
   - Note the connection string
3. **Spaces**: Create bucket `driveway-detail-photos` in your region
   - Generate API key under API → Spaces Keys

### 2. Point DNS

Add A records:
- `drivewaydetail.co` → Droplet IP
- `www.drivewaydetail.co` → Droplet IP

### 3. Run Server Setup

```bash
# Copy setup script to server and run it
scp deploy/setup-server.sh root@YOUR_DROPLET_IP:/tmp/
ssh root@YOUR_DROPLET_IP 'bash /tmp/setup-server.sh'
```

This installs Erlang/Elixir, creates the `deploy` user, sets up systemd and Nginx.

### 4. Configure Environment

```bash
# SSH in and create the .env file
ssh deploy@YOUR_DROPLET_IP
cp /opt/mobile_car_wash/.env.example /opt/mobile_car_wash/.env
nano /opt/mobile_car_wash/.env
# Fill in all values (see .env.example for reference)
```

Generate secrets locally:
```bash
mix phx.gen.secret  # Use for SECRET_KEY_BASE
mix phx.gen.secret  # Use for TOKEN_SIGNING_SECRET
```

### 5. SSL Certificate

```bash
ssh root@YOUR_DROPLET_IP
certbot --nginx -d drivewaydetail.co -d www.drivewaydetail.co
# Certbot auto-renews via systemd timer
```

### 6. GitHub Secrets

In your repo → Settings → Secrets → Actions, add:

| Secret | Value |
|--------|-------|
| `DEPLOY_HOST` | Your Droplet IP |
| `DEPLOY_USER` | `deploy` |
| `DEPLOY_SSH_KEY` | SSH private key for deploy user |

Generate the deploy key:
```bash
ssh-keygen -t ed25519 -f deploy_key -C "github-deploy"
# Add deploy_key.pub to server: ssh deploy@IP 'cat >> ~/.ssh/authorized_keys' < deploy_key.pub
# Add deploy_key (private) as DEPLOY_SSH_KEY secret in GitHub
```

### 7. First Deploy

Push to main — GitHub Actions will build and deploy automatically.

Or trigger manually: Actions → Deploy → Run workflow.

## How Deploys Work

1. **Push to main** triggers `.github/workflows/deploy.yml`
2. GitHub Actions:
   - Installs Elixir/Erlang
   - Compiles in `MIX_ENV=prod`
   - Builds assets (Tailwind CSS, esbuild JS)
   - Creates a release tarball
   - SCPs it to the Droplet
3. On the server:
   - Backs up current release to `previous/`
   - Unpacks new release to `current/`
   - Runs database migrations
   - `systemctl restart mobile_car_wash`

## Rollback

```bash
ssh deploy@YOUR_DROPLET_IP
cd /opt/mobile_car_wash
mv current broken
mv previous current
sudo systemctl restart mobile_car_wash
```

## Monitoring

```bash
# Service status
sudo systemctl status mobile_car_wash

# Logs (systemd journal)
sudo journalctl -u mobile_car_wash -f

# Nginx access logs
sudo tail -f /var/log/nginx/access.log

# Connect to running app (IEx remote shell)
/opt/mobile_car_wash/current/bin/mobile_car_wash remote
```

## File Layout on Server

```
/opt/mobile_car_wash/
├── .env                    # Environment variables
├── current/                # Active release
│   ├── bin/
│   │   ├── server          # Start with PHX_SERVER=true
│   │   ├── migrate         # Run migrations
│   │   └── mobile_car_wash # Release commands
│   └── lib/
├── previous/               # Previous release (rollback)
└── deploy/                 # Config templates (optional)

/etc/systemd/system/mobile_car_wash.service
/etc/nginx/sites-available/mobile_car_wash
/etc/letsencrypt/live/drivewaydetail.co/
```

## Monthly Cost

| Resource | Cost |
|----------|------|
| Droplet (2GB) | $12 |
| Managed PostgreSQL | $15 |
| Spaces (5GB) | $5 |
| Domain | ~$12/yr |
| **Total** | **~$33/mo** |
