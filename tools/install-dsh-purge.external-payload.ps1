<#
  dsh-purge 1.1.90 离线安装器（Windows / PowerShell 5.1+）
  用法（在本文件所在目录）：
    powershell -NoProfile -ExecutionPolicy Bypass -File .\dsh-purge-installer.ps1
  可选参数：
    -DshHome "C:\Users\你\.dsh"   指定 DSH_HOME
    -Payload "C:\path\payload.tgz" 指定主体包
    -KeepPrompt                    不预铺 prompt-inject.md（留给插件自己 seed）
    -Force                         目标目录被占用时仍尝试替换（默认会中止并提示）
#>
param(
  [string]$DshHome = "",
  [string]$Payload = "",
  [switch]$KeepPrompt,
  [switch]$Force
)

$ErrorActionPreference = "Continue"
$script:okCount = 0
$script:failCount = 0
$NL = [char]10

function Say([string]$m, [string]$c = "Gray") { Write-Host $m -ForegroundColor $c }
function Head([string]$m) { Write-Host ""; Write-Host "== $m ==" -ForegroundColor Cyan }
function Test-DirLocked([string]$p) {
  # 目录是否被进程持有：尝试原地改名再改回来，失败即视为被占用
  if (-not (Test-Path -LiteralPath $p)) { return $false }
  $leaf = Split-Path $p -Leaf
  $par  = Split-Path $p -Parent
  $probe = Join-Path $par ($leaf + ".lockprobe")
  try {
    Rename-Item -LiteralPath $p -NewName ($leaf + ".lockprobe") -ErrorAction Stop
  } catch { return $true }
  try { Rename-Item -LiteralPath $probe -NewName $leaf -ErrorAction Stop } catch { }
  return $false
}

function WriteText([string]$path, [string]$text) {
  [IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
}

# ================= 1. DSH_HOME =================
Head "1/5 locate DSH_HOME"
if (-not $DshHome) {
  if ($env:DSH_HOME) { $DshHome = $env:DSH_HOME }
  elseif (Test-Path (Join-Path $env:USERPROFILE ".dsh\profiles")) { $DshHome = Join-Path $env:USERPROFILE ".dsh" }
}
if (-not $DshHome -or -not (Test-Path (Join-Path $DshHome "profiles"))) {
  Say "找不到 DSH_HOME（当前：$DshHome）。用 -DshHome 指定，例如：" "Red"
  Say '  powershell -NoProfile -ExecutionPolicy Bypass -File .\dsh-purge-installer.ps1 -DshHome "C:\Users\你\.dsh"' "DarkGray"
  exit 1
}
Say "DSH_HOME = $DshHome" "Green"

# ================= 2. payload =================
Head "2/5 locate payload"
if (-not $Payload) {
  foreach ($c in @((Join-Path $PSScriptRoot "payload.tgz"), (Join-Path (Get-Location).Path "payload.tgz"))) {
    if ($c -and (Test-Path $c)) { $Payload = $c; break }
  }
}
if (-not $Payload -or -not (Test-Path $Payload)) {
  # 没有外置 payload -> 用内嵌 base64 落盘（本文件自包含）
  Say "外置 payload 不存在，使用内嵌数据解出..."
  $Payload = Join-Path $env:TEMP "dsh-purge-payload-$([guid]::NewGuid().ToString('N')).tgz"
  $bytes = [Convert]::FromBase64String($B64COMPRESSED)
  [IO.File]::WriteAllBytes($Payload, $bytes)
  $script:TempPayload = $Payload
  Say "内嵌数据已解出"
}
$Payload = (Resolve-Path $Payload).Path
$pLen = (Get-Item $Payload).Length
Say ("payload = {0}  ({1:N0} bytes)" -f $Payload, $pLen) "Green"

# ================= 3. node.exe =================
Head "3/5 locate node.exe"
function Find-NodeExe {
  $cands = New-Object System.Collections.Generic.List[string]
  if ($env:DSH_NODE) { $cands.Add($env:DSH_NODE) }
  foreach ($p in (Get-Process -ErrorAction SilentlyContinue)) {
    if ($p.ProcessName -notmatch 'DeepSeek|dsh|electron') { continue }
    try {
      $exe = $p.Path
      if (-not $exe) { continue }
      $dir = Split-Path $exe -Parent
      $cands.Add((Join-Path $dir "resources\runtime\bin\node.exe"))
      $cands.Add((Join-Path $dir "runtime\bin\node.exe"))
      $cands.Add((Join-Path $dir "resources\app.asar.unpacked\runtime\bin\node.exe"))
    } catch { }
  }
  $roots = @(
    "D:\dpsk",
    (Join-Path $env:LOCALAPPDATA "Programs\DeepSeek Harness"),
    (Join-Path $env:LOCALAPPDATA "Programs\deepseek-harness"),
    (Join-Path $env:LOCALAPPDATA "DeepSeek Harness"),
    (Join-Path $env:LOCALAPPDATA "dsh"),
    "C:\Program Files\DeepSeek Harness",
    "C:\Program Files (x86)\DeepSeek Harness"
  )
  foreach ($r in $roots) {
    $cands.Add((Join-Path $r "resources\runtime\bin\node.exe"))
    $cands.Add((Join-Path $r "runtime\bin\node.exe"))
  }
  $w = Get-Command node.exe -ErrorAction SilentlyContinue
  if ($w) { $cands.Add($w.Source) }
  foreach ($c in $cands) { if ($c -and (Test-Path $c)) { return $c } }
  return ""
}
$NodeExe = Find-NodeExe
if ($NodeExe) { Say "node = $NodeExe" "Green" }
else { Say "没找到 node.exe —— 将走纯 PowerShell 兜底写配置（同样可用）" "Yellow" }

# ================= 4. profiles =================
Head "4/5 locate profiles"
$profiles = New-Object System.Collections.Generic.List[string]
foreach ($d in (Get-ChildItem (Join-Path $DshHome "profiles") -Directory -ErrorAction SilentlyContinue)) {
  $pkg = Join-Path $d.FullName "package.json"
  if (-not (Test-Path $pkg)) { continue }
  try { $j = Get-Content $pkg -Raw -Encoding UTF8 | ConvertFrom-Json } catch { continue }
  $isProfile = $false
  if ($j.name -like "dsh-profile-*") { $isProfile = $true }
  if ($j.dsh -and $j.dsh.profile) { $isProfile = $true }
  if ($isProfile) { $profiles.Add($d.FullName) }
}
if ($profiles.Count -eq 0) { Say "profiles 下没有可识别的 profile" "Red"; exit 1 }
foreach ($p in $profiles) { Say "profile: $p" }

# ================= 5. install =================
$tarExe = Join-Path $env:SystemRoot "System32\tar.exe"
if (-not (Test-Path $tarExe)) { $tarExe = "tar" }

$insertBlock = @(
  "- insert:",
  "    - id: dsh-purge",
  "      name: dsh-purge",
  "      inject: [systemPrompt, tools]",
  "      config:",
  "        enabled: true",
  "        stripMnemon: true",
  "        capabilityProtocol: true",
  "        hooksDenyBypass: true"
) -join $NL

foreach ($prof in $profiles) {
  Head ("5/5 install -> " + $prof)
  $nm = Join-Path $prof "node_modules"
  if (-not (Test-Path $nm)) { New-Item -ItemType Directory -Force -Path $nm | Out-Null }
  $dest = Join-Path $nm "dsh-purge"
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"

  if (Test-Path $dest) {
    if (Test-DirLocked $dest) {
      Say ("目标目录被占用，无法替换：" + $dest) "Red"
      if (-not $Force) {
        Say "请完全退出 DeepSeek Harness（含托盘图标）后重跑本脚本；或加 -Force 尝试强推。" "Yellow"
        $script:failCount++
        continue
      }
      Say "已指定 -Force，继续尝试（可能失败）。" "Yellow"
    }
    $bak = Join-Path $nm (".dsh-purge.bak-" + $stamp)
    Say "已有旧版本 -> 备份到 $bak"
    try { Move-Item -LiteralPath $dest -Destination $bak -Force -ErrorAction Stop }
    catch {
      Say ("无法移走旧目录（文件被占用）：" + $_.Exception.Message) "Red"
      Say ("请完全退出 DeepSeek Harness 后重跑，或手工删除：" + $dest) "Yellow"
      $script:failCount++
      continue
    }
  }

  $tmp = Join-Path $env:TEMP ("dsh-purge-unpack-" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  & $tarExe -xzf $Payload -C $tmp
  if ($LASTEXITCODE -ne 0) { Say "解包失败（tar 退出码 $LASTEXITCODE）" "Red"; $script:failCount++; continue }
  $src = Join-Path $tmp "package"
  if (-not (Test-Path $src)) { $src = $tmp }
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  try { Copy-Item -Path (Join-Path $src "*") -Destination $dest -Recurse -Force -ErrorAction Stop }
  catch { Say ("复制文件失败（目录被占用？）：" + $_.Exception.Message) "Red"; Say ("请完全退出 DeepSeek Harness 后重跑，或手工删除：" + $dest) "Yellow"; $script:failCount++; continue }
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

  $ver = "?"
  try { $ver = (Get-Content (Join-Path $dest "package.json") -Raw -Encoding UTF8 | ConvertFrom-Json).version } catch { }
  $cnt = (Get-ChildItem $dest -Recurse -File).Count
  Say ("解包完成 dsh-purge@{0}  ({1} 个文件)" -f $ver, $cnt) "Green"

  $ensured = $false
  if ($NodeExe) {
    $env:INIT_CWD = $prof
    $env:npm_config_local_prefix = $prof
    $out = & $NodeExe (Join-Path $dest "scripts\ensure-profile-bundle.mjs") 2>&1
    $code = $LASTEXITCODE
    foreach ($line in $out) { Say ("  " + $line) }
    if ($code -eq 0) { $ensured = $true; Say "插件自带补丁脚本执行成功" "Green" }
    else { Say "补丁脚本退出码 $code，转 PowerShell 兜底" "Yellow" }
  }

  # ---------- package.json: dsh.profile.bundles ----------
  $pkgPath = Join-Path $prof "package.json"
  try {
    $j = Get-Content $pkgPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $bundles = @()
    if ($j.dsh -and $j.dsh.profile -and $j.dsh.profile.bundles) { $bundles = @($j.dsh.profile.bundles) }
    if ($bundles -notcontains "dsh-purge") {
      if (-not $j.dsh) { $j | Add-Member -NotePropertyName dsh -NotePropertyValue ([pscustomobject]@{}) -Force }
      if (-not $j.dsh.profile) { $j.dsh | Add-Member -NotePropertyName profile -NotePropertyValue ([pscustomobject]@{}) -Force }
      $newBundles = @($bundles) + "dsh-purge"
      $j.dsh.profile | Add-Member -NotePropertyName bundles -NotePropertyValue $newBundles -Force
      Copy-Item $pkgPath ($pkgPath + ".bak-" + $stamp) -ErrorAction SilentlyContinue
      WriteText $pkgPath ($j | ConvertTo-Json -Depth 40)
      Say "已写入 dsh.profile.bundles += dsh-purge" "Green"
    } else { Say "dsh.profile.bundles 已含 dsh-purge，跳过" }
  } catch { Say ("改写 package.json 失败：" + $_.Exception.Message) "Red" }

  # ---------- cordis.patch.yml: 本体 insert ----------
  $patchPath = Join-Path $prof "cordis.patch.yml"
  $ptext = ""
  if (Test-Path $patchPath) { $ptext = [IO.File]::ReadAllText($patchPath) }
  $hasInsert = ($ptext -match '(?m)^\s*-\s*id:\s*dsh-purge(-main)?\s*$') -or ($ptext -match '(?m)^\s*-\s*name:\s*dsh-purge\s*$')
  if ($hasInsert) {
    Say "cordis.patch.yml 已有本体 insert，跳过"
  } else {
    $data = @()
    foreach ($l in ($ptext -split "`r?`n")) {
      $t = $l.Trim()
      if ($t -eq "") { continue }
      if ($t.StartsWith("#")) { continue }
      if ($t -match '^---$') { $data = @(); continue }
      $data += $t
    }
    $newText = $null
    $isEmptyFlow = ($data.Count -eq 1 -and $data[0] -match '^\[\s*\]$')
    $isBlockSeq  = ($data.Count -gt 0 -and $data[0] -match '^-\s')
    if ($data.Count -eq 0) {
      $newText = $insertBlock + $NL
    } elseif ($isEmptyFlow) {
      $newText = [regex]::Replace($ptext, '(?m)^\s*\[\s*\]\s*$', $insertBlock, 1)
      if (-not $newText.EndsWith($NL)) { $newText += $NL }
    } elseif ($isBlockSeq) {
      $sep = ""
      if ($ptext -ne "" -and -not $ptext.EndsWith($NL)) { $sep = $NL }
      $newText = $ptext + $sep + $NL + $insertBlock + $NL
    } else {
      Say "cordis.patch.yml 形态认不准（非块序列），未改动。请手工粘贴下面这段：" "Yellow"
      Say $insertBlock "DarkGray"
    }
    if ($newText -ne $null) {
      if (Test-Path $patchPath) { Copy-Item $patchPath ($patchPath + ".bak-" + $stamp) -ErrorAction SilentlyContinue }
      WriteText $patchPath $newText
      Say "已写入 cordis.patch.yml 本体 insert" "Green"
    }
  }

  # ---------- pnpm-workspace.yaml: allowBuilds ----------
  $wsPath = Join-Path $prof "pnpm-workspace.yaml"
  $ws = ""
  if (Test-Path $wsPath) { $ws = [IO.File]::ReadAllText($wsPath) }
  if ($ws -match '(?m)^[ \t]+dsh-purge:\s*true\s*$') {
    Say "pnpm allowBuilds 已含 dsh-purge，跳过"
  } else {
    $lines = @()
    if ($ws -ne "") { $lines = $ws -split "`r?`n" }
    $outL = New-Object System.Collections.Generic.List[string]
    foreach ($l in $lines) { $outL.Add($l) }
    $idx = -1
    for ($i = 0; $i -lt $outL.Count; $i++) {
      if ($outL[$i] -match '^allowBuilds:\s*$') { $idx = $i; break }
    }
    if ($idx -ge 0) {
      $outL.Insert($idx + 1, "  dsh-purge: true")
    } else {
      if ($outL.Count -gt 0 -and $outL[$outL.Count - 1] -ne "") { $outL.Add("") }
      $outL.Add("allowBuilds:")
      $outL.Add("  dsh-purge: true")
    }
    $ws2 = ($outL -join $NL)
    if (-not $ws2.EndsWith($NL)) { $ws2 += $NL }
    if (Test-Path $wsPath) { Copy-Item $wsPath ($wsPath + ".bak-" + $stamp) -ErrorAction SilentlyContinue }
    WriteText $wsPath $ws2
    Say "已写入 pnpm allowBuilds" "Green"
  }

  # ---------- prompt-inject.md ----------
  if (-not $KeepPrompt) {
    $pinj = Join-Path $DshHome "prompt-inject.md"
    if (Test-Path $pinj) {
      Say "prompt-inject.md 已存在（用户稿），保留不覆盖"
    } else {
      $defZh = Join-Path $dest "lib\default-prompt-inject.zh.md"
      $defEn = Join-Path $dest "lib\default-prompt-inject.en.md"
      $def = ""
      if (Test-Path $defZh) { $def = $defZh } elseif (Test-Path $defEn) { $def = $defEn }
      if ($def -ne "") {
        Copy-Item $def $pinj
        Say "已预铺默认提示词 -> $pinj" "Green"
      } else { Say "包内没找到默认提示词，交给插件首次启动自己 seed" "Yellow" }
    }
  }

  $script:okCount++
}

# ================= 收尾 =================
Head "done"
$msg = ("安装成功 {0} 个 profile，失败 {1} 个" -f $script:okCount, $script:failCount)
if ($script:failCount -gt 0) { Say $msg "Yellow" } else { Say $msg "Green" }
Say ""
Say "下一步（按顺序）：" "Cyan"
Say "  1) 完全退出 DeepSeek Harness（含托盘图标，任务管理器确认没有 DeepSeek Harness.exe）"
Say "  2) 重新启动 DeepSeek Harness"
Say "  3) 进 设置 -> 破甲(dsh-purge) 面板，点【应用】—— 这一步会解开 app.asar 打宿主补丁，会自动重启一次"
Say "  4) 再进面板确认：提示词已注入、patch 数大于 0、状态显示 applied"
Say ""
Say "提示1：装完后别在 profile 目录跑 pnpm install —— lock 里 dsh-purge 指向 GitHub，那个地址拉不到。" "DarkGray"
Say "提示2：若要覆盖安装/修复，先退出 DSH，再跑同一条命令；旧版本会留在 node_modules\.dsh-purge.bak-<时间>。" "DarkGray"
Say "提示3：卸载 = 删掉 node_modules\dsh-purge，并从 package.json 的 dsh.profile.bundles 与 cordis.patch.yml 的 - id: dsh-purge 块里去掉。" "DarkGray"
if ($script:TempPayload -and (Test-Path $script:TempPayload)) { Remove-Item $script:TempPayload -Force -ErrorAction SilentlyContinue }
if ($script:failCount -gt 0) { exit 1 } else { exit 0 }
