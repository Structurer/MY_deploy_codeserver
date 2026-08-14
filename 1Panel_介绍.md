# 1Panel 介绍

> 现代化、开源的 Linux 服务器运维管理面板，也是轻量级的 AI 管理平台。飞致云（Fit2Cloud）出品。

官网：<https://1panel.cn/> ｜ GitHub：<https://github.com/1Panel-dev/1Panel> ｜ 文档：<https://1panel.cn/docs/v2/>

---

## 一、快速安装

### 在线一键安装（推荐）

```bash
curl -sSL https://resource.fit2cloud.com/1panel/package/quick_start.sh -o quick_start.sh && bash quick_start.sh
```

执行后脚本会交互式引导你完成安装，过程中会提示：

- **安装目录**（默认 `/opt`）
- **面板端口**（默认随机生成，可自定义）
- **安全入口**（面板访问路径后缀，增强安全）
- **面板用户名 / 密码**

安装完成后，终端会输出访问地址、端口、入口路径、账号信息，请妥善保存。

### 离线安装（企业版，支持 7 天免费试用）

参考官方文档：<https://1panel.cn/docs/v2/installation/enterprise_installation/>

### 升级

在面板仪表盘右下角点击 `Update` 即可在线升级，也可使用 `1pctl` 命令行工具升级。

---

## 二、系统要求

| 项目 | 要求 |
| --- | --- |
| 操作系统 | Ubuntu 20.04 / 22.04 / 24.04、Debian 11/12、CentOS 8+、Rocky Linux、AlmaLinux 等 |
| 内存 | 最低 1GB，建议 2GB+ |
| 磁盘 | 最低 5GB 可用空间 |
| 权限 | Root 权限 |
| 依赖 | 会自动安装 Docker（核心运行环境） |

> 1Panel V2 深度依赖 Docker，所有应用以容器化方式部署。

---

## 三、核心功能特性

### 1. 高效可视化运维
通过 Web 图形界面，轻松实现主机监控、文件管理、数据库管理、容器管理、终端连接、计划任务、日志审计等。

### 2. 快速建站部署
深度集成 WordPress、Halo 等主流建站程序，一键完成域名绑定、SSL 证书自动申请与续期（Let's Encrypt），大幅降低建站门槛。

### 3. 应用商店
精选 230+ 开源应用，覆盖以下分类，全部一键安装：
- AI（23）：MaxKB、OpenWebUI、LobeChat、vLLM、Ollama、n8n、New API 等
- 建站（9）：WordPress、Halo 等
- 数据库（22）：MySQL、PostgreSQL、Redis、MongoDB
- Web 服务器（4）：OpenResty、Nginx 等
- 运行环境（8）：Node、PHP、Java、Go、Python
- DevOps（19）、实用工具（84）、云存储（8）、安全（7）等

### 4. AI 管理（V2 新增）
- **智能体管理**：集中化管理本地 AI Agent（OpenClaw、Hermes Agent 等）
- **模型管理**：模型账号统一管理
- **vLLM / Ollama**：本地大模型推理服务
- **AI 网关**：统一 API 入口与流量管理
- **MCP**：Model Context Protocol 服务管理
- **Skills Hub**：技能市场
- **GPU 监控**：GPU 资源可视化

### 5. 企业级安全与备份
- **WAF 防火墙**：应用层防护，自动拦截 SQL 注入、XSS、CC 攻击等
- **日志审计**：完整操作记录可追溯
- **一键备份与恢复**：支持本地、S3 兼容存储、阿里云 OSS、腾讯云 COS、七牛云等
- **文件历史**：面板内文件变更可回溯与恢复
- **Tamper Protection**：防篡改保护

---

## 四、常用命令：1pctl CLI

1Panel 提供 `1pctl` 命令行管理工具：

```bash
# 查看面板信息（访问地址、端口、入口、账号）
1pctl user-info

# 重置面板密码
1pctl update password

# 重置面板端口
1pctl update port <新端口>

# 重置安全入口
1pctl update entrance <新入口>

# 重启面板
1pctl restart

# 关闭面板
1pctl stop

# 启动面板
1pctl start

# 查看面板状态
1pctl status

# 查看面板日志
1pctl logs

# 升级面板
1pctl update
```

---

## 五、典型使用场景

### 场景 1：5 分钟搭建个人博客
1. 安装 1Panel
2. 应用商店一键安装 OpenResty + WordPress
3. 网站管理中绑定域名 + 一键申请 SSL 证书
4. 完成

### 场景 2：私有 AI 助理
1. 应用商店安装 Ollama 或 vLLM
2. 安装 OpenWebUI / LobeChat 作为前端
3. 在 AI 模块绑定模型，开始对话

### 场景 3：开发测试环境
1. 一键部署 MySQL + Redis + Node/Python 运行环境
2. 通过容器管理查看运行状态
3. 文件管理器在线编辑代码
4. 终端模块直接 SSH 进容器调试

### 场景 4：服务器统一安全加固
1. 启用 WAF 防火墙
2. 配置 SSL 证书自动续期
3. 设置定时备份到 S3/OSS
4. 开启日志审计与防篡改

---

## 六、与同类产品对比

| 维度 | 1Panel | 宝塔面板 | Webmin |
| --- | --- | --- | --- |
| 技术栈 | Go + Vue.js | Python/C | Perl |
| 部署模式 | Docker 容器化 | 传统二进制 | 传统二进制 |
| 界面 | 现代化扁平 | 传统 | 传统 |
| 应用商店 | 230+ 一键安装 | 付费为主 | 需手动配置 |
| AI 能力 | 原生支持 | 无 | 无 |
| 资源占用 | 200-500MB | 100-300MB | 50-150MB |
| 开源协议 | GPL v3 | 部分开源 | BSD |
| 移动端 | 完整响应式 | 基础适配 | 基础适配 |
| GitHub Stars | 29k+ | - | 5k+ |

---

## 七、版本说明

1Panel 提供三个版本，共享基础运维能力：

| 版本 | 说明 |
| --- | --- |
| **社区版** | 完全免费，基础运维 + 应用商店 + 容器管理 |
| **专业版** | 需许可证，增加 WAF、AI 网关、多节点管理等进阶功能 |
| **企业版** | 需许可证，增加 RBAC 权限、审计、Tamper 等企业级功能 |

版本对比详见：<https://1panel.cn/versions.html>

---

## 八、服务管理

1Panel 自身作为 systemd 服务运行：

```bash
# 重启面板服务
systemctl restart 1panel

# 查看面板状态
systemctl status 1panel

# 开机自启
systemctl enable 1panel

# 查看实时日志
journalctl -u 1panel -f
```

---

## 九、卸载

```bash
# 卸载面板（保留数据）
1pctl uninstall

# 卸载面板并清理所有数据（含容器、镜像、应用数据）
1pctl reset all
```

> 卸载前请务必备份重要数据。

---

## 十、相关链接

- 官网：<https://1panel.cn/>
- GitHub 仓库：<https://github.com/1Panel-dev/1Panel>
- V2 文档：<https://1panel.cn/docs/v2/>
- 在线体验 Demo：<https://demo.1panel.cn/>
- 应用商店：<https://apps.fit2cloud.com/1panel>
- API 手册：<https://1panel.cn/docs/v2/dev_manual/api_manual/>
- 更新日志：<https://1panel.cn/docs/v2/changelog/>

---

## 附：与本仓库脚本的定位差异

| 项目 | 本仓库 deploy_codeserver | 1Panel |
| --- | --- | --- |
| 定位 | 单一服务（code-server）一键部署 | 全功能运维面板 |
| 资源占用 | 极轻量（仅 systemd 服务） | 200-500MB（含 Docker） |
| 适用场景 | 只需公网访问 code-server | 需要管理多服务、多网站 |
| 与 Cloudflare Tunnel | 内置集成 | 需手动配置或使用反代 |

> 若只需把 code-server 暴露到公网，本仓库脚本更轻量；若需要管理多个服务、网站、数据库，1Panel 更合适。两者也可组合使用：用 1Panel 管理服务器，code-server 作为其中一个应用。
