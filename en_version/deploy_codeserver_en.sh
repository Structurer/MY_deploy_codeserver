#!/bin/bash

# Deployment script: Install and configure code Server only (no Cloudflare Tunnel)
# Supports custom listening port
# Author: Trae Assistant
# Date: 2026-08-03

set -e

# ---------- Helper functions ----------

check_and_handle_dpkg_lock() {
    echo "Checking dpkg lock status..."
    if [ -f "/var/lib/dpkg/lock" ] || [ -f "/var/lib/dpkg/lock-frontend" ]; then
        echo "Detected dpkg lock file, attempting to release..."
        sudo fuser -vki -TERM /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend 2>/dev/null || true
        sudo dpkg --configure --pending 2>/dev/null || true
        sleep 3
    fi
}

restart_code_server() {
    echo "Checking code-server service status..."
    if systemctl list-unit-files | grep -q code-server@.service; then
        echo "Restarting code-server service to apply new configuration..."
        systemctl restart code-server@root 2>/dev/null || systemctl start code-server@root
        sleep 2
        systemctl status code-server@root --no-pager
    else
        echo "code-server service is not installed yet, skipping restart..."
    fi
}

# ---------- Entry ----------

echo ""
echo "=== Starting code Server deployment ==="

# ---------- 0. System update ----------
echo ""
echo "0. System update option..."
echo "System update may take a while, skip it?"
echo "1. Perform system update (recommended, ensure packages are up to date)"
echo "2. Skip system update (quick deploy, use existing packages)"
read -p "Please enter choice (1/2): " update_choice

if [ "$update_choice" = "1" ]; then
    echo ""
    echo "1. Updating system packages..."
    check_and_handle_dpkg_lock
    apt update && apt upgrade -y
else
    echo ""
    echo "1. Skipping system update..."
fi

# ---------- 2. Dependencies ----------
echo ""
echo "2. Installing necessary dependencies..."
check_and_handle_dpkg_lock
apt install -y curl

# ---------- 3. Install code-server ----------
echo ""
echo "3. Installing code Server..."
curl -fsSL https://code-server.dev/install.sh | sh

# ---------- 4. Configure: port + password ----------
echo ""
echo "4. Configuring code Server..."

# Custom port
echo "Enter the local port for code Server to listen on (1-65535, default 8080):"
while true; do
    read -p "Local port (press Enter for default 8080): " CODESERVER_PORT
    if [ -z "$CODESERVER_PORT" ]; then
        CODESERVER_PORT=8080
        echo "Using default port: $CODESERVER_PORT"
        break
    fi
    if [[ "$CODESERVER_PORT" =~ ^[0-9]+$ ]] && [ "$CODESERVER_PORT" -ge 1 ] && [ "$CODESERVER_PORT" -le 65535 ]; then
        echo "Using port: $CODESERVER_PORT"
        break
    else
        echo "Error: invalid port number, please enter a number between 1 and 65535"
    fi
done

# Password double confirmation
while true; do
    echo ""
    echo "Enter the login password for code Server:"
    read -s CODESERVER_PASSWORD
    echo ""
    echo "Confirm password:"
    read -s CODESERVER_PASSWORD_CONFIRM
    echo ""

    if [ "$CODESERVER_PASSWORD" = "$CODESERVER_PASSWORD_CONFIRM" ]; then
        echo "Password confirmed successfully!"
        break
    else
        echo "Error: passwords do not match, please try again"
    fi
done

mkdir -p /root/.config/code-server

CONFIG_FILE="/root/.config/code-server/config.yaml"

if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" << EOF
bind-addr: 127.0.0.1:$CODESERVER_PORT
auth: password
password: $CODESERVER_PASSWORD
cert: false
EOF
    echo "Configuration file created"
else
    sed -i "s/bind-addr: .*/bind-addr: 127.0.0.1:$CODESERVER_PORT/" "$CONFIG_FILE"
    sed -i "s/password: .*/password: $CODESERVER_PASSWORD/" "$CONFIG_FILE"
    echo "Port and password updated"
fi

# ---------- 5. Start service ----------
echo ""
echo "5. Starting and enabling code Server service..."
systemctl enable --now code-server@root
# Restart service to ensure port and password take effect
restart_code_server

echo ""
echo "=== code Server deployment complete ==="

# ---------- Verification + Access info ----------
echo ""
echo "=== Deployment complete, verifying service status ==="
echo ""
echo "code Server status:"
systemctl is-active code-server@root

echo ""
echo "=== Access information ==="
echo ""
echo "Local listening address: http://127.0.0.1:$CODESERVER_PORT"
echo ""
echo "Login password: $CODESERVER_PASSWORD"
echo ""
echo "Tip: To expose this service via a public domain, run deploy_tunnel.sh to forward this port through Cloudflare Tunnel."
echo "Example command:"
echo "  bash deploy_tunnel.sh"
echo "  Then enter: port $CODESERVER_PORT, domain code.example.com"
echo ""
echo "=== Complete ==="
