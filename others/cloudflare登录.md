
---

## Windows

### 方式一：命令行（临时，推荐用于测试）

**命令提示符 (cmd)**
```cmd
set CLOUDFLARE_API_TOKEN=你的-api-token
```

**PowerShell**
```powershell
$env:CLOUDFLARE_API_TOKEN="你的-api-token"
```

### 方式二：永久生效（推荐）

1. 打开 **系统属性** → **高级** → **环境变量**
2. 在 **用户变量** 或 **系统变量** 中点击 **新建**
3. 变量名：`CLOUDFLARE_API_TOKEN`
4. 变量值：`你的-api-token`
5. 点击确定，重启终端生效

---

## Linux

### 方式一：命令行（临时）
```bash
export CLOUDFLARE_API_TOKEN="你的-api-token"
```

### 方式二：永久生效（推荐）
```bash
# 编辑配置文件
nano ~/.bashrc  # 或 ~/.zshrc

# 在文件末尾添加
export CLOUDFLARE_API_TOKEN="你的-api-token"

# 保存后重新加载
source ~/.bashrc  # 或 source ~/.zshrc
```

---

## macOS

### 方式一：命令行（临时）
```bash
export CLOUDFLARE_API_TOKEN="你的-api-token"
```

### 方式二：永久生效（推荐）
```bash
# 编辑配置文件
nano ~/.zshrc  # macOS Catalina+ 默认 Zsh
# 或 nano ~/.bash_profile  # 旧版本

# 在文件末尾添加
export CLOUDFLARE_API_TOKEN="你的-api-token"

# 保存后重新加载
source ~/.zshrc  # 或 source ~/.bash_profile
```

---

## 验证配置

设置完成后，运行以下命令验证：
```bash
wrangler whoami
```

输出会显示你的账户信息，包括自动获取的 Account ID，说明配置成功！

```bash
⛅️ wrangler 3.x.x
---------------------------------
Your Account ID: abc123def456...
Your Email: your-email@example.com
```

---

## 快速对比

| 系统 | 临时设置 | 永久设置 |
|------|---------|---------|
| **Windows (cmd)** | `set CLOUDFLARE_API_TOKEN=xxx` | 系统环境变量界面 |
| **Windows (PowerShell)** | `$env:CLOUDFLARE_API_TOKEN="xxx"` | 系统环境变量界面 |
| **Linux** | `export CLOUDFLARE_API_TOKEN="xxx"` | `~/.bashrc` |
| **macOS** | `export CLOUDFLARE_API_TOKEN="xxx"` | `~/.zshrc` |

---

## 额外提示

- **Token 权限**：确保你的 Token 有 **Workers** 相关权限（编辑、部署等）
- **安全注意**：Token 相当于密码，不要提交到代码仓库
- **多项目**：一个 Token 可以在多个项目中复用
- **Wrangler 版本**：确保 wrangler 版本 >= 2.0

如果遇到问题，可以检查：
```bash
wrangler --version
echo $CLOUDFLARE_API_TOKEN  # Linux/macOS
echo %CLOUDFLARE_API_TOKEN%  # Windows cmd
```
