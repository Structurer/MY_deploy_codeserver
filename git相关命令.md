# Git 常用完整命令手册
按工作流程分类，包含**本地操作、仓库创建、分支、暂存、提交、远程、合并冲突、回滚撤销、标签、配置、排查**，可直接复制使用。

## 一、基础配置（首次使用git必做）
```bash
# 设置用户名、邮箱（全局，所有仓库生效）
git config --global user.name "你的名字"
git config --global user.email "你的邮箱@shturl."

# 查看全局配置
git config --global --list

# 当前仓库单独配置（不加--global）
git config user.name "仓库专属名字"

# 设置默认编辑器
git config --global core.editor "code --wait"
```

## 二、初始化仓库 & 克隆仓库
```bash
# 在当前文件夹初始化为git仓库，生成 .git隐藏文件夹
git init

# 克隆远程仓库到本地
git clone shturl.cc/JQzxe1Fc24lzbrDtTE0E

# 克隆并指定本地文件夹名字
git clone shturl.cc/JQzxe1Fc24lzbrDtTE0E myproject
```

## 三、查看状态、日志
```bash
# 查看工作区状态：哪些文件修改、未跟踪
git status

# 简洁版状态输出
git status -s

# 查看提交日志
git log

# 简洁日志，一行显示一条提交
git log --oneline

# 图形化看分支提交历史
git log --oneline --graph --all

# 查看某个文件的修改历史
git log filename.py

# 看每次提交具体改动内容
git log -p
```

## 四、工作区 → 暂存区 → 本地仓库（add / commit）
```bash
# 添加单个文件到暂存区
git add test.py

# 添加多个文件
git add a.py shtu

# 添加当前目录所有修改、新增文件到暂存
git add .

# 只跟踪已经被git管理的文件（不新增untrack文件）
git add -u

# 提交暂存区内容，必须写提交说明
git commit -m "feat: 新增用户登录功能"

# 修改上一次提交（不生成新commit，适合漏提交文件）
git commit --amend
```

## 五、查看改动 diff
```bash
# 工作区 vs 暂存区：看还没add的改动
git diff

# 暂存区 vs 本地仓库：看已经add还没commit的改动
git diff --staged

# 对比两个commit之间差异
git diff commitid1 commitid2

# 指定文件对比
git diff commitid1 commitid2 -- test.py
```

## 六、分支操作（高频）
```bash
# 查看本地分支，*代表当前分支
git branch

# 查看本地+远程全部分支
git branch -a

# 创建新分支（不会切换过去）
git branch dev

# 创建并切换到新分支
git checkout -b dev

# git 2.23+ 新命令，推荐使用
git switch -c dev   # 创建+切换分支
git switch main     # 切换到main分支

# 删除本地分支（分支已经合并完）
git branch -d dev

# 强制删除未合并的分支
git branch -D dev

# 重命名本地分支
git branch -m oldname newname
```

## 七、远程仓库 remote
```bash
# 查看远程仓库地址
git remote -v

# 添加远程仓库，origin是远程仓库别名
git remote add origin shturl.cc/JQzxe1Fc24lzbrDtTE0E

# 修改远程仓库地址
git remote set-url origin https://github.com/xxx/demo.git

# 删除远程关联
git remote remove origin

# 拉取远程最新到本地（不合并）
git fetch origin

# 拉取远程main分支并合并到当前分支
git pull origin main

# 推送本地分支到远程
git push origin dev

# 第一次推送本地新分支，建立上下游关联
git push -u origin dev

# 删除远程分支
git push origin --delete dev
```

## 八、合并 & 变基 merge / rebase
```bash
# 在main分支，把dev分支合并进来
git checkout main
git merge dev

# 变基：把dev的提交接到main末尾（整理提交线）
git checkout dev
git rebase main

# 遇到冲突后，解决完冲突执行
git add .
git rebase --continue

# 终止rebase操作，放弃变基
git rebase --abort
```

> 冲突提示：文件出现 `<<<<<<< HEAD` 标记，手动修改文件后add，再继续。

## 九、撤销、回滚（重点，容易踩坑）
### 1. 撤销工作区修改（文件还没add）
```bash
# 丢弃单个文件本地修改，恢复到暂存区版本
git checkout -- test.py

# git2.23+新版
git restore test.py
```

### 2. 撤销add，文件从暂存区退回工作区，修改保留
```bash
git reset HEAD test.py

# 全部文件取消暂存
git reset HEAD .
```

### 3. reset回退提交（本地commit回滚）
```bash
# soft：回退commit，改动保留在暂存区（最安全）
git reset --soft 提交id

# mixed（默认）：回退commit，改动放回工作区
git reset 提交id

# hard：彻底丢弃所有改动，谨慎！会删除代码
git reset --hard 提交id
```

> ⚠️ `git reset --hard` 不要对已经push到远程的commit使用！

### 4. revert：生成新提交撤销旧提交（适合远程已推送代码）
```bash
git revert 要撤销的commitID
```

## 十、储藏工作现场 stash（临时保存没提交的代码）
开发到一半要切分支，不想提交半成品，用stash
```bash
# 储藏当前未提交工作现场
git stash

# 储藏并写备注
git stash save "临时保存：写一半的登录接口"

# 查看储藏列表
git stash list

# 恢复最新储藏，不删除储藏记录
git stash apply

# 恢复并删掉这条储藏
git stash pop

# 删除指定stash
git stash drop stash@{0}

# 清空全部储藏
git stash clear
```

## 十一、标签 tag（版本号，v1.0.0）
```bash
# 创建轻量标签
git tag v1.0.0

# 创建带备注的标签
git tag -a v1.0.1 -m "版本1.0.1，修复bug"

# 查看所有标签
git tag

# 推送单个标签到远程
git push origin v1.0.0

# 推送全部本地标签
git push origin --tags

# 删除本地标签
git tag -d v1.0.0

# 删除远程标签
git push origin --delete v1.0.0
```

## 十二、其他实用命令
```bash
# 查看某个提交具体修改
git show commit_id

# 查看某个文件每一行是谁修改的
git blame test.py

# 清理工作区未跟踪文件（删除新建还没add的文件）
git clean -n  # 预览会删哪些
git clean -fd #真正删除文件+文件夹

# 找回被删除的commit（git reflog，救急神器）
git reflog
```

## 📌 日常标准工作流程示例
```bash
git pull origin dev   #拉取远程最新
git switch -c feat/user #新建功能分支
#写代码
git add .
git commit -m "feat:完成用户模块"
git push -u origin feat/user
# 提合并请求，合并到dev分支
```
