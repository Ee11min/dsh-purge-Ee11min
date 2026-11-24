# dsh-purge 1.1.90 离线实装包

目标机要求：Windows 10/11 + PowerShell 5.1（系统自带）+ 已装 DeepSeek Harness。
不需要联网、不需要 node、不需要 pnpm、不需要 7z。

## 文件

| 文件 | 用途 |
| --- | --- |
| `dsh-purge-installer.ps1` | 主交付件。1.1 MB，插件本体以 base64 内嵌在里面，单文件即可安装 |
| `payload.tgz` | 插件本体压缩包（810 KB，81 个文件），`dsh-purge-installer.ps1` 优先读取它；不在也不影响 |
| `install-dsh-purge.external-payload.ps1` | 不内嵌的瘦版（14 KB），必须与 `payload.tgz` 同目录；以后换新包时用这个 |

## 安装

把 `dsh-purge-installer.ps1` 拷到目标机任意目录，执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\dsh-purge-installer.ps1
```

可选参数：

- `-DshHome "C:\Users\你\.dsh"` 手动指定 DSH_HOME（默认读 `$env:DSH_HOME`，再退回 `%USERPROFILE%\.dsh`）
- `-Payload "C:\path\payload.tgz"` 手动指定本体包
- `-KeepPrompt` 不预铺 `prompt-inject.md`，留给插件自己 seed
- `-Force` 目标目录被占用时仍强行尝试替换

## 安装器做了什么

1. 定位 DSH_HOME
2. 定位或解出插件本体（内嵌 base64 → %TEMP%，结束后删除）
3. 自动找 DSH 自带的 node.exe（`<安装根>\resources\runtime\bin\node.exe`）
4. 枚举 `profiles\*` 里所有 profile
5. 对每个 profile：
   - 旧 `node_modules\dsh-purge` 备份为 `.dsh-purge.bak-<时间戳>`
   - 解包落盘 81 个文件
   - 跑插件自带 `scripts\ensure-profile-bundle.mjs` 写配置
   - 无论 node 成功与否，都用纯 PowerShell 幂等兜底写三处配置：
     - `package.json` → `dsh.profile.bundles += "dsh-purge"`
     - `cordis.patch.yml` → 追加本体 insert 块
     - `pnpm-workspace.yaml` → `allowBuilds: dsh-purge: true`
   - `prompt-inject.md` 不存在时预铺默认提示词
   - 每个被改的文件都留 `.bak-<时间戳>`

## 装完必须做的

1. 完全退出 DeepSeek Harness（含托盘图标）
2. 重新启动
3. 进 设置 → 破甲(dsh-purge) 面板，点【应用】—— 这一步会解开 `app.asar` 给宿主打补丁，并自动重启一次
4. 再进面板确认：提示词已注入、patch 数 > 0、状态 applied

## 注意

- 装完不要在 profile 目录跑 `pnpm install`：lockfile 里 dsh-purge 指向 GitHub，那个地址已经拉不到了。
- 修复/覆盖安装：退出 DSH 后重跑同一条命令。
- 卸载：删 `node_modules\dsh-purge`，并从 `package.json` 的 `dsh.profile.bundles`、`cordis.patch.yml` 的 `- id: dsh-purge` 块里去掉。

## 已验证

- 空 profile（`bundles: []`、`cordis.patch.yml` 为空）→ 三处配置全部写对，81 文件到位
- 真实形态 profile（`bundles: [...]`、patch 里已有别的 insert 块、allowBuilds 里已有别的包）→ 追加不破坏，原有内容与顺序保留
- 找不到 node.exe → 全走 PowerShell 兜底，结果一致
- 重复执行 → 三文件 sha256 前后完全一致（幂等）
- 无外置 payload → 内嵌解出 810,380 bytes，与 payload.tgz sha256 一致
- 中文 + 带空格路径 → 正常
- 目录被占用 → 中止并提示，不产生半装状态
- `-Force` → 仍会在移动失败处安全中止，不丢数据
