# code Server / Cloudflare Tunnel 部署工具集

本仓库提供两组完全解耦的部署脚本，可独立或组合使用：

- **code Server 部署脚本**：仅安装 code Server（支持自定义监听端口），不含任何 Cloudflare 逻辑。
- **Cloudflare Tunnel 部署脚本**：独立部署 / 追加 Cloudflare Tunnel（单 tunnel + 多 ingress，可重复运行），不依赖 code Server。

组合方式：先跑 code Server 脚本 → 再跑 Tunnel 脚本把端口暴露到公网。

## 功能特性

### code Server 部署
- ✅ 自动安装和配置 code Server
- ✅ 交互式登录密码设置（两次确认）
- ✅ 自定义监听端口（默认 8080，回车默认）
- ✅ 服务开机自启 + 配置变更后自动重启
- ✅ 详细的错误处理和状态反馈

### Cloudflare Tunnel 部署
- ✅ 独立安装和配置 Cloudflare Tunnel（与 code Server 完全解耦）
- ✅ 交互式二维码 + 链接双模式授权
- ✅ 支持多端口转发（首次建 tunnel，后续自动追加 ingress 路由）
- ✅ 域名重复检测、端口范围校验
- ✅ 服务开机自启设置
- ✅ 路由表持久化文件，方便手动增删路由

## 系统要求

- Ubuntu 20.04 LTS 或更高版本
- 至少 1GB RAM
- 至少 10GB 磁盘空间
- 可访问互联网
- Root 权限

## 快速开始

### 方式 1：仅部署 code Server（支持自定义端口）

仅安装和配置 code Server，不带任何 Cloudflare Tunnel。部署完成后如需公网访问，再运行方式 2 的 Tunnel 脚本把端口暴露出去。

中文版：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Structurer/deploy_codeserver/main/deploy_codeserver_CF_tunnel.sh)"
```

英文版（en_US）：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Structurer/deploy_codeserver/main/deploy_codeserver_CF_tunnel_en.sh)"
```

执行时会提示输入：

- **监听端口号**（1-65535，回车默认 `8080`）
- **登录密码**（两次确认）

执行完成后，code Server 监听 `http://127.0.0.1:<端口>`。需要公网访问时，继续运行方式 2 的 Tunnel 脚本，输入相同的端口即可。

### 方式 2：仅部署 Cloudflare Tunnel（可重复运行，自动追加多端口转发）

适用场景：服务器上已有监听某端口的服务（如 code-server、Web 应用、API 等），只需将其通过 Cloudflare Tunnel 暴露到公网域名，无需安装 code Server。

**支持多次运行追加路由**：首次运行完成部署后，再次运行会自动检测已有 tunnel，在同一条 tunnel 的 ingress 规则中追加新的域名+端口，不会创建新 tunnel 也不会卸载重装 systemd 服务。

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Structurer/deploy_codeserver/main/deploy_tunnel.sh)"
```

执行时会提示输入：

- **本地端口号**（1-65535）：Tunnel 将 `https://你的域名` 转发到 `http://localhost:端口`
- **完整域名**：如 `app.example.com`（同一域名不会被重复添加）

> 注意：此脚本不会启动后端服务，仅负责建立 Tunnel 转发。请确保目标端口已有服务在监听。

**内部持久化文件**（位于 `/etc/cloudflared/`）：

| 文件 | 作用 |
|---|---|
| `routes.conf` | 路由表，每行 `域名 端口`，如需删除某条路由可直接编辑此文件 |
| `tunnel.meta` | 记录 tunnel 的 NAME 和 ID |
| `config.yml` | 由 `routes.conf` 自动生成的 cloudflared ingress 配置 |

**典型使用流程**：

```bash
# 第一次：创建 tunnel + 首条路由（app1.example.com -> localhost:3000）
bash deploy_tunnel.sh

# 第二次：在同一 tunnel 上追加第二条路由（app2.example.com -> localhost:9000）
bash deploy_tunnel.sh

# 第三次：继续追加第三条路由（api.example.com -> localhost:8080）
bash deploy_tunnel.sh
```




#### 常用命令


* ssh-keygen
```bash
ssh-keygen -R example_ip
```


* tunnel管理
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Structurer/deploy_codeserver/main/cloudflare_tunnel_manager.sh)"
```


* 提权
```bash
sudo -i
```


## 执行流程

1. **系统准备**
   - 更新系统包
   - 安装必要依赖

2. **code Server 部署**
   - 安装 code Server
   - 交互式输入登录密码（两次确认）
   - 启动并启用 code Server 服务

3. **Cloudflare Tunnel 部署**
   - 安装 Cloudflare Tunnel 客户端
   - Cloudflare 账户授权（需要浏览器登录）
   - 提取并选择已授权的域名
   - 配置子域名前缀（默认：code）
   - 创建并配置 Cloudflare Tunnel
   - 启动并启用 Cloudflare Tunnel 服务
   - 绑定域名到 Tunnel

4. **完成部署**
   - 验证服务状态
   - 显示访问信息

## 访问信息

部署完成后，您可以通过以下地址访问 code Server：

- **自定义域名**：https://[子域名].[主域名]（ 例如：https://code.example.com ）
- **Cloudflare Tunnel 默认地址**：https://[tunnel-id].cfargotunnel.com

## 注意事项

1. **权限要求**
   - 执行脚本时需要 root 权限

2. **网络连接**
   - 确保服务器可以访问互联网
   - 确保服务器可以访问 Cloudflare 服务

3. **Cloudflare 授权**
   - 在授权步骤中，需要在浏览器中打开提供的 URL 并登录 Cloudflare 账户
   - 授权完成后，返回终端按回车键继续

4. **域名配置**
   - 确保您选择的域名已经添加到 Cloudflare 账户中
   - 如果域名的 DNS 记录已存在，需要先在 Cloudflare 仪表盘中删除冲突的记录

5. **服务管理**

   ```bash
   # 重启 code Server 服务
   systemctl restart code-server@root

   # 重启 Cloudflare Tunnel 服务
   systemctl restart cloudflared

   # 查看服务状态
   systemctl status code-server@root
   systemctl status cloudflared
   ```

## 故障排查

### 常见问题

1. **Cloudflare 授权失败**
   - 确保您在浏览器中完成了授权操作
   - 确保使用的是正确的 Cloudflare 账户

2. **域名绑定失败**
   - 错误信息：`Failed to add route: code: 1003, reason: Failed to create record...`
   - 解决方案：在 Cloudflare 仪表盘中删除冲突的 DNS 记录，然后重新运行脚本

3. **服务启动失败**
   - 检查服务状态：`systemctl status [service-name]`
   - 查看服务日志：`journalctl -u [service-name]`

### 日志查看

```bash
# 查看 code Server 日志
journalctl -u code-server@root

# 查看 Cloudflare Tunnel 日志
journalctl -u cloudflared
```

## 更新脚本

要获取最新版本的脚本，只需重新运行下载命令：

```bash
curl -fsSL https://raw.githubusercontent.com/Structurer/deploy_codeserver/main/deploy_codeserver_CF_tunnel.sh | bash
```

## 许可证

MIT License

## 贡献

欢迎提交 Issue 和 Pull Request 来改进这个项目！
