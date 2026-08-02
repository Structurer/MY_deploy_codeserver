#!/bin/bash

# 部署脚本：独立部署 Cloudflare Tunnel，支持多次运行追加路由（单 tunnel + 多 ingress）
# 首次运行：创建 tunnel + 首条路由 + 安装并启动服务
# 再次运行：检测到已有 tunnel → 追加新域名+端口路由到 ingress + 绑定 DNS + 重启服务
# 作者：Trae Assistant
# 日期：2026-08-03

set -e

# ---------- 路径常量 ----------
CLOUDFLARED_DIR="/etc/cloudflared"
ROUTES_FILE="$CLOUDFLARED_DIR/routes.conf"       # 格式：每行 "域名 端口"
TUNNEL_META_FILE="$CLOUDFLARED_DIR/tunnel.meta"   # 格式：TUNNEL_NAME=xxx / TUNNEL_ID=xxx
CONFIG_FILE="$CLOUDFLARED_DIR/config.yml"
CERT_FILE="$HOME/.cloudflared/cert.pem"
SYSTEMD_SERVICE="/etc/systemd/system/cloudflared.service"

# ---------- 辅助函数 ----------

check_and_handle_dpkg_lock() {
    echo "检查 dpkg 锁状态..."
    if [ -f "/var/lib/dpkg/lock" ] || [ -f "/var/lib/dpkg/lock-frontend" ]; then
        echo "检测到 dpkg 锁文件，尝试释放..."
        sudo fuser -vki -TERM /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend 2>/dev/null || true
        sudo dpkg --configure --pending 2>/dev/null || true
        sleep 3
    fi
}

# 从 routes.conf 重新生成完整的 ingress 格式 config.yml
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
    echo "已重新生成 config.yml（共 $(wc -l < "$ROUTES_FILE") 条路由规则）"
}

# 保存 tunnel 元信息
save_tunnel_meta() {
    cat > "$TUNNEL_META_FILE" << EOF
TUNNEL_NAME=$1
TUNNEL_ID=$2
EOF
}

# 读取 tunnel 元信息（成功返回 0，失败返回 1）
load_tunnel_meta() {
    if [ -f "$TUNNEL_META_FILE" ]; then
        # shellcheck disable=SC1090
        source "$TUNNEL_META_FILE"
        [ -n "$TUNNEL_NAME" ] && [ -n "$TUNNEL_ID" ] && return 0
    fi
    return 1
}

# 检查域名是否已在 routes.conf 中（避免重复）
domain_exists() {
    local target=$1
    [ ! -f "$ROUTES_FILE" ] && return 1
    awk '{print $1}' "$ROUTES_FILE" | grep -qxF "$target"
}

# 显示当前所有路由
show_current_routes() {
    echo ""
    echo "--- 当前路由规则（来自 $ROUTES_FILE）---"
    if [ ! -f "$ROUTES_FILE" ] || [ ! -s "$ROUTES_FILE" ]; then
        echo "（暂无路由）"
    else
        printf "%-2s  %-35s  %s\n" "#" "域名" "本地端口"
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

# Cloudflare 授权逻辑（两套分支合一）
run_cloudflared_login() {
    # 检查 qrencode
    if ! command -v qrencode &> /dev/null; then
        echo "安装 qrencode 用于生成二维码..."
        apt update && apt install -y qrencode
    fi

    echo "=== Cloudflare 账户授权 ==="
    echo "您可以使用以下任意一种方式进行授权："
    echo "- 通过链接授权：复制下面的链接到浏览器中打开"
    echo "- 通过二维码授权：使用手机相机扫描下面的二维码"
    echo ""
    echo "=== 授权说明 ==="
    echo "1. 选择下述任意一种授权方式"
    echo "2. 在浏览器中登录 Cloudflare 账户"
    echo "3. 点击 'Authorize' 按钮完成授权"
    echo "4. 授权成功后，按回车键继续"
    echo ""

    cloudflared tunnel login > /tmp/auth_output.txt 2>&1 &
    AUTH_PID=$!

    echo "生成授权 URL..."
    sleep 3

    AUTH_URL=$(grep -o "https://dash.cloudflare.com/argotunnel.*" /tmp/auth_output.txt)

    if [ -n "$AUTH_URL" ]; then
        echo ""
        echo "=== 方式 1: 通过链接授权 ==="
        echo "授权 URL:"
        echo "$AUTH_URL"
        echo ""
        echo "=== 方式 2: 通过二维码授权 ==="
        echo "请使用手机相机扫描下面的二维码:"
        echo ""
        qrencode -t ASCII -s 1 -m 0 "$AUTH_URL"
        echo ""
        read -p "授权完成后，按回车键继续: "
        wait $AUTH_PID 2>/dev/null
    else
        echo "无法获取授权 URL，直接执行授权命令..."
        cloudflared tunnel login
    fi
}

# ---------- 入口 ----------

echo ""
echo "=== Cloudflare Tunnel 部署 / 追加路由 ==="

# ---------- 判断首次 / 追加 ----------
FIRST_DEPLOY=true
if load_tunnel_meta \
   && [ -f "$CERT_FILE" ] \
   && [ -f "$ROUTES_FILE" ] \
   && command -v cloudflared &> /dev/null; then
    FIRST_DEPLOY=false
fi

if $FIRST_DEPLOY; then
    echo ""
    echo "检测：首次部署，将创建新的 Cloudflare Tunnel"
else
    echo ""
    echo "检测：检测到已有部署（TUNNEL_NAME=$TUNNEL_NAME, TUNNEL_ID=$TUNNEL_ID）"
    echo "将在现有 tunnel 上追加新的路由规则"
    show_current_routes
fi

# ---------- 公共：收集用户输入（域名 + 端口） ----------
echo ""
echo "步骤 1/4：配置新的转发规则"

# 端口输入
echo "请输入要转发到的本地端口号（1-65535）："
while true; do
    read -p "本地端口: " LOCAL_PORT
    if [[ "$LOCAL_PORT" =~ ^[0-9]+$ ]] && [ "$LOCAL_PORT" -ge 1 ] && [ "$LOCAL_PORT" -le 65535 ]; then
        break
    else
        echo "错误：端口号无效，请输入 1-65535 之间的数字"
    fi
done

# 域名输入
echo ""
echo "请输入完整域名（如 app.example.com）："
while true; do
    read -p "完整域名: " FULL_DOMAIN
    if [ -z "$FULL_DOMAIN" ]; then
        echo "错误：域名不能为空"
        continue
    fi
    if domain_exists "$FULL_DOMAIN"; then
        echo "错误：域名 $FULL_DOMAIN 已存在于路由表中，请使用不同的域名"
        continue
    fi
    break
done

echo ""
echo "新规则：https://$FULL_DOMAIN  ->  http://localhost:$LOCAL_PORT"

# ---------- 首次部署流程 ----------
if $FIRST_DEPLOY; then

    echo ""
    echo "=== 首次部署流程开始 ==="

    # --- 0. 系统更新选项 ---
    echo ""
    echo "步骤 2/4：系统准备"
    echo ""
    echo "0. 系统更新选项..."
    echo "系统更新可能需要较长时间，是否跳过？"
    echo "1. 执行系统更新（推荐，确保系统包最新）"
    echo "2. 跳过系统更新（快速部署，使用现有包）"
    read -p "请输入选择 (1/2): " update_choice

    if [ "$update_choice" = "1" ]; then
        echo ""
        echo "1. 更新系统包..."
        check_and_handle_dpkg_lock
        apt update && apt upgrade -y
    else
        echo ""
        echo "1. 跳过系统更新..."
    fi

    echo ""
    echo "2. 安装必要依赖..."
    check_and_handle_dpkg_lock
    apt install -y curl qrencode

    # --- 3. 安装 cloudflared ---
    echo ""
    echo "3. 安装 Cloudflare Tunnel 客户端..."
    curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o cloudflared.deb
    check_and_handle_dpkg_lock
    dpkg -i cloudflared.deb
    rm -f cloudflared.deb

    # --- 4. Cloudflare 授权 ---
    echo ""
    echo "4. Cloudflare 账户授权..."
    if [ -f "$CERT_FILE" ]; then
        echo "检测到已存在的 Cloudflare 证书"
        echo "请选择操作："
        echo "1. 使用现有证书"
        echo "2. 重新授权（覆盖现有证书）"
        read -p "请输入选择 (1/2): " cert_choice
        if [ "$cert_choice" = "2" ]; then
            echo "正在删除现有证书..."
            rm -f "$CERT_FILE"
            run_cloudflared_login
        else
            echo "使用现有证书"
        fi
    else
        run_cloudflared_login
    fi

    # --- 验证授权 ---
    echo ""
    echo "5. 验证 Cloudflare 授权..."
    if [ ! -f "$CERT_FILE" ]; then
        echo "错误：Cloudflare 授权失败，请重新执行授权步骤"
        exit 1
    fi
    echo "Cloudflare 授权成功！"

    # --- 6. 创建 tunnel ---
    echo ""
    echo "6. 创建 Cloudflare Tunnel..."
    TUNNEL_NAME="custom-tunnel"
    TUNNEL_ID=""

    echo "正在尝试创建 tunnel '$TUNNEL_NAME'..."
    TUNNEL_CREATION_OUTPUT=$(cloudflared tunnel create "$TUNNEL_NAME" 2>&1 || echo "命令执行失败: $?")
    echo "创建命令输出: $TUNNEL_CREATION_OUTPUT"

    TUNNEL_ID=$(echo "$TUNNEL_CREATION_OUTPUT" | grep "Created tunnel" | grep "with id" | awk -F 'id ' '{print $2}' | tr -d '\n')
    echo "提取到的 Tunnel ID: '$TUNNEL_ID'"

    # 同名已存在 → 选择现有 / 建新名
    if [ -z "$TUNNEL_ID" ] && echo "$TUNNEL_CREATION_OUTPUT" | grep -q "tunnel with name already exists"; then
        echo "检测到 tunnel '$TUNNEL_NAME' 已存在"
        echo "请选择操作："
        echo "1. 使用现有 tunnel"
        echo "2. 创建新名称的 tunnel"
        read -p "请输入选择 (1/2): " tunnel_choice

        if [ "$tunnel_choice" = "1" ]; then
            echo "正在获取现有 tunnel 列表..."
            MAX_RETRIES=3
            RETRY_COUNT=0
            TUNNEL_LIST=""

            while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
                TUNNEL_LIST=$(cloudflared tunnel list 2>&1)
                if [ $? -eq 0 ] && echo "$TUNNEL_LIST" | grep -q -E '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'; then
                    break
                fi
                echo "尝试重新授权..."
                cloudflared tunnel login
                RETRY_COUNT=$((RETRY_COUNT + 1))
            done

            if [ -z "$TUNNEL_LIST" ] || ! echo "$TUNNEL_LIST" | grep -q -E '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'; then
                echo "错误：无法获取有效的 tunnel 列表，请稍后重试"
                exit 1
            fi

            echo "调试信息：tunnel 列表内容："
            echo "$TUNNEL_LIST"
            echo "---------------------------------------------------------------"

            TUNNEL_ITEMS=()
            while IFS= read -r line; do
                echo "$line" | grep -q -E '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' && TUNNEL_ITEMS+=("$line")
            done <<< "$TUNNEL_LIST"

            if [ ${#TUNNEL_ITEMS[@]} -eq 0 ]; then
                echo "错误：未找到任何现有 tunnel"
                exit 1
            fi

            echo "序号  ID                                   NAME              CREATED"
            echo "---------------------------------------------------------------"
            for i in "${!TUNNEL_ITEMS[@]}"; do
                index=$((i+1))
                tunnel_line=${TUNNEL_ITEMS[$i]}
                tunnel_id=$(echo "$tunnel_line" | awk '{print $1}')
                tunnel_name=$(echo "$tunnel_line" | awk '{print $2}')
                tunnel_created=$(echo "$tunnel_line" | awk '{print $3 " " $4 " " $5 " " $6 " " $7}')
                printf "%2d   %s   %-16s   %s\n" "$index" "$tunnel_id" "$tunnel_name" "$tunnel_created"
            done

            read -p "请输入要使用的 tunnel 序号：" tunnel_index
            if [[ "$tunnel_index" =~ ^[0-9]+$ ]] && [ "$tunnel_index" -ge 1 ] && [ "$tunnel_index" -le "${#TUNNEL_ITEMS[@]}" ]; then
                selected_index=$((tunnel_index-1))
                selected_tunnel=${TUNNEL_ITEMS[$selected_index]}
                TUNNEL_ID=$(echo "$selected_tunnel" | awk '{print $1}')
                TUNNEL_NAME=$(echo "$selected_tunnel" | awk '{print $2}')

                echo "您选择的 tunnel：ID=$TUNNEL_ID, NAME=$TUNNEL_NAME"

                CREDENTIALS_FILE="/root/.cloudflared/$TUNNEL_ID.json"
                if [ ! -f "$CREDENTIALS_FILE" ]; then
                    echo "检测到本地缺少该 tunnel 的凭据文件，删除后重建..."
                    cloudflared tunnel delete "$TUNNEL_ID" 2>&1 || true
                    CREATE_RESULT=$(cloudflared tunnel create "$TUNNEL_NAME" 2>&1)
                    NEW_TUNNEL_ID=$(echo "$CREATE_RESULT" | grep "Created tunnel" | grep "with id" | awk -F 'id ' '{print $2}' | tr -d '\n')
                    if [[ "$NEW_TUNNEL_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
                        TUNNEL_ID="$NEW_TUNNEL_ID"
                    else
                        echo "错误：重新创建 tunnel 失败"
                        exit 1
                    fi
                fi
            else
                echo "错误：输入无效"
                exit 1
            fi
        else
            read -p "新的 tunnel 名称: " NEW_TUNNEL_NAME
            [ -z "$NEW_TUNNEL_NAME" ] && NEW_TUNNEL_NAME="custom-tunnel-$(date +%s)"
            TUNNEL_CREATION_OUTPUT=$(cloudflared tunnel create "$NEW_TUNNEL_NAME" 2>&1 || echo "命令执行失败: $?")
            TUNNEL_ID=$(echo "$TUNNEL_CREATION_OUTPUT" | grep "Created tunnel" | grep "with id" | awk -F 'id ' '{print $2}' | tr -d '\n')
            if [[ "$TUNNEL_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
                TUNNEL_NAME="$NEW_TUNNEL_NAME"
            else
                echo "错误：创建 tunnel 失败"
                exit 1
            fi
        fi
    elif [ -z "$TUNNEL_ID" ]; then
        echo "错误：创建 Cloudflare Tunnel 失败"
        echo "输出：$TUNNEL_CREATION_OUTPUT"
        exit 1
    fi

    echo "成功创建/选中 tunnel：$TUNNEL_NAME (ID=$TUNNEL_ID)"

    # --- 保存 tunnel 元信息 + 初始化路由表 ---
    echo ""
    echo "7. 写入持久化配置..."
    mkdir -p "$CLOUDFLARED_DIR"
    save_tunnel_meta "$TUNNEL_NAME" "$TUNNEL_ID"
    echo "$FULL_DOMAIN $LOCAL_PORT" > "$ROUTES_FILE"

    regenerate_config "$TUNNEL_ID"

    # --- 安装并启动 systemd 服务 ---
    echo ""
    echo "8. 安装并启动 Cloudflare Tunnel 服务..."
    if [ -f "$SYSTEMD_SERVICE" ]; then
        echo "检测到 cloudflared 服务已存在，先卸载旧服务..."
        cloudflared service uninstall
    fi
    cloudflared service install
    systemctl enable --now cloudflared
    sleep 5

    # --- 绑定 DNS ---
    echo ""
    echo "9. 绑定域名到 Cloudflare Tunnel..."
    echo "将 $FULL_DOMAIN 绑定到 tunnel..."
    BIND_RESULT=$(cloudflared tunnel route dns "$TUNNEL_NAME" "$FULL_DOMAIN" 2>&1)
    if echo "$BIND_RESULT" | grep -q "Failed to add route"; then
        echo "警告：绑定域名失败（可能 DNS 记录已存在）"
        echo "错误信息：$BIND_RESULT"
    else
        echo "成功绑定 $FULL_DOMAIN 到 tunnel"
    fi

else

    # ---------- 追加流程 ----------
    echo ""
    echo "=== 追加路由流程开始 ==="

    # 加载 tunnel 元信息
    load_tunnel_meta

    # --- 追加到路由表 ---
    echo ""
    echo "步骤 2/4：写入新路由..."
    echo "$FULL_DOMAIN $LOCAL_PORT" >> "$ROUTES_FILE"

    # --- 重生成 config.yml ---
    echo "步骤 3/4：重新生成 config.yml..."
    regenerate_config "$TUNNEL_ID"

    # --- 只重启服务（不卸载重装） ---
    echo ""
    echo "步骤 4/4：重启 cloudflared 服务以应用新配置..."
    systemctl restart cloudflared
    sleep 3

    # --- 绑定新 DNS ---
    echo ""
    echo "绑定新域名 $FULL_DOMAIN 到 tunnel..."
    BIND_RESULT=$(cloudflared tunnel route dns "$TUNNEL_NAME" "$FULL_DOMAIN" 2>&1)
    if echo "$BIND_RESULT" | grep -q "Failed to add route"; then
        echo "警告：绑定域名失败（可能 DNS 记录已存在）"
        echo "错误信息：$BIND_RESULT"
    else
        echo "成功绑定 $FULL_DOMAIN 到 tunnel"
    fi
fi

# ---------- 公共：验证 + 总结 ----------
echo ""
echo "=== 部署完成，验证服务状态 ==="
echo ""
echo "Cloudflare Tunnel 状态:"
systemctl is-active cloudflared

show_current_routes

echo ""
echo "=== 访问信息 ==="
echo ""
echo "本次新增："
echo "  自定义域名: https://$FULL_DOMAIN"
echo "  -> 本地端口: http://localhost:$LOCAL_PORT"
echo ""
echo "Tunnel 信息："
echo "  名称: $TUNNEL_NAME"
echo "  ID:   $TUNNEL_ID"
echo "  默认地址: https://$TUNNEL_ID.cfargotunnel.com"
echo ""
echo "持久化文件："
echo "  路由表:   $ROUTES_FILE"
echo "  Meta:     $TUNNEL_META_FILE"
echo "  Config:   $CONFIG_FILE"
echo ""
if $FIRST_DEPLOY; then
    echo "提示：下次运行本脚本将在同一 tunnel 上追加新路由，不会创建新 tunnel 或卸载服务。"
else
    echo "提示：当前路由表共 $(wc -l < "$ROUTES_FILE") 条。需要删除路由请手动编辑 $ROUTES_FILE 后重新运行脚本（输入不存在的域名会被当作新增）。"
fi
echo ""
echo "=== 完成 ==="
