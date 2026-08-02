#!/bin/bash

# Deployment script: Standalone Cloudflare Tunnel deployment, supports multiple runs to append routes (single tunnel + multiple ingress)
# First run: create tunnel + first route + install and start service
# Subsequent runs: detect existing tunnel → append new domain+port route to ingress + bind DNS + restart service
# Author: Trae Assistant
# Date: 2026-08-03

set -e

# ---------- Path constants ----------
CLOUDFLARED_DIR="/etc/cloudflared"
ROUTES_FILE="$CLOUDFLARED_DIR/routes.conf"       # Format: "domain port" per line
TUNNEL_META_FILE="$CLOUDFLARED_DIR/tunnel.meta"   # Format: TUNNEL_NAME=xxx / TUNNEL_ID=xxx
CONFIG_FILE="$CLOUDFLARED_DIR/config.yml"
CERT_FILE="$HOME/.cloudflared/cert.pem"
SYSTEMD_SERVICE="/etc/systemd/system/cloudflared.service"

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

# Regenerate full ingress-format config.yml from routes.conf
regenerate_config() {
    local tunnel_id=$1
    {
        echo "tunnel: $tunnel_id"
        echo "credentials-file: /root/.cloudflared/$tunnel_id.json"
        echo "ingress:"
        while IFS=' ' read -r r_domain r_port; do
            [ -z "$r_domain" ] && continue
            echo "  - hostname: $r_domain"
            echo "    service: http://localhost:$r_port"
        done < "$ROUTES_FILE"
        echo "  - service: http_status:404"
    } > "$CONFIG_FILE"
    echo "Regenerated config.yml ($(wc -l < "$ROUTES_FILE") route rules total)"
}

# Save tunnel metadata
save_tunnel_meta() {
    cat > "$TUNNEL_META_FILE" << EOF
TUNNEL_NAME=$1
TUNNEL_ID=$2
EOF
}

# Load tunnel metadata (returns 0 on success, 1 on failure)
load_tunnel_meta() {
    if [ -f "$TUNNEL_META_FILE" ]; then
        # shellcheck disable=SC1090
        source "$TUNNEL_META_FILE"
        [ -n "$TUNNEL_NAME" ] && [ -n "$TUNNEL_ID" ] && return 0
    fi
    return 1
}

# Check if domain already exists in routes.conf (avoid duplicates)
domain_exists() {
    local target=$1
    [ ! -f "$ROUTES_FILE" ] && return 1
    awk '{print $1}' "$ROUTES_FILE" | grep -qxF "$target"
}

# Show all current routes
show_current_routes() {
    echo ""
    echo "--- Current route rules (from $ROUTES_FILE) ---"
    if [ ! -f "$ROUTES_FILE" ] || [ ! -s "$ROUTES_FILE" ]; then
        echo "(no routes yet)"
    else
        printf "%-2s  %-35s  %s\n" "#" "Domain" "Local Port"
        printf "%-2s  %-35s  %s\n" "--" "-----------------------------------" "----------"
        local idx=0
        while IFS=' ' read -r r_domain r_port; do
            [ -z "$r_domain" ] && continue
            idx=$((idx+1))
            printf "%-2d  %-35s  %s\n" "$idx" "$r_domain" "$r_port"
        done < "$ROUTES_FILE"
    fi
    echo "--------------------------------------------------"
}

# Cloudflare authorization logic (two branches merged into one)
run_cloudflared_login() {
    # Check qrencode
    if ! command -v qrencode &> /dev/null; then
        echo "Installing qrencode for QR code generation..."
        apt update && apt install -y qrencode
    fi

    echo "=== Cloudflare Account Authorization ==="
    echo "You can authorize using either of the following methods:"
    echo "- Via link: copy the URL below and open it in a browser"
    echo "- Via QR code: scan the QR code below with your phone camera"
    echo ""
    echo "=== Authorization instructions ==="
    echo "1. Choose either authorization method above"
    echo "2. Log in to your Cloudflare account in the browser"
    echo "3. Click the 'Authorize' button to complete authorization"
    echo "4. After successful authorization, press Enter to continue"
    echo ""

    cloudflared tunnel login > /tmp/auth_output.txt 2>&1 &
    AUTH_PID=$!

    echo "Generating authorization URL..."
    sleep 3

    AUTH_URL=$(grep -o "https://dash.cloudflare.com/argotunnel.*" /tmp/auth_output.txt)

    if [ -n "$AUTH_URL" ]; then
        echo ""
        echo "=== Method 1: Authorize via link ==="
        echo "Authorization URL:"
        echo "$AUTH_URL"
        echo ""
        echo "=== Method 2: Authorize via QR code ==="
        echo "Please scan the QR code below with your phone camera:"
        echo ""
        qrencode -t ASCII -s 1 -m 0 "$AUTH_URL"
        echo ""
        read -p "After authorization is complete, press Enter to continue: "
        wait $AUTH_PID 2>/dev/null
    else
        echo "Unable to retrieve authorization URL, running authorization command directly..."
        cloudflared tunnel login
    fi
}

# ---------- Entry ----------

echo ""
echo "=== Cloudflare Tunnel Deploy / Append Route ==="

# ---------- Determine first run vs append ----------
FIRST_DEPLOY=true
if load_tunnel_meta \
   && [ -f "$CERT_FILE" ] \
   && [ -f "$ROUTES_FILE" ] \
   && command -v cloudflared &> /dev/null; then
    FIRST_DEPLOY=false
fi

if $FIRST_DEPLOY; then
    echo ""
    echo "Detection: first deployment, will create a new Cloudflare Tunnel"
else
    echo ""
    echo "Detection: existing deployment found (TUNNEL_NAME=$TUNNEL_NAME, TUNNEL_ID=$TUNNEL_ID)"
    echo "Will append a new route rule to the existing tunnel"
    show_current_routes
fi

# ---------- Common: collect user input (domain + port) ----------
echo ""
echo "Step 1/4: Configure new forwarding rule"

# Port input
echo "Enter the local port to forward to (1-65535):"
while true; do
    read -p "Local port: " LOCAL_PORT
    if [[ "$LOCAL_PORT" =~ ^[0-9]+$ ]] && [ "$LOCAL_PORT" -ge 1 ] && [ "$LOCAL_PORT" -le 65535 ]; then
        break
    else
        echo "Error: invalid port number, please enter a number between 1 and 65535"
    fi
done

# Domain input
echo ""
echo "Enter the full domain (e.g., app.example.com):"
while true; do
    read -p "Full domain: " FULL_DOMAIN
    if [ -z "$FULL_DOMAIN" ]; then
        echo "Error: domain cannot be empty"
        continue
    fi
    if domain_exists "$FULL_DOMAIN"; then
        echo "Error: domain $FULL_DOMAIN already exists in the route table, please use a different domain"
        continue
    fi
    break
done

echo ""
echo "New rule: https://$FULL_DOMAIN  ->  http://localhost:$LOCAL_PORT"

# ---------- First deployment flow ----------
if $FIRST_DEPLOY; then

    echo ""
    echo "=== First deployment flow started ==="

    # --- 0. System update option ---
    echo ""
    echo "Step 2/4: System preparation"
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

    echo ""
    echo "2. Installing necessary dependencies..."
    check_and_handle_dpkg_lock
    apt install -y curl qrencode

    # --- 3. Install cloudflared ---
    echo ""
    echo "3. Installing Cloudflare Tunnel client..."
    curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o cloudflared.deb
    check_and_handle_dpkg_lock
    dpkg -i cloudflared.deb
    rm -f cloudflared.deb

    # --- 4. Cloudflare authorization ---
    echo ""
    echo "4. Cloudflare account authorization..."
    if [ -f "$CERT_FILE" ]; then
        echo "Existing Cloudflare certificate detected"
        echo "Please choose an action:"
        echo "1. Use existing certificate"
        echo "2. Re-authorize (overwrite existing certificate)"
        read -p "Please enter choice (1/2): " cert_choice
        if [ "$cert_choice" = "2" ]; then
            echo "Deleting existing certificate..."
            rm -f "$CERT_FILE"
            run_cloudflared_login
        else
            echo "Using existing certificate"
        fi
    else
        run_cloudflared_login
    fi

    # --- Verify authorization ---
    echo ""
    echo "5. Verifying Cloudflare authorization..."
    if [ ! -f "$CERT_FILE" ]; then
        echo "Error: Cloudflare authorization failed, please re-run the authorization step"
        exit 1
    fi
    echo "Cloudflare authorization successful!"

    # --- 6. Create tunnel ---
    echo ""
    echo "6. Creating Cloudflare Tunnel..."
    TUNNEL_NAME="custom-tunnel"
    TUNNEL_ID=""

    echo "Attempting to create tunnel '$TUNNEL_NAME'..."
    TUNNEL_CREATION_OUTPUT=$(cloudflared tunnel create "$TUNNEL_NAME" 2>&1 || echo "Command failed: $?")
    echo "Create command output: $TUNNEL_CREATION_OUTPUT"

    TUNNEL_ID=$(echo "$TUNNEL_CREATION_OUTPUT" | grep "Created tunnel" | grep "with id" | awk -F 'id ' '{print $2}' | tr -d '\n')
    echo "Extracted Tunnel ID: '$TUNNEL_ID'"

    # Same name already exists → choose existing / create new name
    if [ -z "$TUNNEL_ID" ] && echo "$TUNNEL_CREATION_OUTPUT" | grep -q "tunnel with name already exists"; then
        echo "Detected that tunnel '$TUNNEL_NAME' already exists"
        echo "Please choose an action:"
        echo "1. Use existing tunnel"
        echo "2. Create a tunnel with a new name"
        read -p "Please enter choice (1/2): " tunnel_choice

        if [ "$tunnel_choice" = "1" ]; then
            echo "Fetching existing tunnel list..."
            MAX_RETRIES=3
            RETRY_COUNT=0
            TUNNEL_LIST=""

            while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
                TUNNEL_LIST=$(cloudflared tunnel list 2>&1)
                if [ $? -eq 0 ] && echo "$TUNNEL_LIST" | grep -q -E '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'; then
                    break
                fi
                echo "Attempting to re-authorize..."
                cloudflared tunnel login
                RETRY_COUNT=$((RETRY_COUNT + 1))
            done

            if [ -z "$TUNNEL_LIST" ] || ! echo "$TUNNEL_LIST" | grep -q -E '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'; then
                echo "Error: unable to fetch a valid tunnel list, please try again later"
                exit 1
            fi

            echo "Debug info: tunnel list contents:"
            echo "$TUNNEL_LIST"
            echo "---------------------------------------------------------------"

            TUNNEL_ITEMS=()
            while IFS= read -r line; do
                echo "$line" | grep -q -E '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' && TUNNEL_ITEMS+=("$line")
            done <<< "$TUNNEL_LIST"

            if [ ${#TUNNEL_ITEMS[@]} -eq 0 ]; then
                echo "Error: no existing tunnels found"
                exit 1
            fi

            echo "No.  ID                                   NAME              CREATED"
            echo "---------------------------------------------------------------"
            for i in "${!TUNNEL_ITEMS[@]}"; do
                index=$((i+1))
                tunnel_line=${TUNNEL_ITEMS[$i]}
                tunnel_id=$(echo "$tunnel_line" | awk '{print $1}')
                tunnel_name=$(echo "$tunnel_line" | awk '{print $2}')
                tunnel_created=$(echo "$tunnel_line" | awk '{print $3 " " $4 " " $5 " " $6 " " $7}')
                printf "%2d   %s   %-16s   %s\n" "$index" "$tunnel_id" "$tunnel_name" "$tunnel_created"
            done

            read -p "Enter the number of the tunnel to use: " tunnel_index
            if [[ "$tunnel_index" =~ ^[0-9]+$ ]] && [ "$tunnel_index" -ge 1 ] && [ "$tunnel_index" -le "${#TUNNEL_ITEMS[@]}" ]; then
                selected_index=$((tunnel_index-1))
                selected_tunnel=${TUNNEL_ITEMS[$selected_index]}
                TUNNEL_ID=$(echo "$selected_tunnel" | awk '{print $1}')
                TUNNEL_NAME=$(echo "$selected_tunnel" | awk '{print $2}')

                echo "Selected tunnel: ID=$TUNNEL_ID, NAME=$TUNNEL_NAME"

                CREDENTIALS_FILE="/root/.cloudflared/$TUNNEL_ID.json"
                if [ ! -f "$CREDENTIALS_FILE" ]; then
                    echo "Missing credentials file for this tunnel locally, deleting and recreating..."
                    cloudflared tunnel delete "$TUNNEL_ID" 2>&1 || true
                    CREATE_RESULT=$(cloudflared tunnel create "$TUNNEL_NAME" 2>&1)
                    NEW_TUNNEL_ID=$(echo "$CREATE_RESULT" | grep "Created tunnel" | grep "with id" | awk -F 'id ' '{print $2}' | tr -d '\n')
                    if [[ "$NEW_TUNNEL_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
                        TUNNEL_ID="$NEW_TUNNEL_ID"
                    else
                        echo "Error: failed to recreate tunnel"
                        exit 1
                    fi
                fi
            else
                echo "Error: invalid input"
                exit 1
            fi
        else
            read -p "New tunnel name: " NEW_TUNNEL_NAME
            [ -z "$NEW_TUNNEL_NAME" ] && NEW_TUNNEL_NAME="custom-tunnel-$(date +%s)"
            TUNNEL_CREATION_OUTPUT=$(cloudflared tunnel create "$NEW_TUNNEL_NAME" 2>&1 || echo "Command failed: $?")
            TUNNEL_ID=$(echo "$TUNNEL_CREATION_OUTPUT" | grep "Created tunnel" | grep "with id" | awk -F 'id ' '{print $2}' | tr -d '\n')
            if [[ "$TUNNEL_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
                TUNNEL_NAME="$NEW_TUNNEL_NAME"
            else
                echo "Error: failed to create tunnel"
                exit 1
            fi
        fi
    elif [ -z "$TUNNEL_ID" ]; then
        echo "Error: failed to create Cloudflare Tunnel"
        echo "Output: $TUNNEL_CREATION_OUTPUT"
        exit 1
    fi

    echo "Successfully created/selected tunnel: $TUNNEL_NAME (ID=$TUNNEL_ID)"

    # --- Save tunnel metadata + initialize route table ---
    echo ""
    echo "7. Writing persistent configuration..."
    mkdir -p "$CLOUDFLARED_DIR"
    save_tunnel_meta "$TUNNEL_NAME" "$TUNNEL_ID"
    echo "$FULL_DOMAIN $LOCAL_PORT" > "$ROUTES_FILE"

    regenerate_config "$TUNNEL_ID"

    # --- Install and start systemd service ---
    echo ""
    echo "8. Installing and starting Cloudflare Tunnel service..."
    if [ -f "$SYSTEMD_SERVICE" ]; then
        echo "Detected existing cloudflared service, uninstalling old service first..."
        cloudflared service uninstall
    fi
    cloudflared service install
    systemctl enable --now cloudflared
    sleep 5

    # --- Bind DNS ---
    echo ""
    echo "9. Binding domain to Cloudflare Tunnel..."
    echo "Binding $FULL_DOMAIN to tunnel..."
    BIND_RESULT=$(cloudflared tunnel route dns "$TUNNEL_NAME" "$FULL_DOMAIN" 2>&1)
    if echo "$BIND_RESULT" | grep -q "Failed to add route"; then
        echo "Warning: failed to bind domain (DNS record may already exist)"
        echo "Error message: $BIND_RESULT"
    else
        echo "Successfully bound $FULL_DOMAIN to tunnel"
    fi

else

    # ---------- Append flow ----------
    echo ""
    echo "=== Append route flow started ==="

    # Load tunnel metadata
    load_tunnel_meta

    # --- Append to route table ---
    echo ""
    echo "Step 2/4: Writing new route..."
    echo "$FULL_DOMAIN $LOCAL_PORT" >> "$ROUTES_FILE"

    # --- Regenerate config.yml ---
    echo "Step 3/4: Regenerating config.yml..."
    regenerate_config "$TUNNEL_ID"

    # --- Just restart service (no uninstall/reinstall) ---
    echo ""
    echo "Step 4/4: Restarting cloudflared service to apply new config..."
    systemctl restart cloudflared
    sleep 3

    # --- Bind new DNS ---
    echo ""
    echo "Binding new domain $FULL_DOMAIN to tunnel..."
    BIND_RESULT=$(cloudflared tunnel route dns "$TUNNEL_NAME" "$FULL_DOMAIN" 2>&1)
    if echo "$BIND_RESULT" | grep -q "Failed to add route"; then
        echo "Warning: failed to bind domain (DNS record may already exist)"
        echo "Error message: $BIND_RESULT"
    else
        echo "Successfully bound $FULL_DOMAIN to tunnel"
    fi
fi

# ---------- Common: verification + summary ----------
echo ""
echo "=== Deployment complete, verifying service status ==="
echo ""
echo "Cloudflare Tunnel status:"
systemctl is-active cloudflared

show_current_routes

echo ""
echo "=== Access information ==="
echo ""
echo "Newly added:"
echo "  Custom domain: https://$FULL_DOMAIN"
echo "  -> Local port:  http://localhost:$LOCAL_PORT"
echo ""
echo "Tunnel information:"
echo "  Name:          $TUNNEL_NAME"
echo "  ID:            $TUNNEL_ID"
echo "  Default URL:   https://$TUNNEL_ID.cfargotunnel.com"
echo ""
echo "Persistent files:"
echo "  Routes:  $ROUTES_FILE"
echo "  Meta:    $TUNNEL_META_FILE"
echo "  Config:  $CONFIG_FILE"
echo ""
if $FIRST_DEPLOY; then
    echo "Tip: Next time you run this script, a new route will be appended to the same tunnel. No new tunnel will be created and no service will be uninstalled."
else
    echo "Tip: The route table currently has $(wc -l < "$ROUTES_FILE") entries. To remove a route, manually edit $ROUTES_FILE and re-run the script (entering a non-existent domain will be treated as a new addition)."
fi
echo ""
echo "=== Complete ==="
