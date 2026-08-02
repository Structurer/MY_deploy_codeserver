#!/bin/bash

# 部署脚本：仅安装和配置 code Server（不含 Cloudflare Tunnel）
# 支持自定义监听端口
# 作者：Trae Assistant
# 日期：2026-08-03

set -e

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

restart_code_server() {
    echo "检查 code-server 服务状态..."
    if systemctl list-unit-files | grep -q code-server@.service; then
        echo "重启 code-server 服务以应用新配置..."
        systemctl restart code-server@root 2>/dev/null || systemctl start code-server@root
        sleep 2
        systemctl status code-server@root --no-pager
    else
        echo "code-server 服务尚未安装，跳过重启操作..."
    fi
}

# ---------- 入口 ----------

echo ""
echo "=== 开始部署 code Server ==="

# ---------- 0. 系统更新 ----------
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

# ---------- 2. 依赖 ----------
echo ""
echo "2. 安装必要依赖..."
check_and_handle_dpkg_lock
apt install -y curl

# ---------- 3. 安装 code-server ----------
echo ""
echo "3. 安装 code Server..."
curl -fsSL https://code-server.dev/install.sh | sh

# ---------- 4. 配置：端口 + 密码 ----------
echo ""
echo "4. 配置 code Server..."

# 端口自定义
echo "请输入 code Server 监听的本地端口号（1-65535，默认 8080）："
while true; do
    read -p "本地端口（直接回车默认 8080）: " CODESERVER_PORT
    if [ -z "$CODESERVER_PORT" ]; then
        CODESERVER_PORT=8080
        echo "使用默认端口: $CODESERVER_PORT"
        break
    fi
    if [[ "$CODESERVER_PORT" =~ ^[0-9]+$ ]] && [ "$CODESERVER_PORT" -ge 1 ] && [ "$CODESERVER_PORT" -le 65535 ]; then
        echo "使用的端口: $CODESERVER_PORT"
        break
    else
        echo "错误：端口号无效，请输入 1-65535 之间的数字"
    fi
done

# 密码两次确认
while true; do
    echo ""
    echo "请输入 code Server 的登录密码："
    read -s CODESERVER_PASSWORD
    echo ""
    echo "确认密码："
    read -s CODESERVER_PASSWORD_CONFIRM
    echo ""

    if [ "$CODESERVER_PASSWORD" = "$CODESERVER_PASSWORD_CONFIRM" ]; then
        echo "密码确认成功！"
        break
    else
        echo "错误：两次输入的密码不一致，请重新输入"
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
    echo "配置文件已创建"
else
    sed -i "s/bind-addr: .*/bind-addr: 127.0.0.1:$CODESERVER_PORT/" "$CONFIG_FILE"
    sed -i "s/password: .*/password: $CODESERVER_PASSWORD/" "$CONFIG_FILE"
    echo "端口与密码已更新"
fi

# ---------- 5. 启动服务 ----------
echo ""
echo "5. 启动并启用 code Server 服务..."
systemctl enable --now code-server@root
# 重启服务以确保端口和密码生效
restart_code_server

echo ""
echo "=== code Server 部署完成 ==="

# ---------- 验证 + 访问信息 ----------
echo ""
echo "=== 部署完成，验证服务状态 ==="
echo ""
echo "code Server 状态:"
systemctl is-active code-server@root

echo ""
echo "=== 访问信息 ==="
echo ""
echo "本地监听地址: http://127.0.0.1:$CODESERVER_PORT"
echo ""
echo "登录密码: $CODESERVER_PASSWORD"
echo ""
echo "提示：如需通过公网域名访问此服务，请运行 deploy_tunnel.sh 将该端口通过 Cloudflare Tunnel 暴露。"
echo "示例命令："
echo "  bash deploy_tunnel.sh"
echo "  然后输入：端口 $CODESERVER_PORT，域名 code.example.com"
echo ""
echo "=== 完成 ==="
