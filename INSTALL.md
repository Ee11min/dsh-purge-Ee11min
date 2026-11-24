# 离线实装（其他电脑）

本仓库自带离线安装件，**不需要联网、不需要 node、不需要 pnpm、不需要 7z**。
目标机要求：Windows 10/11 + 系统自带 PowerShell 5.1 + 已装 DeepSeek Harness。

## 一条命令

```powershell
irm https://raw.githubusercontent.com/Ee11min/dsh-purge-Ee11min/master/tools/dsh-purge-installer.ps1 -OutFile "$env:TEMP\dsh-purge-installer.ps1"; & "$env:TEMP\dsh-purge-installer.ps1"
```

克隆下来本地跑（离线可用）：

```powershell
git clone https://github.com/Ee11min/dsh-purge-Ee11min.git
cd dsh-purge-Ee11min\tools
powershell -NoProfile -ExecutionPolicy Bypass -File .\dsh-purge-installer.ps1
```

## 参数

| 参数 | 说明 |
| --- | --- |
| `-DshHome "C:\Users\你\.dsh"` | 手动指定 DSH_HOME（默认 `$env:DSH_HOME` → `%USERPROFILE%\.dsh`） |
| `-Payload "C:\path\payload.tgz"` | 手动指定插件本体包 |
| `-KeepPrompt` | 不预铺 `prompt-inject.md`，留给插件首次启动自己 seed |
| `-Force` | 目标目录被占用时仍强行尝试替换 |

## 安装器做什么

1. 定位 DSH_HOME
2. 定位插件本体：`tools/payload.tgz` 优先，没有就解安装器内嵌的 base64（收尾删除）
3. 自动找 DSH 自带 node.exe（`<安装根>\resources\runtime\bin\node.exe`）
4. 枚举 `profiles\*` 下所有 profile
5. 每个 profile：
   - 旧 `node_modules\dsh-purge` 备份为 `.dsh-purge.bak-<时间戳>`
   - `tar.exe -xzf` 落盘 81 个文件
   - 跑插件自带 `scripts\ensure-profile-bundle.mjs`
   - 无论 node 成败，都用纯 PowerShell 幂等兜底写三处配置：
     - `package.json` → `dsh.profile.bundles += "dsh-purge"`
     - `cordis.patch.yml` → 追加本体 `- id: dsh-purge` insert 块
     - `pnpm-workspace.yaml` → `allowBuilds: dsh-purge: true`
   - `prompt-inject.md` 不存在时预铺默认提示词
   - 被改文件都留 `.bak-<时间戳>`

## 装完必须做 4 步

1. 完全退出 DeepSeek Harness（含托盘图标）
2. 重新启动
3. 设置 → 破甲(dsh-purge) 面板 → 点【应用】（解 `app.asar` 打宿主补丁，会自动重启一次）
4. 再进面板确认：提示词已注入、patch 数 > 0、状态 applied

## 注意

- 装完不要在 profile 目录跑 `pnpm install` —— 新版 DSH 会去 `dsh.install` 里写的地址拉包，离线环境会失败。
- 修复/覆盖安装：退出 DSH，重跑同一条命令。
- 卸载：删 `node_modules\dsh-purge`，并从 `package.json` 的 `dsh.profile.bundles` 与 `cordis.patch.yml` 的 `- id: dsh-purge` 块里去掉。

## 已验证场景

空 profile / 已有其他 insert 块的真实 profile / 找不到 node.exe / 重复执行（幂等）/ 无外置 payload（走内嵌）/ 中文带空格路径 / 目录被占用中止 / `-Force` 安全中止 —— 全部通过。
