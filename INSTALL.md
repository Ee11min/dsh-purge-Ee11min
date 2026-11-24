# 离线实装到其他电脑（Windows）

不需要联网、不需要 node、不需要 pnpm、不需要 7z、不需要管理员权限。
目标机：Windows 10/11 + 系统自带 PowerShell 5.1 + 已装好 DeepSeek Harness。

---

## 一条命令（推荐）

在目标机按 `Win + X` → **Windows PowerShell**（或终端里选 PowerShell），整行粘进去回车：

```powershell
$u='https://github.com/Ee11min/dsh-purge-Ee11min/releases/download/v1.1.90/dsh-purge-installer.ps1';$f="$env:TEMP\dsh-purge-installer.ps1";(New-Object Net.WebClient).DownloadFile($u,$f);powershell -NoProfile -ExecutionPolicy Bypass -File $f
```

看到 `安装成功 N 个 profile；失败 0 个` 就成了。

带参数跑（例如目标机 DSH_HOME 不在默认位置）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\dsh-purge-installer.ps1" -DshHome "D:\my\.dsh"
```

---

## 完全断网时：拷文件过去

1. 本机下 **payload + installer** 两个文件（或用 `git clone` 整个仓库）：
   - <https://github.com/Ee11min/dsh-purge-Ee11min/releases/download/v1.1.90/dsh-purge-installer.ps1>
   - <https://github.com/Ee11min/dsh-purge-Ee11min/releases/download/v1.1.90/payload.tgz>
2. 两个文件放进同一个文件夹（U 盘 / 局域网共享 / Everything HTTP 都行）。
3. 目标机在那个文件夹里开 PowerShell：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\dsh-purge-installer.ps1
```

只拷了 installer 一个文件也能装 —— 它内嵌了完整 payload（自解到 `%TEMP%`，装完自动删）。

---

## 参数

| 参数 | 说明 |
| --- | --- |
| `-DshHome "C:\Users\你\.dsh"` | 手动指定 DSH_HOME（默认 `$env:DSH_HOME` → `%USERPROFILE%\.dsh`） |
| `-Payload "C:\path\payload.tgz"` | 手动指定插件本体包 |
| `-KeepPrompt` | 不预铺 `prompt-inject.md`，留给插件首次启动自己 seed |
| `-Force` | 目标目录被占用时仍强行尝试替换（默认安全中止） |

---

## 安装器做什么

1. 定位 `DSH_HOME`
2. 定位插件本体：`tools/payload.tgz` 或同目录 `payload.tgz` 优先，找不到就解安装器内嵌的 base64
3. 自动找 DSH 自带 `node.exe`（`<安装根>\resources\runtime\bin\node.exe`，找不到就走纯 PowerShell 分支）
4. 枚举 `profiles\*` 下所有 profile
5. 每个 profile：
   - 旧 `node_modules\dsh-purge` 备份成 `.dsh-purge.bak-<时间戳>`
   - `tar.exe -xzf` 落盘 81 个文件
   - 调插件自带 `scripts\ensure-profile-bundle.mjs`
   - 无论 node 成败，都用纯 PowerShell 幂等兜底写三处：
     - `package.json` → `dsh.profile.bundles += "dsh-purge"`
     - `cordis.patch.yml` → 追加本体 `- id: dsh-purge` 的 `insert` 块
     - `pnpm-workspace.yaml` → `allowBuilds: dsh-purge: true`
   - `prompt-inject.md` 不存在时预铺默认提示词
   - 所有被改的文件都留 `.bak-<时间戳>`

---

## 装完必须做 4 步

1. **完全退出** DeepSeek Harness（含托盘图标；任务管理器确认没有 `DeepSeek Harness.exe`）
2. 重新启动 DeepSeek Harness
3. 打开 **设置 → 破甲（dsh-purge）** 面板，点【应用】—— 这一步解 `app.asar` 打宿主补丁，会自动重启一次
4. 再进面板确认：提示词已注入、patch 数 > 0、状态 `applied`

---

## 注意

- 装完**不要**在 profile 目录跑 `pnpm install`：DSH 会按 `dsh.install` 里写的地址去 GitHub 拉包，离线环境会失败。
- 修复 / 覆盖安装：退出 DSH，重跑同一条命令即可（幂等，重复跑三处配置字节不变）。
- 卸载：删 `node_modules\dsh-purge`，并从 `package.json` 的 `dsh.profile.bundles` 与 `cordis.patch.yml` 的 `- id: dsh-purge` 块里去名。
- 本插件是自托管 fork：`package.json` / `lib/update.js` / `client.js` 里的仓库地址都指向 `Ee11min/dsh-purge-Ee11min`，上游署名与 Apache-2.0 要求见 [NOTICE](NOTICE)。

---

## 已验证场景

空 profile · 已有其他 `insert` 块的真实 profile · 找不到 `node.exe` · 重复执行（幂等，三文件 sha256 不变） · 无外置 payload 走内嵌 · 中文带空格路径 · 目录被占用中止不留半装 · `-Force` 安全中止 · 从 GitHub release 真实下载后执行 —— 全部通过。
