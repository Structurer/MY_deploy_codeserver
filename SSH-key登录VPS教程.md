# 使用 SSH Key 登录 Ubuntu VPS 新人教程

> 本教程面向 Windows 用户,目标 VPS 系统为 Ubuntu。按步骤操作,大约 10 分钟即可完成配置。

---

## 一、什么是 SSH Key 登录?

SSH Key 是一种**非对称加密**的登录方式,比传统密码登录更安全、更方便。

### 工作原理

```
[你的电脑]                          [VPS 服务器]
  私钥  ←──加密挑战/响应──→  公钥(~/.ssh/authorized_keys)
```

- **私钥**:保存在你本地,绝不能外泄(相当于你的"钥匙")
- **公钥**:放在 VPS 上(相当于"锁")
- 连接时 VPS 用公钥发起挑战,只有持有私钥的人才能正确响应

### 优势对比

| 对比项 | 密码登录 | SSH Key 登录 |
|--------|----------|--------------|
| 安全性 | 易被暴力破解 | 几乎无法破解 |
| 便捷性 | 每次输密码 | 免密直接登录 |
| 自动化 | 不便 | 适合脚本/CI |

---

## 二、前置条件

- 本地系统:Windows 10/11(自带 OpenSSH 客户端)
- 一台 Ubuntu VPS,且**当前能用密码登录**(用于首次上传公钥)
- 知道 VPS 的:IP 地址、用户名(如 root 或普通用户)、SSH 端口(默认 22)

---

## 三、操作步骤

### 第 1 步:检查本地 OpenSSH 是否已安装

打开 **PowerShell**(按 `Win + X` 选择"终端"或"Windows PowerShell"),执行:

```powershell
ssh -V
```

如果显示类似下面的输出,说明已安装:

```
OpenSSH_for_Windows_9.5p2, LibreSSL 3.8.2
```

> 如果提示找不到命令,请在"设置 → 应用 → 可选功能 → 添加功能"中安装 **OpenSSH 客户端**。

### 第 2 步:生成密钥对

在 PowerShell 中执行(把邮箱换成你自己的):

```powershell
ssh-keygen -t ed25519 -C "your_email@example.com"
```

参数说明:
- `-t ed25519`:使用 Ed25519 算法(推荐,比 RSA 更短更安全)
- `-C`:添加注释,方便识别这把钥匙是谁的

接下来会问几个问题:

```
Enter file in which to save the key (C:\Users\你的用户名/.ssh/id_ed25519):
```
**直接按回车**,使用默认路径。

```
Enter passphrase (empty for no passphrase):
```
- 留空(直接回车):方便,私钥泄露则危险
- 设置 passphrase:更安全,但每次连接要输一次

生成完成后,在 `C:\Users\你的用户名\.ssh\` 目录下会出现两个文件:

| 文件 | 说明 | 是否可外传 |
|------|------|-----------|
| `id_ed25519` | 私钥 | **绝不外传** |
| `id_ed25519.pub` | 公钥 | 可放到服务器 |

### 第 3 步:把公钥上传到 VPS

#### 方法 A:命令行一键上传(推荐)

在 PowerShell 中执行(替换 `用户名` 和 `VPS_IP`):

```powershell
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh 用户名@VPS_IP "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

这条命令做了四件事:
1. 读取本地公钥内容
2. 在 VPS 上创建 `~/.ssh` 目录
3. 把公钥追加到 `authorized_keys` 文件
4. 设置正确的权限

执行时会**最后一次要求输入 VPS 密码**,输入后即完成。

#### 方法 B:手动上传

1. 用密码登录 VPS:`ssh 用户名@VPS_IP`
2. 在 VPS 上创建 `.ssh` 目录并设置权限：
   ```bash
   mkdir -p ~/.ssh && chmod 700 ~/.ssh
   ```
3. 用记事本打开 `C:\Users\你的用户名\.ssh\id_ed25519.pub`,复制**完整一整行**公钥内容
4. 在 VPS 上执行：
   ```bash
   echo "粘贴你的完整公钥整行内容" >> ~/.ssh/authorized_keys
   ```
4. 设置密钥文件权限
   ```bash
   chmod 600 ~/.ssh/authorized_keys
   ```
5. 确认写入是否成功（可选）
   ```bash
   cat ~/.ssh/authorized_keys
   ```

> 注意：
> - 公钥全部放在双引号内部，保持一整行，不要换行拆分；
> - 使用 `>>` 是追加，不会覆盖已有密钥；如果使用 `>` 会清空覆盖文件。

### 第 4 步:配置 SSH Config(强烈推荐)

配置后可以用 `ssh myvps` 这样的简称连接,不用每次输 IP 和用户名。

编辑 `C:\Users\你的用户名\.ssh\config` 文件(没有则新建,无扩展名),写入:

```ssh-config
Host myvps
    HostName 你的VPS_IP
    User 你的用户名
    Port 22
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
    PreferredAuthentications publickey
    ServerAliveInterval 60
```

参数说明:
- `Host myvps`:自定义简称,随便起
- `HostName`:VPS 的 IP 地址
- `User`:登录用户名(root 或普通用户)
- `IdentityFile`:私钥路径
- `IdentitiesOnly yes`:只使用指定私钥,避免用错钥匙
- `ServerAliveInterval 60`:每 60 秒发心跳,防止连接断开

### 第 5 步:测试登录

```powershell
ssh myvps
```

如果配置正确,会**直接进入 VPS 命令行,不再要求密码**。

测试是否真的成功:

```bash
hostname    # 显示 VPS 主机名
whoami      # 显示当前用户
exit        # 退出
```

### 第 6 步:安全加固(强烈推荐)

确认 key 登录正常后,建议关闭密码登录,防止暴力破解。

> ⚠️ **重要**:操作前请保持当前 SSH 窗口不关,新开一个窗口测试,避免把自己锁在外面!

登录 VPS,编辑 sshd 配置:

```bash
sudo nano /etc/ssh/sshd_config
```

找到并修改以下三行(去掉前面的 `#`):

```sshd-config
PasswordAuthentication no
PubkeyAuthentication yes
PermitRootLogin prohibit-password
```

说明:
- `PasswordAuthentication no`:禁用密码登录
- `PubkeyAuthentication yes`:启用 key 登录
- `PermitRootLogin prohibit-password`:root 可用 key 登录,但禁密码

保存后重启 sshd 服务:

```bash
sudo systemctl restart ssh
```

**验证:** 新开一个 PowerShell 窗口,执行 `ssh myvps`,确认仍能登录。如果失败,回到 VPS 窗口把 `PasswordAuthentication` 改回 `yes` 再重启 sshd。

---

## 四、常见问题排查

### 问题 1:`Permission denied (publickey)`

**最常见原因:** VPS 上 `~/.ssh` 或 `authorized_keys` 权限不对。

**解决:** 登录 VPS(用密码或控制台)执行:

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
chown -R $USER:$USER ~/.ssh
```

### 问题 2:还是要求输入密码

**可能原因:**
1. 公钥内容粘贴时换行或多空格 → 重新上传
2. `sshd_config` 中 `PubkeyAuthentication` 设为 `no` → 改为 `yes`
3. 私钥没被使用 → 用 `ssh -v myvps` 查看调试信息

### 问题 3:`ssh myvps` 提示无法解析主机名

**原因:** `config` 文件没配置或路径不对。

**解决:** 确认文件在 `C:\Users\你的用户名\.ssh\config`,且内容正确(参考第 4 步)。

### 问题 4:Windows 提示私钥权限太开放

**解决:** 右键 `id_ed25519` → 属性 → 安全 → 高级 → 禁用继承 → 移除其他用户,只保留当前用户。

### 问题 5:连接超时

**排查:**
1. VPS 防火墙是否放行 22 端口
2. VPS IP 是否正确
3. 本地网络是否能访问外网(`ping VPS_IP`)

### 调试技巧:用 verbose 模式查看详细过程

```powershell
ssh -v myvps
```

输出会显示:使用哪个私钥、服务端接受哪些认证方式、卡在哪一步,是排查问题的利器。

---

## 五、命令速查表

| 操作 | 命令 |
|------|------|
| 生成密钥 | `ssh-keygen -t ed25519 -C "邮箱"` |
| 上传公钥 | `type ~/.ssh/id_ed25519.pub \| ssh 用户@IP "cat >> ~/.ssh/authorized_keys"` |
| 连接 VPS | `ssh myvps` |
| 指定私钥连接 | `ssh -i ~/.ssh/id_ed25519 用户@IP` |
| 调试连接 | `ssh -v myvps` |
| 重启 sshd | `sudo systemctl restart ssh` |
| 查看 sshd 配置 | `sudo nano /etc/ssh/sshd_config` |

---

## 六、安全建议

1. **私钥绝不外传**——不要上传到 GitHub、不要发到聊天群
2. **关闭密码登录**——配置完成后务必执行第 6 步
3. **设置 passphrase**——私钥即使泄露,没有 passphrase 也无法使用
4. **定期更换密钥**——建议每年更换一次
5. **不同服务器用不同密钥**——一把钥匙开一把锁,避免连环失守
6. **保管好备份**——私钥丢失需要重新生成并更新所有服务器

---

## 七、延伸阅读

- [OpenSSH 官方文档](https://www.openssh.com/manual.html)
- [SSH 端口转发](https://www.ssh.com/academy/ssh/tunneling)
- [SSH Agent 详解](https://www.ssh.com/academy/ssh/agent)

---

**祝你配置顺利!遇到问题多用 `ssh -v` 查看日志,大部分问题都能从中找到线索。**
