在本地使用 Wrangler 配置 Cloudflare API Token，在 Linux、Windows 和 macOS 上的核心方法是通用的，主要区别在于环境变量的设置方式。更推荐使用 API Token 的方式，因为它比 Global API Key 更安全。

### 🛠️ 通用设置步骤

1.  **获取 API Token**：登录 Cloudflare 控制台，在 "我的个人资料" → "API Tokens" 中，使用 "编辑 Cloudflare Workers" 模板创建一个新的 Token，并务必复制并保存好生成的 Token 。

2.  **设置 Account ID**：你可以在 Cloudflare 控制台的仪表板 "概述" 页面找到你的 Account ID 。

### 🖥️ 各系统设置环境变量的方法

在你的终端中，根据使用的操作系统，通过以下方式将 Token 和 Account ID 设置为环境变量。

#### Linux 与 macOS
这两种系统都是类 Unix 环境，设置方法相同。

*   **临时设置（仅对当前终端会话生效）**：直接在终端中执行 export 命令。
    ```bash
    export CLOUDFLARE_API_TOKEN="你的-api-token"
    export CLOUDFLARE_ACCOUNT_ID="你的-account-id"
    ```

*   **永久生效（推荐）**：将上面的 export 命令添加到你的 Shell 配置文件中，例如 `~/.bashrc` (Bash)、`~/.zshrc` (Zsh) 或 `~/.fish` (Fish)，这样每次打开终端都会自动加载。

    ```bash
    # 例如，在 ~/.zshrc 文件中添加
    export CLOUDFLARE_API_TOKEN="你的-api-token"
    export CLOUDFLARE_ACCOUNT_ID="你的-account-id"
    ```

#### Windows
Windows 可以通过命令行设置环境变量。

*   **命令提示符 (cmd)**：使用 `set` 命令。
    ```cmd
    set CLOUDFLARE_API_TOKEN="你的-api-token"
    set CLOUDFLARE_ACCOUNT_ID="你的-account-id"
    ```

*   **PowerShell**：使用 `$env:` 前缀。
    ```powershell
    $env:CLOUDFLARE_API_TOKEN="你的-api-token"
    $env:CLOUDFLARE_ACCOUNT_ID="你的-account-id"
    ```
    **注意**：通过命令行设置的环境变量都是**临时的**，只对当前窗口有效。如果希望永久生效，需要通过 Windows 系统的"环境变量"设置界面来添加。

### ✅ 验证配置

设置完成后，可以运行以下命令来验证你的认证配置是否成功：
```bash
wrangler whoami
```
如果配置正确，该命令会打印出你的账户邮箱和 Account ID 等信息。


