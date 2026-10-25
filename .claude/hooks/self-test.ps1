# 守卫自测 · 一键可跑（D3 实操）
#
# 本脚本是 `docs/guard-self-test.md` 的【可执行形态】：把两格手动沙箱
# 扩成【两守卫 × 正/负控】，整段复制粘贴或直接 `-File` 跑，**只读、不碰你的工作树**。
#
# 为什么必须跑这一组：两个守卫都含【刻意静默】的分支（缺页 / 找不到 SHA 标记 /
# 无候选仓 / unborn 仓）。"它没吭声"**不构成任何证据**——「确无判据」与「脚本已死」
# 在观测上不可分（台账 `GAP-002`）。**必须先让它在「你确信该报警」的输入上报警**，
# 它的沉默才开始携带信息。本脚本就是造那组输入。
#
# 退出码：0 = 全部格子符合预期；1 = 至少一格不符（即守卫可能已瞎）。
#
# ⚠️ **本脚本此前只支持「自托管布局」**（`2026-10-16` 实测修正）：
# 它从【脚本自身位置】向上推两层当「仓库根」用，而自托管布局下那个目录**同时**是工作区根与仓库根，
# 两个含义重合 ⇒ 缺陷**不可见**；到目标布局下则**崩在第 180 行**（`git -C <工作区根>` → not a
# git repository ⇒ `$null` 上调 `.Trim()`），且 C 组**枚举塌成 0 个文件而"绿"**。
# 修法与理由见下方「基础设施」两节，与台账 `GAP-029`（本轮登记）同源。
#
# 规则权威源仍是 `AGENTS.md` §5；与本脚本冲突时以它为准（D4）。

[CmdletBinding()]
param(
    # 跑完保留沙箱目录以便查看（默认删除）
    [switch]$KeepSandbox
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- 基础设施
$HookDir = Split-Path -Parent $PSCommandPath          # <workspaceRoot>/.claude/hooks
# ⚠️ 这两个名字**必须分开**，混用是本次缺陷的根因（D4）：
#   $RepoRoot —— 【工作区根】。框架文件（AGENTS.md / .claude/ / 进度页指针）住在**这里**。
#   $GitRepo  —— 【仓库根】。`git` 操作（rev-parse / rev-list / ls-files）**只能**在**这里**跑。
# 在**自托管布局**下二者是**同一个目录**（工作区根自身含 `.git`）—— 正因如此，
# 此前用 `$RepoRoot` 一个变量兼做两件事**从未暴露**：错的那一半恰好撞对了。
# 到**目标布局**下（仓在 `project/`、工作区根**无** `.git`）二者分离，
# 混用立刻表现为：`git -C $RepoRoot` → `fatal: not a git repository` → 崩 / 静默空转。
# 这与 `AGENTS.md` §0.0 的「位置错**不会报错**，只会让此后每一步都作用在**错的仓**上」同族。
$RepoRoot = Split-Path -Parent (Split-Path -Parent $HookDir)
# 全局暴露：helper / 打桩探针都在子作用域里跑，读 `$script:` 才能拿到同一份值。
# （与本文件 `$script:Pass` / `$script:Fail` 同一手法——`& { }` 是子作用域，未限定的赋值会丢。）
$script:RepoRoot = $RepoRoot
# 打桩位（**只用于负向证伪**，见文件末的 G2）：运行时把 `$GitRepo` 置 `$null` 即模拟
# 「候选全不命中」。做成**变量**而非"改代码"，是为了让注入不动被测脚本的源码。
$GitRepo = $null
$ProgressGuard = Join-Path $HookDir 'check-progress.ps1'
$NumbersGuard  = Join-Path $HookDir 'check-numbers.ps1'

foreach ($g in @($ProgressGuard, $NumbersGuard)) {
    if (-not (Test-Path -LiteralPath $g)) { Write-Error "缺守卫：$g"; exit 1 }
}

# --- git 环境变量【族】：**唯一一份清单**，清空与 `A11` 的注入**共用它**
# 为什么必须是"族"而不是"一个变量"：`GAP-013①` 只是这个族里**最先被测到**的那一个。
# **实测（`2026-10-16`）**：只清 `GIT_DIR` 时，**`GIT_INDEX_FILE` 会让沙箱的 `git add`
# 直接写进一个无关仓的 index** —— 注入后受害仓 `index 5B00A626 → 45A64801`、
# `git status` 变成 `fatal: unable to read 2e8695b5…` ⇒ **真损坏**（不是假报警，也不是读数错）。
# 族成员之间没有"哪个次要"：每一个都指向一个**全局**位置（仓库发现 / 工作树 / 对象库 / index）。
# ⚠️ `GIT_COMMON_DIR` 与 `GIT_WORK_TREE` 在 `A11` 里实测**不劫持读取**，但**仍留在清单里**：
# 「哪个会劫持、哪个会写坏」是 git 的实现细节，不该由人记得；清掉的代价为零（`A11` 同一理由）。
$GitEnvFamily = @(
    'GIT_DIR',
    'GIT_WORK_TREE',
    'GIT_OBJECT_DIRECTORY',
    'GIT_COMMON_DIR',
    'GIT_INDEX_FILE',
    'GIT_ALTERNATE_OBJECT_DIRECTORIES',
    'GIT_CEILING_DIRECTORIES',
    'GIT_NAMESPACE',
    'GIT_PREFIX'
)

# 把整族置空、跑 `$Body`、再逐个还原（`$env:` 是**进程级**，故 save/restore）。
# 凡"会改变 git 语义"的调用都必须包在这里——**这是本文件唯一的清空点**。
function Invoke-ClearingGitEnv {
    param([scriptblock]$Body)
    $saved = @{}
    foreach ($n in $GitEnvFamily) {
        $saved[$n] = [Environment]::GetEnvironmentVariable($n)
        [Environment]::SetEnvironmentVariable($n, $null)
    }
    try {
        & $Body
    } finally {
        foreach ($n in $GitEnvFamily) { [Environment]::SetEnvironmentVariable($n, $saved[$n]) }
    }
}

# --- git 入口（与 `check-progress.ps1` 的 `Invoke-GitChecked` **同款**，D4：同一份判据不做两处实现）
# 本脚本**没有**这个 helper 时有两个坑，两个都由它一并挡住：
#   ① `GAP-013①`：环境里残留的 `GIT_DIR` 会**劫持**每一次 `git -C <repo>` —— `-C` 只是换工作目录，
#      `GIT_DIR` 覆盖的是**仓库发现**。守卫侧已实测过：被劫持时会去读**另一个仓**的 HEAD，
#      页面与它一致就**静默放行**陈旧页。（`$env:` 是进程级，故 save/restore。）
#   ② 原生命令写 stderr + 脚本级 `$ErrorActionPreference='Stop'`：PS 5.1 会把 stderr 经 `2>&1`
#      包成 NativeCommandError（ErrorRecord），被 Stop 升格为**终止异常**，把自测脚本自己打断。
#      本文件 L54-59（Invoke-Guard）与 L152-159 已为同一个坑写过注释——这里是**第三处**，
#      故抽成一个入口，而不是再抄一遍。
# **判据**：`.Exit` 是**唯一**的判据，`.Text` 只是载荷（同 check-progress.ps1 的 THE ONE RULE）。
function Invoke-GitChecked {
    param([scriptblock]$GitCall)
    $script:__gitExit = $null
    $out = $null
    try {
        $out = & {
            $ErrorActionPreference = 'Continue'
            # 整族置空（见 `$GitEnvFamily`）：只用 `GIT_DIR` 一个是不够的——
            # `GIT_INDEX_FILE` 实测会把沙箱的 `git add` 写进**无关仓**的 index。
            Invoke-ClearingGitEnv { & $GitCall }
            $script:__gitExit = $LASTEXITCODE
        }
    } catch {
        # git 根本起不来（不在 PATH / 零字节 exe）落这里。Exit 留 $null ⇒ `.Exit -eq 0` 为假 ⇒ 失败关闭。
        $script:__gitExit = $null
        $out = $null
    }
    return [pscustomobject]@{ Exit = $script:__gitExit; Text = [string]::Join("`n", @($out)).Trim() }
}

# --- 本脚本【自铺沙箱】用的 git 入口：只负责**把 `GIT_DIR` 清掉**，不判返回值
# 为什么它必须存在（`2026-10-16` 实测）：本脚本要造十几个沙箱，`git init/add/commit/checkout`
# 都直连 `git`。**环境里残留的 `GIT_DIR` 会劫持这些调用**（`GAP-013①` 同族，只是受害方不是守卫、
# 而是**尺子自己**）。实测（干净对照）：注入 `GIT_DIR` 后
#   `git -C <新目录> init -q` → `exit=0`，但 `<新目录>/.git` **不存在** ⇒ **init 静默没建仓**；
#   紧接着 `git -C <新目录> add -A` → `exit=128  fatal: this operation must be run in a work tree`。
# ⇒ 沙箱**压根不存在**，而后续格子仍在"判分"，结果是：**5 格假 FAIL + 1 格假 PASS**
# （`A1`/`A4`/`A8`/`A10`/`A11` 假报警——两条守卫其实都没坏；`A6` 假通过——它名叫
# 「沙箱确实 unborn」，而沙箱不存在，且被劫持的 `rev-parse` 返回 `Object[]`（SHA + `$LASTEXITCODE`），
# 谓词 `-ne 0` 对数组恒为真）。**D3 原话**：「误报的判据比没有判据更糟——它会教人忽略它」。
# ⚠️ 与 `Invoke-GitChecked` 的分工：那个是**判据入口**（`.Exit` 是唯一判据）；
# 这个是**造数据入口**（只清环境，不看退出码）——两件事，故两个函数，不合并。
# `$env:` 是**进程级**，故 save/restore。
function Invoke-GitRepo {
    param([scriptblock]$GitCall)
    $script:__repoGitExit = $null        # 先置空：起不来时不得读到上一次的残留值
    try {
        # 子作用域 EAP：原生命令写 stderr 会被脚本级 `Stop` 升格为终止异常（本文件已记过三处）
        $out = & {
            $ErrorActionPreference = 'Continue'
            Invoke-ClearingGitEnv { & $GitCall }
        } 2>&1
        $script:__repoGitExit = $LASTEXITCODE
    } catch {
        $script:__repoGitExit = $null    # git 起不来 ⇒ 失败关闭（调用方查 .Exit 即知）
        $out = $null
    }
    return [pscustomobject]@{ Exit = $script:__repoGitExit; Text = [string]::Join("`n", @($out)).Trim() }
}

# --- 仓库根解析：与 `check-progress.ps1:249-254` **同款候选与同款顺序**
# 候选 = 工作区根自身（自托管布局，本仓走这条）与 `project/` 子目录（目标布局）。
# **顺序不可换**：工作区根优先。一个**仅仅存在**的 `project/` 不是仓；若先试它、而后有人在里面
# `git init`，本脚本会锁进那个**空的内层仓**——找不到 HEAD，却看起来一切正常。
# 候选必须**能 resolve 成仓**（`rev-parse --git-dir` 退出码 0），不能只看 `.git` 条目在不在（`GAP-009`）。
function Resolve-GitRepo {
    foreach ($cand in @($script:RepoRoot, (Join-Path $script:RepoRoot 'project'))) {
        if (-not (Test-Path -LiteralPath (Join-Path $cand '.git'))) { continue }
        if ((Invoke-GitChecked { git -C $cand rev-parse --git-dir 2>$null }).Exit -eq 0) { return $cand }
    }
    return $null
}

# --- 主干解析（`GAP-031`）：与 `check-progress.ps1` **同款三级回退**，判据同为**退出码**
# 为什么尺子也要走这一条：守卫的比对对象已从「当前检出的 HEAD」改为「主干」（`GAP-031`）。
# 若 `E3`/`E4` 仍拿 `rev-parse --short HEAD` 当实测基准，则**在特性分支上二者永久不等** ——
# 页面记的是主干（正确），尺子量的是分支 ⇒ `E3`/`E4` **假红**。而 `D3` 的原话是
# 「**误报的判据比没有判据更糟——它会教人忽略它**」。故尺子与守卫必须同一口径（`D4`）。
# 三级顺序与守卫逐字一致，**不得各自演化**：远端默认分支 → 本地 `main` → 当前 `HEAD`。
# 返回 `$null` = 三级全不中（unborn / 仓无 HEAD）——调用方按 `GAP-012` 的原语义处置。
function Resolve-Mainline {
    param([string]$Repo)
    if (-not $Repo) { return $null }
    $oh = Invoke-GitChecked { git -C $Repo symbolic-ref --quiet refs/remotes/origin/HEAD 2>$null }
    if ($oh.Exit -eq 0 -and $oh.Text) {
        $ref = $oh.Text
        # `symbolic-ref` **不解析** unborn / dangling 目标 ⇒ 必须再验一次 `rev-parse --verify`
        if ((Invoke-GitChecked { git -C $Repo rev-parse --verify --quiet "$ref^{commit}" 2>$null }).Exit -eq 0) {
            return [pscustomobject]@{ Ref = $ref; Name = ($ref -replace '^refs/remotes/', '') }
        }
    }
    if ((Invoke-GitChecked { git -C $Repo rev-parse --verify --quiet 'refs/heads/main^{commit}' 2>$null }).Exit -eq 0) {
        return [pscustomobject]@{ Ref = 'refs/heads/main'; Name = 'main' }
    }
    if ((Invoke-GitChecked { git -C $Repo rev-parse --verify --quiet 'HEAD^{commit}' 2>$null }).Exit -eq 0) {
        return [pscustomobject]@{ Ref = 'HEAD'; Name = 'HEAD（未找到主干）' }
    }
    return $null
}

# --- 文件枚举：**布局无关**（这是本次修法的第二半，且比第一半更根本）
# 为什么不能只用 `git ls-files`：**目标布局下框架文件不在任何仓里** ⇒ `ls-files` 枚举不到它们，
# 全部检查**结构性失去输入**。实测（`2026-10-16`）：同一份脚本、同一份框架文件，
# 只因枚举口径从 53 塌成 0，C3 就从 `108 张表` 变成 `0 张表` 而**依然 PASS**——
# **「零输入而绿」与「检查过了」在观测上同形**（D3：判据必须测它声称要测的东西）。
# 两条分支，**自托管布局走原路**（读数与改前**逐字节一致**，那条路已被验证过，不顺手改掉）：
#   (a) 工作区根自身是仓 ⇒ `git -C $RepoRoot ls-files <pathspec>`（原实现）；
#   (b) 否则 ⇒ 遍历工作区根的文件系统（框架文件不在仓里，但**在工作区里**）。
# **两条分支统一返回相对 `$RepoRoot` 的相对路径**——下游一律 `Join-Path $RepoRoot $f`，故无需改动：
# `git ls-files` 本来给的就是相对路径，遍历则把绝对路径**换算**回去（这正是两口径可比的关键）。
#
# 遍历的三条硬要求（`2026-10-16` 在真实目标布局（某采用方工作区）实测过该算法）：
#   ① **凡子目录自身含 `.git` ⇒ 整棵跳过** —— 那是业务仓根（`project/` 也在其中），
#      框架规则管框架仓、不管业务仓；实测该算法在采用方工作区下给出 `MD=68 PS1=6`，
#      **全部是框架文件 + 工作区根自身文档，一个业务仓文件都没误扫**。
#      ⚠️ 用 `Test-Path <dir>/.git` 判定即可：`project/` 常常是**符号链接**，而含 `.git` 的**目标**
#      经 `Test-Path` 解析后照样命中 ⇒ 符号链接被顺带挡住。
#   ② 跳过 `node_modules` / `.next`（构建产物；`ls-files` 口径本来就不含它们）。
#   ③ **用显式栈，不用递归** —— 符号链接可能成环。堆栈在 `[Collections.Generic.HashSet[string]]`
#      里以 **Ordinal** 记已访问的**规范化绝对路径**去重（PS 的 `@{}` 是**大小写不敏感**的，
#      会把两个不同的目录折成一个 —— 同 `check-numbers.ps1` 里那个 comparer 的理由）。
#      另注：`Get-ChildItem -Recurse` 在 PS 5.1 上**不会**跟着 junction 进死循环（实测），
#      但那是**该 cmdlet 的实现细节**，不该是本判据的隐含前提。
#
# ⚠️ **去重键必须是「解析后的物理目标」，不能是 `Get-Item … .FullName`**（`2026-10-16` 实测踩过）：
# `Get-Item -LiteralPath <junction> -Force` 的 **`.FullName` 返回的是链接路径本身**，不是目标——
# 实测：`<ws>\loop` → `.FullName = <ws>\loop`、`<ws>\loop\loop` → `.FullName = <ws>\loop\loop`……
# ⇒ 去重键**逐层都不同**、`$visited.Add()` **恒为真**、去重一次都没生效 ⇒ **成环时无限展开**。
# **实测后果**（工作区根建 `loop -> 工作区根自身` 的 junction，改前）：`C3 108 → 3456 张表`、
# `C7 5 → 160 个 .ps1`、耗时 `20.0s → 35.1s`，而**挡住它的是 `MAX_PATH`**（一个本脚本从未声明的
# OS 常量）——即"判据没在防，防的是操作系统的巧合"。
# `Resolve-Path` 与 `GetFullPath` **同样不解析** junction（实测，与 `qa-validator` 的建议相反），
# **可用的是 `.Target`**（实测：`Target = <ws>`、`LinkType = Junction`；类型是 `String[]`）。
# 取一个目录的**物理目标**作为去重键（唯一目的：让成环被挡住）。
# 三条分支，按可靠性从高到低：
#   ① **不可见属性优先**：`.LinkType` 在**普通目录**上取不到（PS 5.1 下读它会抛异常），
#      故用 `-is [string]` 判定；是链接 ⇒ 取 `.Target` 的首项。
#   ② 取不到 `.Target` ⇒ 退回**普通目录**（无链接可解析，`.FullName` 就是物理路径）。
#   ③ 返回 `$null` 的三条路，**逐条写明可达性**（`F1-d`：不留一句代码做不到的承诺）：
#      · **可空 `.Target`** ⇒ `$null`。**可达**：`Target` 为空数组 / 空串时。
#      · **相对 `.Target`** ⇒ `$null`。**可达**：`TreeSize` 之类工具建的 junction 存的就是相对路径。
#      · **`GetFullPath` 抛异常**（非法字符 / 超长）⇒ `$null`。**可达，且已实测**（`F1-c` 那一格）。
#      · 非链接时 `$Item.FullName` 为空 ⇒ `$null`：**防御性分支，实测不可达**
#        （`Get-ChildItem` 给的 `DirectoryInfo.FullName` 不会为空）。**如实标注为不可达**，
#        不假装它是判据的一部分——留着只为不漏掉"值为空"这一类的将来回归。
# 调用方一律用 `-not $target` 判定（同时覆盖 `$null` 与 `''`），故"可达与否"不影响正确性。
# ⚠️ **真 symlink 未验证**：`.Target` 的语义是在 **Junction** 上实测的
# （`Target = <ws>`、`LinkType = Junction`、类型 `String[]`）。本机**建不出真 symlink**（需管理员），
# 故「真 symlink 上 `.Target` 同样可用」是**推断，不是实测**——按 `qa-validator` 的建议如实标注。
# 若 `.Target` 为**空**或**相对路径**：一律按 fail-closed 处理（跳过），
# 因为相对路径无法与绝对路径形式的目标比较 ⇒ 当成"工作区外"处理（见下）。
#
# ⚠️ **`[System.IO.Path]::GetFullPath` 必须在 `try` 之内**（`F1-c`）：它会对**非法字符 / 超长路径**
# 抛异常（实测：`C:\bad*name` 这类目标会让它抛）。放在 `try` 之外 = **崩在中途、无 `---- 小结 ----`**，
# 与 `norepo` 那种"响亮失败"不同，那是**半截死掉**。故整段（含 `GetFullPath`）都收在 `try` 里。
function Get-DirTarget {
    param($Item)
    try {
        $t = $null
        if ((Get-Item -LiteralPath $Item.FullName -Force).LinkType -is [string]) {
            # 是链接 ⇒ 目标是**一个具体目录**：取 `.Target` 首项（`.Target` 是 String[]，实测）
            $raw = (Get-Item -LiteralPath $Item.FullName -Force).Target
            if ($raw) { $t = [string](@($raw)[0]) }
            if (-not $t) { return $null }                       # 空目标 ⇒ 不压栈（fail-closed）
            if (-not [System.IO.Path]::IsPathRooted($t)) { return $null }   # 相对 ⇒ 不压栈（同上）
        } else {
            # 不是链接 ⇒ 物理路径就是它自己
            $t = $Item.FullName
            if (-not $t) { return $null }
        }
        return [System.IO.Path]::GetFullPath($t)                 # ← 在 try 内（见上）
    } catch {
        return $null                                             # 解析不了 ⇒ 不压栈（fail-closed）
    }
}

# 去重键的**唯一**口径（`F1-b`）：折小写 + 去尾分隔符 ⇒ 同一个目录恒得同一个键。
# 大小写**故意**折：Windows 路径本身不区分大小写。（容器仍用 Ordinal —— 那是为了**阻止**
# PS `@{}` 的**意外**折叠；与这里的**有意**折叠是两回事，二者不矛盾。）
function ConvertTo-Key {
    param([string]$Path)
    return ([System.IO.Path]::GetFullPath($Path)).TrimEnd('\', '/').ToLowerInvariant()
}

# 目标是否落在工作区根**之内**（含它自身）。用于掐掉 `up → 父目录` 这类**逃逸**（`F1-a`）。
# ⚠️ 比较时两边都折小写 + 去尾分隔符，并在末尾补一个分隔符再比 —— 否则
# `<ws>\foo` 会被误判成在 `<ws2>` 之内（前缀相同但不是一个目录）。
function Test-InWorkspace {
    param([string]$Path)
    $ws = ([System.IO.Path]::GetFullPath($script:RepoRoot)).TrimEnd('\', '/').ToLowerInvariant()
    $p  = ([System.IO.Path]::GetFullPath($Path)).TrimEnd('\', '/').ToLowerInvariant()
    if ($p -eq $ws) { return $true }
    return $p.StartsWith($ws + '\')
}

function Get-RepoFiles {
    param([string]$Pathspec)
    # `-like` 与 `ls-files` 用的是同一套 `*.md` 通配，故 pathspec 原样即可，不发明新语法
    $pattern = $Pathspec

    # G1 注入点（默认不生效，见脚本末的 G1/G2 说明）：把枚举打成**恒返回空集**，
    # 用来复现本次缺陷的形态——「零输入而绿」。这一行**只**由环境变量武装，
    # 不设 `SELFTEST_INJECT` 时它恒为假，正常跑的读数不受任何影响。
    if ($env:SELFTEST_INJECT -eq 'noenum') { return @() }

    # (a) 工作区根自身是仓 —— 原路，读数与改前逐字节一致
    if ($script:GitRepo -and $script:GitRepo -eq $script:RepoRoot) {
        $p = Invoke-GitChecked { git -C $script:GitRepo ls-files $Pathspec 2>$null }
        if ($p.Exit -ne 0) { return @() }
        return @($p.Text -split "`n" | Where-Object { $_ -ne '' })
    }

    # (b) 框架文件不在任何仓里 —— 走文件系统
    $skipDirs = @('node_modules', '.next', '.git')     # 末项兜底：.git 是**文件**时（worktree）按名字挡
    $files = New-Object System.Collections.Generic.List[string]
    $stack = New-Object System.Collections.Generic.Stack[string]
    # ⚠️ **去重键口径只有一处**（`F1-b`）：全部走 `ConvertTo-Key`，**起点也不例外**。
    # 此前起点用 `TrimEnd+ToLowerInvariant`、子项用 `GetPhysicalKey` ⇒ **两套口径**，
    # 起点能匹配上子项只能靠"恰好都对"——那是 `GAP-019` 那一族（两套 comparer 比同一个东西）。
    $visited = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    # ⚠️ 栈统一压**物理路径**（`F1-a` 的修法核心）：键算物理目标、栈却压链接路径 ⇒ **错位**——
    # 于是"已访问"记在物理路径上，而遍历走的是链接路径，子项拿到的路径又不同 ⇒
    # **只有"指回已访问祖先"的环被挡**，「指到附近」的链接（`up → 工作区根的父目录`）**不被拦**。
    # 实测（目标布局）：注入 `up → 父目录` ⇒ `C3 108 → 216 张表`、`C7 5 → 11 个 .ps1`，
    # 且**扫到了工作区外的诱饵文件** ⇒ 分母被污染、扫描范围可逃出工作区。
    # 压物理路径后：子项拿物理路径、`Get-DirTarget` 对普通目录恒等于其物理路径 ⇒
    # **去重对整棵子树成立**，且"同一物理目录只进一次"成为结构性质，不再依赖"恰好指回祖先"。
    $null = $visited.Add((ConvertTo-Key -Path $script:RepoRoot))
    $stack.Push([System.IO.Path]::GetFullPath($script:RepoRoot))    # 起点也压物理路径（workdir 侧）
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        $children = @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue)
        foreach ($c in $children) {
            if ($c.PSIsContainer) {
                if ($skipDirs -contains $c.Name) { continue }
                # ① 凡子目录自身含 `.git` ⇒ 整棵跳过（业务仓根）
                if (Test-Path -LiteralPath (Join-Path $c.FullName '.git')) { continue }
                # ③ 目标 = **解析后的物理目标**（`.FullName` **不**解析链接，用它等于没去重）
                $target = Get-DirTarget -Item $c
                if (-not $target) {
                    # fail-closed：解析不出目标（空 / 相对 / 非法字符 / 超长）⇒ **跳过该目录**（不压栈）。
                    continue
                }
                # ④ **必须落在工作区根之内**（`F1-a` 的第二半）。
                # **权衡（显式）**：跳过 = 少扫（读数偏小）；不跳过 = **逃逸**
                # （分母被污染、扫到工作区外别人的文件夹）。**判断：后者代价更大**——
                # 少扫会让计数**变小**、且有 `C3`/`C6`/`C7` 的「输入非空」前提与列数一致性兜着；
                # 而逃逸是**静默地把别人的文件算成自己的**，读数看着更"饱满"、更难被发现，
                # 且 `Substring($prefixLen)` 在物理目标位于工作区外时会算出**乱码相对路径**。
                # ⇒ 宁可少扫。这也是 `AGENTS.md` §0.0「带项目布局」下"框架规则管框架仓"的同一条边界。
                if (-not (Test-InWorkspace -Path $target)) { continue }
                if ($visited.Add((ConvertTo-Key -Path $target))) { $stack.Push($target) }
                continue
            }
            if ($c.Name -like $pattern) { $files.Add($c.FullName) }
        }
    }
    # 绝对路径 → **相对 `$RepoRoot`**（与 `git ls-files` 的输出形态对齐，见上）
    $prefixLen = $script:RepoRoot.TrimEnd('\', '/').Length + 1
    return @($files | ForEach-Object {
        # 只做**前缀截断**，不做任何分隔符/大小写改写 —— 那会让此分支与 (a) 的输出**不可比**
        ($_ -replace '/', '\').Substring($prefixLen)
    } | Sort-Object)
}

# 「解析不到仓 ⇒ 报错退出」的**唯一**出口。
# ⚠️ **刻意与 `check-progress.ps1` 不同**：那边 `exit 0`（静默），这边**报错 + exit 1**。
# 理由：守卫是 fail-closed 的**阻断件**，「没有候选仓」对它 = 「尚未初始化」，静默是对的
#（`AGENTS.md` §5 首次使用即初始化）。而本脚本是**自测尺子**——它的职责就是回答
#「守卫还有没有牙」。一把**解析不到仓就静默退出的尺子**，与一把**跑完全绿的尺子**在观测上
# 不可区分，而后者正是它要防的病（`GAP-015` 同族）。**自测脚本"静默通过"，正是本次缺陷的形态**。
# 抽成函数是为了让**真实失败**与**注入（G2）**走**逐字相同**的一条路——否则"注入验过了"
# 只证明我另写的那段报错文本会响，证明不了真实分支会响（这两件事在观测上不等价）。
function Fail-NoGitRepo {
    [Console]::Error.WriteLine(
        "守卫自测未运行：在工作区根 $RepoRoot 与其 project/ 子目录中，都没找到能 resolve 的 git 仓。" +
        "自测需要真仓（要取 HEAD / 列分支 / 枚举文件），故本轮【未验证任何东西】——" +
        "这不是「通过」，请不要把它读成通过。")
    exit 1
}

$script:GitRepo = Resolve-GitRepo

# --- G1/G2 · 布局无关性自己的负向证伪（`GAP-029` 的 D3 用例；**由环境变量武装**）
# 为什么它在这里、而不是在 A–F 里：A–F 验的是**两个守卫**，而本次缺陷在**本脚本自己**身上——
# 「修好了」这件事本身也需要一个**能被证伪**的判据。故给它两格，且**故意做成环境变量触发**：
#   默认（变量不设）= **零格**，总格数与会话行为**逐字节不变**（不设变量时这两格根本不进账）。
#   设 `SELFTEST_INJECT=noenum`  → `Get-RepoFiles` **恒返回空集** ⇒ C3/C5/C6/C7 必须 **FAIL**。
#   设 `SELFTEST_INJECT=norepo`  → 「候选解析全不命中」      ⇒ 必须 **报错 + exit 1**。
# 这与 A 组「注入故障 → 期望 FAIL」是同一件事，只是被注入的是**本脚本的接线**。
# ⚠️ **为什么不做成"新开两格常驻"**：那会改变**总格数**，而总格数被 `C6` **机械**守着、
# 又被抄在 8 份文档里 ⇒ 会引发一轮**与缺陷无关**的跨文档改动（D4 要的是同成熟度，不是同步风暴）。
# 判据仍是**可证伪**的：注入即 FAIL、不注入即不计——只是它的"输入非空"由人**显式**给。
# 跑法（两格各一条，读数见第 ④ 段）：
#   $env:SELFTEST_INJECT='noenum'; powershell -NoProfile -File .claude/hooks/self-test.ps1; $env:SELFTEST_INJECT=$null
#   $env:SELFTEST_INJECT='norepo'; powershell -NoProfile -File .claude/hooks/self-test.ps1; $env:SELFTEST_INJECT=$null
if ($env:SELFTEST_INJECT -eq 'norepo') {
    "== G2 · 注入：SELFTEST_INJECT=norepo（把仓库解析打成全不命中）—— 期望【报错 + exit 1】=="
    Fail-NoGitRepo          # 与真实失败同一条出口，不是另写一段文本
}
if (-not $script:GitRepo) { Fail-NoGitRepo }

$script:Pass = 0
$script:Fail = 0

# 「造沙箱的 git 调用失败 ⇒ 报错退出」的唯一出口。
# **不核对退出码 = 在"沙箱不存在"的前提下继续判分**：实测注入 `GIT_DIR` 后 `init` 报 0 却没建仓，
# 后面每一格都是在空目录上跑出来的数（5 格假 FAIL + 1 格假 PASS）。与 G2 同一条道理：
# **造数据失败必须响，不能变成一组看着像结论的数字。**
function Require-SandboxGit {
    param($Result, [string]$What)
    if ($Result.Exit -ne 0) {
        [Console]::Error.WriteLine(
            "守卫自测未运行：造沙箱的 git 调用失败（$What，exit=$($Result.Exit)）。$($Result.Text)")
        exit 1
    }
}

function New-Sandbox {
    param([string]$Tag)
    $d = Join-Path $env:TEMP ('guard-selftest-' + $Tag + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path (Join-Path $d '.claude/hooks') -Force | Out-Null
    # ⚠️ 本函数**自己兜住清理**。真实机制（`2026-10-16` 实测，与直觉相反）：
    # `exit` **会**跑 `finally`（实测：`function T { try { exit 1 } finally { … } }` ⇒ finally 执行），
    # 所以泄漏**不是**"exit 跳过了 finally"，而是 **`New-Sandbox` 被放在调用点的 `try` 之外**
    # （`$sbA = New-Sandbox …` 在 `try {` 上一行）⇒ 在 `New-Sandbox` 内部 abort 时，
    # **调用点的 `finally` 还没建立**，没人清理。实测（abort 路径）：`leftovers AFTER = 1`。
    # ⇒ 修法选「**谁造谁负责**」（不依赖调用点把 `try` 包到哪一行）：清理放进本函数自己的 `finally`。
    # （另一种改法是把三处 `New-Sandbox` 挪进各自 `try`，但那样**每新增一个调用点都要记得**；
    #   本改法在结构上把它变成不可能忘。）
    $ok = $false
    try {
        Copy-Item -LiteralPath $ProgressGuard (Join-Path $d '.claude/hooks/check-progress.ps1')
        Copy-Item -LiteralPath $NumbersGuard  (Join-Path $d '.claude/hooks/check-numbers.ps1')
        # 页名指针（页名的唯一事实源）
        [System.IO.File]::WriteAllText((Join-Path $d '.claude/progress-page.txt'), "project-progress.html`n")
        # 沙箱必须是一个【能取到 HEAD】的真仓 —— 否则走 unborn 静默分支（GAP-012），两格都只剩静默
        # ⚠️ 一律走 `Invoke-GitRepo`（清整族 git 环境变量）并**核对退出码**：
        # 见该函数与 `Require-SandboxGit` 的注释。
        Require-SandboxGit (Invoke-GitRepo { git -C $d init -q }) 'init'
        # ⚠️ **沙箱的分支名必须是 `main`**（`GAP-031`）：`Resolve-Mainline` 的第二级回退是
        # `refs/heads/main`。本机 `init.defaultBranch=master`（**实测**），若不钉死分支名，
        # 所有沙箱都会掉到**第三级回退（HEAD）** ⇒ A 组测到的是**旧语义**，新语义一格没测到。
        # 用 `symbolic-ref HEAD`（而非 `checkout -b`）是为了让**首次提交前**就生效 ——
        # unborn 沙箱（`A6`/`A7`/`A8`）与有提交的沙箱因此走**同一条**解析路径。
        Require-SandboxGit (Invoke-GitRepo { git -C $d symbolic-ref HEAD refs/heads/main }) 'symbolic-ref HEAD refs/heads/main'
        [System.IO.File]::WriteAllText((Join-Path $d 'seed.txt'), "seed`n")
        Require-SandboxGit (Invoke-GitRepo { git -C $d add -A }) 'add'
        Require-SandboxGit (Invoke-GitRepo { git -C $d -c user.email=a@b -c user.name=demo commit -q -m seed }) 'commit'
        $ok = $true
    } finally {
        # 只在**失败**路径清（成功路径由调用点的 `try/finally` 负责，
        # 且 `$KeepSandbox` 时调用点会刻意保留 —— 这里不能替它决定）。
        if (-not $ok) { Remove-Item -Recurse -Force $d -ErrorAction SilentlyContinue }
    }
    return $d
}

function Invoke-Guard {
    param([string]$Script, [string]$Sandbox)
    # ⚠️ 本函数【必须】在作用域内把 EAP 降到 Continue 后再调原生命令。
    # 不加这一句，PS 5.1 会把 powershell.exe 的 stderr 经 2>&1 包成
    # NativeCommandError（ErrorRecord），而脚本级 `$ErrorActionPreference='Stop'`
    # 会把它升格为【终止异常】——于是「守卫报了撞车」反而把自测脚本自己打断。
    # 这正是本仓台账 GAP-013② 同族的坑（作用域 EAP 与「原生命令写 stderr」的交互）；
    # 修法与 `check-progress.ps1` 的 `Invoke-GitChecked` 一致：把 EAP 收进子作用域。
    $raw = & {
        $ErrorActionPreference = 'Continue'
        powershell -NoProfile -ExecutionPolicy Bypass -File $Script 2>&1
    }
    return [pscustomobject]@{
        Exit   = $LASTEXITCODE
        Stdout = ([string]::Join("`n", @($raw))).Trim()
    }
}

function Assert-Cell {
    param([string]$Name, [string]$Expect, $Actual, [scriptblock]$Predicate)
    $ok = & $Predicate
    if ($ok) { $script:Pass++; "  PASS  $Name" }
    else { $script:Fail++; "  FAIL  $Name`n        期望：$Expect`n        实测：$($Actual.Exit) / [$($Actual.Stdout)]" }
}

"守卫自测 · 工作区根 = $RepoRoot"
"守卫 sha256:"
foreach ($g in @($ProgressGuard, $NumbersGuard)) {
    "  $(Split-Path -Leaf $g)  $((Get-FileHash -LiteralPath $g -Algorithm SHA256).Hash.Substring(0,8))…"
}
""

# ================================================================ A · 进度页守卫
# A1 正控（有牙）：页面【存在】且写错 SHA -> 必须 emit decision:block
# A2 对照：页面存在且写对 SHA -> 必须静默（证明它不是只会喊 block）
# A3 负控（已接受代价）：指针指向不存在的页名 -> 静默（GAP-002）
# A4 负控（GAP-025）：<b> 上加一个 class 属性 -> 正则失配 -> 静默放行陈旧页
# A12/A13（GAP-031）：守卫的比对对象是【主干】，不是当前检出的 HEAD。两格的性质见各自注释。
"== A · check-progress.ps1 =="
$sbA = New-Sandbox -Tag 'prog'
try {
    $headProbe = Invoke-GitRepo { git -C $sbA rev-parse --short HEAD }
    Require-SandboxGit $headProbe 'sbA rev-parse --short HEAD'
    $head = $headProbe.Text
    $page = Join-Path $sbA 'project-progress.html'

    # A1
    [System.IO.File]::WriteAllText($page, "<html><body><div>head <b>0000000</b></div></body></html>`n")
    $a1 = Invoke-Guard -Script (Join-Path $sbA '.claude/hooks/check-progress.ps1') -Sandbox $sbA
    Assert-Cell -Name 'A1 正控 页面存在+错SHA → decision:block' -Expect 'stdout 含 {"decision":"block"}' -Actual $a1 `
        -Predicate { $a1.Stdout -match '"decision"\s*:\s*"block"' }

    # A2
    [System.IO.File]::WriteAllText($page, "<html><body><div>head <b>$head</b></div></body></html>`n")
    $a2 = Invoke-Guard -Script (Join-Path $sbA '.claude/hooks/check-progress.ps1') -Sandbox $sbA
    Assert-Cell -Name 'A2 对照 页面存在+SHA一致 → 静默' -Expect 'exit 0 且 stdout 空' -Actual $a2 `
        -Predicate { $a2.Exit -eq 0 -and $a2.Stdout -eq '' }

    # A3
    [System.IO.File]::WriteAllText($page, "<html><body><div>head <b>0000000</b></div></body></html>`n")
    [System.IO.File]::WriteAllText((Join-Path $sbA '.claude/progress-page.txt'), "no-such-page.html`n")
    $a3 = Invoke-Guard -Script (Join-Path $sbA '.claude/hooks/check-progress.ps1') -Sandbox $sbA
    Assert-Cell -Name 'A3 负控 指针指向不存在页名 → 静默（GAP-002 已接受代价）' -Expect 'exit 0 且 stdout 空' -Actual $a3 `
        -Predicate { $a3.Exit -eq 0 -and $a3.Stdout -eq '' }
    [System.IO.File]::WriteAllText((Join-Path $sbA '.claude/progress-page.txt'), "project-progress.html`n")

    # A4 —— GAP-025 的【已修】格：正则改为容忍 <b> 上的属性后，
    # 加一个 class 不应再让它失明。（修复前这一格是静默的。）
    [System.IO.File]::WriteAllText($page, "<html><body><div>head <b class=""v"">0000000</b></div></body></html>`n")
    $a4 = Invoke-Guard -Script (Join-Path $sbA '.claude/hooks/check-progress.ps1') -Sandbox $sbA
    Assert-Cell -Name 'A4 <b> 加 class 属性 → 仍 block（GAP-025 已修此格）' -Expect 'stdout 含 {"decision":"block"}' -Actual $a4 `
        -Predicate { $a4.Stdout -match '"decision"\s*:\s*"block"' }

    # A5 —— GAP-025 的【残余】格，**故意断言"静默"**：把标记重构成 <span> 后守卫仍失明。
    # 这一格的作用不是"验通过"，而是【把残余钉住】：只要它还静默，GAP-025 就没关；
    # 哪天有人把守卫改成不解析展示层，这一格会开始 FAIL —— 那正是需要更新台账的信号。
    [System.IO.File]::WriteAllText($page, "<html><body><div>head <span>0000000</span></div></body></html>`n")
    $a5 = Invoke-Guard -Script (Join-Path $sbA '.claude/hooks/check-progress.ps1') -Sandbox $sbA
    Assert-Cell -Name 'A5 重构成 <span> → 仍静默（GAP-025 残余，故意断言）' -Expect 'exit 0 且 stdout 空' -Actual $a5 `
        -Predicate { $a5.Exit -eq 0 -and $a5.Stdout -eq '' }

    # --- A12/A13 · GAP-031：比对【主干】而非【当前检出的 HEAD】
    # 缺陷形态（issue #36）：守卫取 `rev-parse --short HEAD`，于是在任何特性分支上
    #   · 页面记主干 SHA（**正确**，干系人要看主线事实） ⇒ 守卫**误报「落后」**；
    #   · 页面改记分支 SHA ⇒ 一合并/变基就失效，且那不是给干系人看的事实。
    # 两格分别钉住「不该报的不报」与「该报的照报」：
    #   A12 = 特性分支 + 页面=主干 ⇒ **必须静默**（改前：只要主干与分支 tips 不同就**误报 block**）
    #   A13 = 页面写一个**能解析、但不在主干上**的提交 ⇒ **必须 block**（改前：在分支上**静默**，
    #         因为"当前检出的 HEAD"恰好就是它）⇒ A13 是**真回归护栏**：它防的是"退化成只查 HEAD"。
    # A12 的前条件必须自证：`probe` 的 HEAD 必须**等于**主干，否则这一格测的不是它声称要测的东西。
    # ⚠️ **与 A6/A9 的差异（显式）**：那两格把前条件算作**独立的格**；这里把它**折进本格的谓词**——
    # 因为 `GAP-031` 的交付口径钉死「新增**两格**」（总格数 38 → 40，见台账与 8 份文档）。
    # 代价：前条件不成立时本格同样 FAIL，只是失败原因要在「实测」两个数里读 —— 可接受。
    Require-SandboxGit (Invoke-GitRepo { git -C $sbA checkout -q -b probe }) 'sbA checkout -b probe'
    $mainlineProbe = Resolve-Mainline $sbA
    if (-not $mainlineProbe) {
        [Console]::Error.WriteLine("守卫自测未运行：A12/A13 在沙箱 $sbA 解析不到主干（GAP-031 的前提不成立）。")
        exit 1
    }
    $forkPoint = Invoke-GitRepo { git -C $sbA rev-parse --verify --quiet "$($mainlineProbe.Ref)^{commit}" }
    $probeFork = Invoke-GitRepo { git -C $sbA rev-parse --verify --quiet 'HEAD^{commit}' }
    Require-SandboxGit $forkPoint 'sbA mainline rev-parse（fork 点）'
    Require-SandboxGit $probeFork 'sbA probe HEAD rev-parse（fork 点）'
    $branchIsClean = ($probeFork.Text -eq $forkPoint.Text)

    # ⚠️ **A12 必须是"主干已推进、分支未提交"**（`2026-10-17` 打桩实测后修正，如实记）：
    # 第一版只做 `checkout -b probe`，主干与分支**仍逐字相同** ⇒ 把守卫打桩回 `HEAD` 之后
    # **A12 照样 PASS** ⇒ **这一格对"修复被撤掉"不敏感、塌成死代码**。这正是 issue #36 的「最强注入」
    # 没被覆盖的那一半：**分支自己没有提交，骗不到"比 HEAD"的守卫；只有主干往前走了才骗得到。**
    # 故：切回 `main` 补一次提交（分支仍在旧提交上），再切回 `probe`，页面记**主干的新 SHA**。
    Require-SandboxGit (Invoke-GitRepo { git -C $sbA checkout -q main }) 'sbA checkout main（推进主干）'
    [System.IO.File]::WriteAllText((Join-Path $sbA 'trunk-move.txt'), "trunk`n")
    Require-SandboxGit (Invoke-GitRepo { git -C $sbA add -A }) 'sbA add (trunk)'
    Require-SandboxGit (Invoke-GitRepo { git -C $sbA -c user.email=a@b -c user.name=demo commit -q -m 'trunk moves on' }) 'sbA commit (trunk)'
    $mainAfter = Invoke-GitRepo { git -C $sbA rev-parse --verify --quiet "$($mainlineProbe.Ref)^{commit}" }
    Require-SandboxGit $mainAfter 'sbA mainline rev-parse（推进后）'
    Require-SandboxGit (Invoke-GitRepo { git -C $sbA checkout -q probe }) 'sbA checkout probe（回到分支；它仍停在 fork 点）'
    $probeNow = Invoke-GitRepo { git -C $sbA rev-parse --verify --quiet 'HEAD^{commit}' }
    Require-SandboxGit $probeNow 'sbA probe HEAD rev-parse（推进后）'
    $sbMainSha = $mainAfter.Text.Substring(0, 7)

    # A12：分支**零提交**、主干**已推进**、页面记主干新 SHA ⇒ 必须静默。
    # 谓词四段缺一不可：① 分支确实在 fork 点（零提交）· ② 主干确实动了 · ③ exit 0 · ④ stdout 空。
    # ② 保证这一格**能区分**"比主干"与"比 HEAD"——缺了它，两版都会静默（已实测）。
    [System.IO.File]::WriteAllText($page, "<html><body><div>head <b>$sbMainSha</b></div></body></html>`n")
    $a12 = Invoke-Guard -Script (Join-Path $sbA '.claude/hooks/check-progress.ps1') -Sandbox $sbA
    Assert-Cell -Name "A12 GAP-031 分支零提交 + 主干推进，页面记主干 → 静默（改前：误报 block）" -Expect 'exit 0 且 stdout 空' -Actual $a12 `
        -Predicate { $branchIsClean -and ($mainAfter.Text -ne $forkPoint.Text) -and $a12.Exit -eq 0 -and $a12.Stdout -eq '' }

    # A13：在 probe 上提交一次 —— 该提交**能解析、但不在主干上**；页面写它 ⇒ 必须 block
    # （主干此刻已在别处 ⇒ 这一格的 block 只可能来自"比的是主干"，不可能来自"分支 tip 变了"。）
    [System.IO.File]::WriteAllText((Join-Path $sbA 'probe.txt'), "probe`n")
    Require-SandboxGit (Invoke-GitRepo { git -C $sbA add -A }) 'sbA add (probe)'
    Require-SandboxGit (Invoke-GitRepo { git -C $sbA -c user.email=a@b -c user.name=demo commit -q -m 'probe work' }) 'sbA commit (probe)'
    $probeTipProbe = Invoke-GitRepo { git -C $sbA rev-parse --verify --quiet 'HEAD^{commit}' }
    Require-SandboxGit $probeTipProbe 'sbA probe tip rev-parse'
    $probeTip = $probeTipProbe.Text
    [System.IO.File]::WriteAllText($page, "<html><body><div>head <b>$($probeTip.Substring(0,7))</b></div></body></html>`n")
    $a13 = Invoke-Guard -Script (Join-Path $sbA '.claude/hooks/check-progress.ps1') -Sandbox $sbA
    # 谓词三段缺一不可：① 前条件（分支 tip **不在**主干上，否则与"一致"同义）· ② 确实 block ·
    # ③ reason 里**点名了主干**（否则读者仍分不清比的是哪条线）。
    Assert-Cell -Name 'A13 GAP-031 页面记「能解析但不在主干上」的提交 → block（改前：在分支上静默）' -Expect 'stdout 含 {"decision":"block"} 且 reason 点名主干' `
        -Actual $a13 -Predicate { $probeTip -ne $mainAfter.Text -and $a13.Stdout -match '"decision"\s*:\s*"block"' -and $a13.Stdout -match '落后于主干' }
    # 收尾刻意**不切回主干**：A13 把页面文件提交进了 `probe`（`git add -A`），切回 `main` 会因
    # 该文件在两侧不同而被 git 拒绝（实测 `exit=1`）——而 `sbA` 本就在 `finally` 里整个删掉，
    # 没有任何后续格依赖它的分支状态。（写下来是为了下一个人不会"顺手补一行 checkout"。）
}
finally { if (-not $KeepSandbox) { Remove-Item -Recurse -Force $sbA -ErrorAction SilentlyContinue } }
""

# ================================================================ A6-A8 · unborn 仓（GAP-012）
# 【这两格断言的是"静默是对的"，不是一个待修的行为】——故附对照格，证明该静默是【分支特定】
# 而非死代码。
#
# 为什么维持静默（2026-10-14 读代码后判定，【与台账 GAP-012 原写的解除条件相反】）：
#   ① unborn 仓【没有 HEAD】⇒ 页面无法"落后"一个不存在的 HEAD ⇒【根本没有判据】。
#      通知它 = 通知"判据不存在"——而那正是指针异常通道的职责，在此处价值更低。
#   ② 代价落在最坏位置：新用户从零建仓时，页面尚未存在且无提交；若 unborn 变成通知，
#      他们会在【第一次提交之前的每一轮】收到警告 —— 恰在入门时刻制造噪声。
#   ③ 该状态是【过渡性且自愈】的：首次提交即消失。
# ⇒ 台账原写的解除条件「显式识别 unborn 并 emit 提示而非静默」【提错了】；已在台账留痕更正。
# 但仍【缺负向验证】（D3 要求）—— 这三格就是补它。
$sbU = Join-Path $env:TEMP ('unborn-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
try {
    New-Item -ItemType Directory -Path (Join-Path $sbU '.claude/hooks') -Force | Out-Null
    Copy-Item -LiteralPath $ProgressGuard (Join-Path $sbU '.claude/hooks/check-progress.ps1')
    [System.IO.File]::WriteAllText((Join-Path $sbU '.claude/progress-page.txt'), "project-progress.html`n")
    # ⚠️ 走 `Invoke-GitRepo`（清 `GIT_DIR`）**并核对退出码**。不核对的后果实测过两重：
    # ① 注入 `GIT_DIR` 时 `init` 报 0 却没建仓 ⇒ 沙箱**不存在**；
    # ② 沙箱不存在时 `rev-parse` 被劫持，返回值是 `Object[]`（SHA + `$LASTEXITCODE`），
    #    而下面的谓词 `-ne 0` **对数组恒为真** ⇒ `A6`「沙箱确实 unborn」**假通过**
    #    （它测的其实不是它声称要测的东西）。故前置条件必须**先**确认沙箱真建起来了。
    Require-SandboxGit (Invoke-GitRepo { git -C $sbU init -q }) 'sbU init（只 init，不 commit）'
    # ⚠️ 与 `New-Sandbox` 同一条理由（`GAP-031`）：钉死分支名为 `main`，否则 `A8`
    # 测到的是第三级回退（HEAD），而**不是**新语义的第二级（本地 `main`）。
    # 放在**首次提交之前** ⇒ unborn 与有提交两种状态走同一条解析路径。
    Require-SandboxGit (Invoke-GitRepo { git -C $sbU symbolic-ref HEAD refs/heads/main }) 'sbU symbolic-ref HEAD refs/heads/main'
    Require-SandboxGit (Invoke-GitRepo { git -C $sbU rev-parse --git-dir }) 'sbU 确实是个仓（前置条件）'

    # A6 前条件：必须【真的】是 unborn，否则这一格测的不是它声称要测的东西
    # ⚠️ 必须把 EAP 收进子作用域：unborn 下 git 把 `fatal: Needed a single revision`
    # 写进 stderr，而脚本级 EAP=Stop 会把它升格为【终止异常】，把自测自己打断。
    # 这正是本仓已记过两次的坑（GAP-013② / 本文件 Invoke-Guard 的注释）——
    # 直接调 git 而不走 Invoke-Guard，就会复现它。
    # ⚠️ 取 `.Exit`（**标量**）而非把 `$LASTEXITCODE` 混进返回值：见上 ②，数组会让谓词恒真。
    $unbornExit = (Invoke-GitRepo { git -C $sbU rev-parse --short HEAD 2>$null }).Exit
    Assert-Cell -Name 'A6 前条件 沙箱确实 unborn（rev-parse --short HEAD 非 0）' -Expect 'exit != 0' `
        -Actual ([pscustomobject]@{ Exit = $unbornExit; Stdout = '' }) -Predicate { $unbornExit -ne 0 }

    # A7 页面【存在】且写错 SHA —— 在 unborn 下仍须静默（维持；理由见上）
    [System.IO.File]::WriteAllText((Join-Path $sbU 'project-progress.html'), "<html><body><div>head <b>0000000</b></div></body></html>`n")
    $a6 = Invoke-Guard -Script (Join-Path $sbU '.claude/hooks/check-progress.ps1') -Sandbox $sbU
    Assert-Cell -Name 'A7 unborn 仓 + 页面存在且写错 SHA → 静默（GAP-012 维持）' -Expect 'exit 0 且 stdout 空' `
        -Actual $a6 -Predicate { $a6.Exit -eq 0 -and $a6.Stdout -eq '' }

    # A8 对照：同一沙箱补一次提交后，同页同错 SHA 必须 block
    # ⇒ 证明 A7 的静默是【分支特定】，不是"守卫已死"
    Require-SandboxGit (Invoke-GitRepo { git -C $sbU add -A }) 'sbU add'
    Require-SandboxGit (Invoke-GitRepo { git -C $sbU -c user.email=a@b -c user.name=demo commit -q -m seed }) 'sbU commit'
    $a7 = Invoke-Guard -Script (Join-Path $sbU '.claude/hooks/check-progress.ps1') -Sandbox $sbU
    Assert-Cell -Name 'A8 对照 同一沙箱补一次提交后 → 必须 block（证明 A7 是分支特定）' -Expect 'stdout 含 {"decision":"block"}' `
        -Actual $a7 -Predicate { $a7.Stdout -match '"decision"\s*:\s*"block"' }
    # --- A9/A10 · GAP-013①：GIT_DIR 劫持（2026-10-14 实测并修复）
    # 现象（修复前实测）：设 `GIT_DIR` 指向【另一个仓】，守卫会去读那个仓的 HEAD。
    # 若其 HEAD 恰好与页面一致 → exit 0 【静默放行】一个陈旧页。
    # 机制：`git -C <repo>` 指定工作目录，但 `GIT_DIR` 覆盖仓库发现 —— 两者不是一回事。
    # 修法：`Invoke-GitChecked` 在调用前把 `GIT_DIR` 置空、调用后还原（`$env:` 是进程级，
    # 故须 save/restore）。该 helper 是两个守卫的【唯一】git 入口，所以一处即覆盖全部。
    # ⚠️ 这里取的是**框架仓**的 HEAD，故必须走 `$GitRepo`（仓库根）而非 `$RepoRoot`（工作区根）：
    # 目标布局下工作区根**不是**仓，`git -C` 会直接失败 —— 而那正是本脚本此前的崩溃点。
    $repoHeadProbe = Invoke-GitChecked { git -C $script:GitRepo rev-parse --short HEAD 2>$null }
    if ($repoHeadProbe.Exit -ne 0 -or -not $repoHeadProbe.Text) {
        # 走到这里说明仓能 resolve 却取不到 HEAD（unborn / 异常）—— **不得**留空往下走：
        # 空的 `$repoHeadNow` 会让 A9 塌成 `'' -ne <沙箱HEAD>` = 恒真（假绿），
        # 并让 A10/A11 的页面写出 `<b></b>` ⇒ 守卫走「找不到 SHA 标记」的**静默分支** ⇒ 两格也假绿。
        # 这正是本脚本要防的「输入塌成空而绿」，故**明确报错 + 非零退出**。
        [Console]::Error.WriteLine("守卫自测未运行：在 $GitRepo 取不到 HEAD（仓存在但无 HEAD？）。A9/A10/A11 三格无输入，不得当作通过。")
        exit 1
    }
    $repoHeadNow = $repoHeadProbe.Text
    $sbHeadProbe = Invoke-GitRepo { git -C $sbU rev-parse --short HEAD }
    Require-SandboxGit $sbHeadProbe 'sbU rev-parse --short HEAD'
    $sbHeadNow = $sbHeadProbe.Text
    Assert-Cell -Name 'A9 前条件 沙箱 HEAD 与框架仓 HEAD 不同（否则本格无意义）' -Expect '两者不同' `
        -Actual ([pscustomobject]@{ Exit = $sbHeadNow; Stdout = $repoHeadNow }) -Predicate { $sbHeadNow -ne $repoHeadNow }


    # 页面写【框架仓】的 HEAD —— 对沙箱而言是陈旧的 ⇒ 必须 block
    [System.IO.File]::WriteAllText((Join-Path $sbU 'project-progress.html'), "<html><body><div>head <b>$repoHeadNow</b></div></body></html>`n")

    $t9 = & { $ErrorActionPreference='Continue'; $env:GIT_DIR=$null; powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $sbU '.claude/hooks/check-progress.ps1') 2>&1 }
    $s9 = [string]::Join("`n", @($t9)).Trim()
    Assert-Cell -Name 'A10 对照 无 GIT_DIR → block（正控）' -Expect 'stdout 含 {"decision":"block"}' `
        -Actual ([pscustomobject]@{ Exit = 0; Stdout = $s9 }) -Predicate { $s9 -match '"decision"\s*:\s*"block"' }

    # A11 —— GIT_DIR 及【同族环境变量】皆不得改变读数。
    # 2026-10-14 实测：只有 GIT_DIR 会劫持（其余四个【不】劫持）。但判据仍覆盖全族 ——
    # 因为"哪个会劫持"是 git 的实现细节，不该由人记得；判据只该是"没有一个能改变读数"。
    # （`Invoke-GitChecked` 只清 GIT_DIR；其余四个实测无害，故此格是对该取舍的【持续验证】，
    #   而非重复。哪天 git 改了语义，这一格会开始 FAIL。）
    # 合并为【一次】spawn（逐个 spawn 要 5 次 powershell.exe 启动，实测显著抬升整轮耗时）。
    # 判据仍是"没有一个能改变读数"—— 两者皆设时若任一劫持，读数一样会失真（静默），本格照样 FAIL。
    # ⚠️ 取值必须【逐个按语义设】—— 2026-10-14 实测踩过：把五个变量【全设成同一个值】
    # 时该组合【不劫持】，于是这一格对"修复被撤掉"不敏感、塌成死代码（注入验证时抓到的）。
    # 下面这组值是【实测定为会劫持】的那组（GIT_WORK_TREE 指工作树根、GIT_OBJECT_DIRECTORY
    # 指 objects 目录），故它能真正验到"清环境"这一步。
    # ⚠️ **`GIT_INDEX_FILE` 指向仓库 index 是「写坏」而非「读错」，且 `2026-10-16` 实测过**：
    # 不清它时，沙箱的 `git add` 会**覆盖一个无关仓的 index**（`5B00A626 → 45A64801`，
    # 该仓此后 `git status` 报 `fatal: unable to read …`）。故它必须在这组值里。
    # ⚠️ **清单与清空点共用 `$GitEnvFamily`**（D4：同一份事实不做两处）——
    # 两处各写一份时，下次新增一个变量必然只改一处（本缺陷就是这么来的：清空点只清了 1 个）。
    # `GIT_ALTERNATE_OBJECT_DIRECTORIES` / `GIT_CEILING_DIRECTORIES` / `GIT_NAMESPACE` / `GIT_PREFIX`
    # **未经逐变量实测**（`2026-10-14` 只测过族里前四个，`GIT_INDEX_FILE` 于 `2026-10-16` 实测会写坏别仓），
    # 但仍**一并注入**：判据只该是「**没有一个能改变读数**」，而不是由人记得"哪个会劫持"。
    # 它们同时也在 `$GitEnvFamily` 里（清空侧），故这一组是对清空的**全族持续验证**。
    $envMap = [ordered]@{
        'GIT_DIR'              = $script:GitRepo   # 指向一个**看起来很像仓**的目录（真实仓库根）
        'GIT_WORK_TREE'        = $GitRepo
        'GIT_OBJECT_DIRECTORY' = (Join-Path $GitRepo '.git/objects')
        'GIT_COMMON_DIR'       = (Join-Path $GitRepo '.git')
        'GIT_INDEX_FILE'       = (Join-Path $GitRepo '.git/index')
        'GIT_ALTERNATE_OBJECT_DIRECTORIES' = (Join-Path $GitRepo '.git/objects')
        'GIT_CEILING_DIRECTORIES'          = (Split-Path -Parent $GitRepo)
        'GIT_NAMESPACE'                    = 'selftest-inject'
        'GIT_PREFIX'                       = 'selftest/'
    }
    $savedEV = @{}
    foreach ($ev in $envMap.Keys) {
        $savedEV[$ev] = [Environment]::GetEnvironmentVariable($ev)
        [Environment]::SetEnvironmentVariable($ev, $envMap[$ev])
    }
    try {
        $probe = & { $ErrorActionPreference='Continue'; powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $sbU '.claude/hooks/check-progress.ps1') 2>&1 }
        $sFam = [string]::Join("`n", @($probe)).Trim()
    } finally {
        foreach ($ev in $envMap.Keys) { [Environment]::SetEnvironmentVariable($ev, $savedEV[$ev]) }
    }
    Assert-Cell -Name "A11 同族 git 环境变量（$($envMap.Count) 个）皆不得改变读数（单次 spawn）" -Expect 'stdout 含 {"decision":"block"}' `
        -Actual ([pscustomobject]@{ Exit = 0; Stdout = $sFam }) -Predicate { $sFam -match '"decision"\s*:\s*"block"' }
}
finally { if (-not $KeepSandbox) { Remove-Item -Recurse -Force $sbU -ErrorAction SilentlyContinue } }
""

# ================================================================ B · 编号守卫
# B1 正控（有牙）：两条分支各有同号不同文件 -> exit 1 且 stderr 报撞车
# B2 对照：只有一个 docs/changes/ 条目、无跨分支同号 -> exit 1 且 stderr 报
#          「未检查编号撞车」？不——那条是【无法枚举】的通道。
#          本仓形态是「0 候选仓」：docs/changes/ 不存在于任何 ref -> exit 0 静默。
"== B · check-numbers.ps1 =="
$sbB = New-Sandbox -Tag 'nums'
try {
    $gB = Join-Path $sbB '.claude/hooks/check-numbers.ps1'

    # B1 正控：造跨分支同号撞车
    # ⚠️ 全部走 `Invoke-GitRepo` + 核对退出码（同 New-Sandbox 的理由）。本格尤其经不起"沙箱没建起来"：
    # `checkout -b` 失败会让**两条分支其实是同一条**，于是「跨分支同号」这个前提直接不成立——
    # 而守卫仍会照常给出一个读数，那一格就成了**在错的前提上判分**。
    New-Item -ItemType Directory -Path (Join-Path $sbB 'docs/changes') -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $sbB 'docs/changes/023-alpha.md'), "alpha`n")
    Require-SandboxGit (Invoke-GitRepo { git -C $sbB add -A }) 'sbB add (a)'
    Require-SandboxGit (Invoke-GitRepo { git -C $sbB -c user.email=a@b -c user.name=demo commit -q -m 'a: 023-alpha' }) 'sbB commit (a)'
    Require-SandboxGit (Invoke-GitRepo { git -C $sbB checkout -q -b feat-b }) 'sbB checkout -b feat-b'
    Remove-Item -LiteralPath (Join-Path $sbB 'docs/changes/023-alpha.md') -Force
    [System.IO.File]::WriteAllText((Join-Path $sbB 'docs/changes/023-beta.md'), "beta`n")
    Require-SandboxGit (Invoke-GitRepo { git -C $sbB add -A }) 'sbB add (b)'
    Require-SandboxGit (Invoke-GitRepo { git -C $sbB -c user.email=a@b -c user.name=demo commit -q -m 'b: 023-beta' }) 'sbB commit (b)'
    # 切回默认分支：`master` 是旧 git、`main` 是新 git —— 两个名字都要试，
    # 且**新写法不留 `$LASTEXITCODE` 混进返回值**（那是本文件 A6 假通过的同族错法）。
    $back = Invoke-GitRepo { git -C $sbB checkout -q master 2>$null }
    if ($back.Exit -ne 0) { Require-SandboxGit (Invoke-GitRepo { git -C $sbB checkout -q main }) 'sbB checkout main' }
    # 前提自证：两条分支必须真的都在（否则本格测的不是「跨分支」）
    $refs = Invoke-GitRepo { git -C $sbB for-each-ref --format='%(refname:short)' refs/heads }
    Require-SandboxGit $refs 'sbB for-each-ref'
    if (@($refs.Text -split "`n" | Where-Object { $_ -ne '' }).Count -lt 2) {
        [Console]::Error.WriteLine("守卫自测未运行：B1 需要两条分支才有意义，实测只有 [$($refs.Text)]。")
        exit 1
    }

    $b1 = Invoke-Guard -Script $gB -Sandbox $sbB
    Assert-Cell -Name 'B1 正控 跨分支同号不同文件 → exit 1 + 报撞车' -Expect 'exit 1 且 stdout 含「撞车」' -Actual $b1 `
        -Predicate { $b1.Exit -eq 1 -and $b1.Stdout -match '撞车' }
}
finally { if (-not $KeepSandbox) { Remove-Item -Recurse -Force $sbB -ErrorAction SilentlyContinue } }

$sbC = New-Sandbox -Tag 'nocand'
try {
    # B2 对照：任何 ref 都没有 docs/changes/ -> 0 候选仓 -> exit 0 静默
    $b2 = Invoke-Guard -Script (Join-Path $sbC '.claude/hooks/check-numbers.ps1') -Sandbox $sbC
    Assert-Cell -Name 'B2 对照 无 docs/changes/（0 候选仓）→ 静默' -Expect 'exit 0 且 stdout 空' -Actual $b2 `
        -Predicate { $b2.Exit -eq 0 -and $b2.Stdout -eq '' }
}
finally { if (-not $KeepSandbox) { Remove-Item -Recurse -Force $sbC -ErrorAction SilentlyContinue } }
""

# ================================================================ C · 规则—判据之间的机械检查
# 这四格补的是台账 GAP-017 同族里【可机械检出】的四名。它们不起沙箱，直接查工作区。
# 之所以放这里而不是新开脚本：它们与 A/B 同属「D3 负向用例先行」这一件事——
# 判据的牙要有人定期去咬，规则的投影也要有人定期去对。
"== C · 规则投影的机械检查（GAP-017 同族）=="

function Get-BilingualPairs {
    return @(
        [pscustomobject]@{ Zh = 'AGENTS.md'; En = 'AGENTS.en.md'; Name = 'AGENTS' },
        [pscustomobject]@{ Zh = 'README.md'; En = 'README.en.md'; Name = 'README' },
        # `2026-10-25` 补（issue #55）：接入引导也是【双语成对】分发的，且它承载§0.0 的
        # 「先问位置、再接入」流程 —— 与 AGENTS / README 同属"两份读者各读一份"的载体。
        [pscustomobject]@{ Zh = 'ONBOARDING.md'; En = 'ONBOARDING.en.md'; Name = 'ONBOARDING' }
    )
}

# --- C1 · 双语章节结构（GAP-022 的判据）
# 单测这一格【不充分】：它只证明「节的数目与层级对上了」，证明不了「内容等价」。
# 故 C2 必须一起跑 —— 这与 A1/A2 是同一个道理（结构绿 ≠ 内容绿）。
foreach ($p in Get-BilingualPairs) {
    $zhFile = Join-Path $RepoRoot $p.Zh
    $enFile = Join-Path $RepoRoot $p.En
    if (-not (Test-Path -LiteralPath $zhFile) -or -not (Test-Path -LiteralPath $enFile)) {
        $script:Fail++; "  FAIL  C1 $($p.Name) 双语文件缺失"
        continue
    }
    $zh = @(Select-String -LiteralPath $zhFile -Pattern '^#{2,3} ').Count
    $en = @(Select-String -LiteralPath $enFile -Pattern '^#{2,3} ').Count
    Assert-Cell -Name "C1 $($p.Name) 双语章节数相等（zh=$zh en=$en）" -Expect '两数相等' -Actual ([pscustomobject]@{ Exit = $zh; Stdout = $en }) `
        -Predicate { $zh -eq $en }
}

# --- C2 · 判据词双语锚点（F7 建议的最小内容判据）
# 为什么必须有它：C1 全绿时，把英文版 all three must hold 改成 any one may hold、
# 并整条删掉硬边界③，C1 照样全绿（已实测）。**结构判据测不出语义反转。**
# 本格检查几条【承载硬约束】的判据词在中英两侧各自在场。
# ⚠️ 它只判【在场】，不判【次数相等】——两侧提及次数可以不同（英文可能换一种措辞说到同一件事）。
#    这条限制是显式的：它把盲区从「任意语义反转」收窄到「判据词整体消失」，**不等于内容等价**。
$anchors = @(
    [pscustomobject]@{ Zh = 'AGENTS.md'; ZhWord = '三条同时成立';   En = 'AGENTS.en.md'; EnWord = 'all three must hold' },
    [pscustomobject]@{ Zh = 'AGENTS.md'; ZhWord = '不构成豁免';     En = 'AGENTS.en.md'; EnWord = 'Not an exemption' },
    [pscustomobject]@{ Zh = 'AGENTS.md'; ZhWord = '历史快照不改写'; En = 'AGENTS.en.md'; EnWord = 'historical snapshots are not rewritten' },
    [pscustomobject]@{ Zh = 'AGENTS.md'; ZhWord = '任务定位协议';   En = 'AGENTS.en.md'; EnWord = 'Task-location protocol' }
    [pscustomobject]@{ Zh = 'AGENTS.md'; ZhWord = '决策提醒义务';   En = 'AGENTS.en.md'; EnWord = 'Decision-reminder duty' }
    [pscustomobject]@{ Zh = 'AGENTS.md'; ZhWord = '询问项目位置';   En = 'AGENTS.en.md'; EnWord = 'ask the user where the project is' }
    [pscustomobject]@{ Zh = 'AGENTS.md'; ZhWord = '落 ADR';         En = 'AGENTS.en.md'; EnWord = 'land the ADR' }
    [pscustomobject]@{ Zh = 'AGENTS.md'; ZhWord = '输入通道';       En = 'AGENTS.en.md'; EnWord = 'channel for user intent' }
    [pscustomobject]@{ Zh = 'AGENTS.md'; ZhWord = '可复用 ≠ 可携带'; En = 'AGENTS.en.md'; EnWord = 'Reusable ≠ portable' }
    # `2026-10-25` 补（issue #55）：接入流程的两条硬约束。C1 只能证明"章节数相等"，
    # 证明不了"§0.0 的『接入确认』与『现状基线』这两步还在"——语义被整条删掉时 C1 照样全绿。
    [pscustomobject]@{ Zh = 'AGENTS.md'; ZhWord = '接入确认';       En = 'AGENTS.en.md'; EnWord = 'attach check' }
    [pscustomobject]@{ Zh = 'AGENTS.md'; ZhWord = '现状基线';       En = 'AGENTS.en.md'; EnWord = 'status baseline' }
)
foreach ($a in $anchors) {
    $zc = @(Select-String -LiteralPath (Join-Path $RepoRoot $a.Zh) -Pattern ([regex]::Escape($a.ZhWord)) -AllMatches).Count
    $ec = @(Select-String -LiteralPath (Join-Path $RepoRoot $a.En) -Pattern ([regex]::Escape($a.EnWord)) -AllMatches).Count
    Assert-Cell -Name "C2 判据词双语在场：「$($a.ZhWord)」/「$($a.EnWord)」（$zc/$ec）" -Expect '两侧均 >0' `
        -Actual ([pscustomobject]@{ Exit = $zc; Stdout = $ec }) -Predicate { $zc -gt 0 -and $ec -gt 0 }
}

# --- C3 · Markdown 表格列数一致（GAP-017 同族第 ③ 名）
# 为什么要有它：表格是规则的载体。删掉行首一个 `| ` 会让三列塌成两列，
# 渲染时「判据」列被吞进「分路」列 —— 规则静默变形，两条 Stop 钩子均静默（已实测）。
# 数法：把 \| （转义管道）先换成占位符，再按 | 切。
#
# ⚠️ 枚举**必须**走 `Get-RepoFiles`（布局无关），不能写 `git -C <repo> ls-files`：
# 目标布局下框架文件**不在任何仓里**，`ls-files` 直接返回空 ⇒ 本格的输入**结构性塌成 0**，
# 而「0 张表」当时**照样 PASS**——**与死代码同形**（实测：`0 张表` PASS ↔ 本仓 `108 张表` PASS）。
# 故本格有**两个前提**，缺一不可：① 输入非空（下面谓词里的 `$tableCount -gt 0`）；
# ② 列数一致。只查 ② 是本格过去的形态。
$tableFiles = @(Get-RepoFiles '*.md')
$tableCount = 0; $tableBad = @()
foreach ($f in $tableFiles) {
    $fp = Join-Path $RepoRoot $f
    if (-not (Test-Path -LiteralPath $fp)) { continue }
    $lines = [System.IO.File]::ReadAllLines($fp)
    $inTable = $false; $expCols = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = $lines[$i].Trim()
        if ($l -match '^\|') {
            $s = $l -replace '\\\|', '@ESC@'
            $cells = ($s -split '\|').Count - 2
            # ⚠️ 用 $expCols 而非 $expect —— `$Expect` 是 Assert-Cell 的参数名，
            # 二者【仅靠大小写区分】，属 PowerShell 大小写不敏感下的静默别名风险（见 C7）。
            if (-not $inTable) { $inTable = $true; $expCols = $cells; $tableCount++ }
            elseif ($cells -ne $expCols) { $tableBad += "$f`:$($i+1) 列数=$cells 期望=$expCols" }
        } else { $inTable = $false }
    }
}
Assert-Cell -Name "C3 Markdown 表格列数一致（$tableCount 张表）" -Expect '异常行 = 0 且表数 > 0' `
    -Actual ([pscustomobject]@{ Exit = $tableBad.Count; Stdout = ($tableBad -join '; ') }) `
    -Predicate { $tableBad.Count -eq 0 -and $tableCount -gt 0 }

# --- C4 · git grep 的 -E 与 \| 同现（GAP-017 同族第 ⑤ 名）
# -E 是 ERE，其中 \| 是【字面竖线】而非【或】 ⇒ 命令照抄跑出 0 行，而记录声称有命中。
# 它不报错，只返回空。
# 豁免：行内含 `grep-pipe-trap: 引用反例` 标记的，是【刻意展示的错误示例】，不算误用。
$grepBad = @()
foreach ($f in $tableFiles) {
    $fp = Join-Path $RepoRoot $f
    if (-not (Test-Path -LiteralPath $fp)) { continue }
    $lines = [System.IO.File]::ReadAllLines($fp)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        if ($l -match 'grep-pipe-trap') { continue }
        foreach ($m in [regex]::Matches($l, 'git\s+grep[^\x60]*')) {
            if ($m.Value -match '\-[a-zA-Z]*E' -and $m.Value -match '\\\|') {
                $grepBad += "$f`:$($i+1)  $($m.Value.Trim())"
            }
        }
    }
}
Assert-Cell -Name 'C4 git grep -E 与 \| 不同现' -Expect '误用 = 0 且扫描集 > 0' `
    -Actual ([pscustomobject]@{ Exit = $grepBad.Count; Stdout = ($grepBad -join '; ') }) `
    -Predicate { $grepBad.Count -eq 0 -and $tableFiles.Count -gt 0 }
# ⚠️ 与 C5 同理：本格扫的是**同一个 `$tableFiles`**，与 C3/C5 共用枚举。
# **实测（`SELFTEST_INJECT=noenum`）**：枚举塌空时 `C3`/`C5`/`C7` 全 FAIL，而本格**仍 PASS**
# ——它报「误用 = 0」，而它**一个文件都没读过**。借邻格的失败解释自己的绿，不算判据。
# 故同样并入「扫描集非空」这一前提（**不新开格**，见 C6 上方关于总格数的那段理由）。

# --- C5 · 编号引用完整性（防幻影引用）
# 形状：文档里写了 GAP-099 / DEFER-099 之类，而台账里根本没有那一条。
# 读者照着编号去台账查 —— 查不到，而他不会知道是编号错了还是自己看错了。
# 本仓真实发生过一次（GAP-016 幻影路径），且总控本轮写文档时差点再犯一次（引用尚未登记的 DEFER-014）。
# 数法：全仓 tracked 文件里出现的 GAP-NNN / DEFER-NNN，逐个到 docs/ledger.md 里找定义行。
$ledgerPath = Join-Path $RepoRoot 'docs/ledger.md'
$defined = @{}
if (Test-Path -LiteralPath $ledgerPath) {
    foreach ($m in [regex]::Matches([System.IO.File]::ReadAllText($ledgerPath), '^\|\s*\*\*`?(GAP|DEFER)-(\d{3})`?\*\*', 'Multiline')) {
        $defined["$($m.Groups[1].Value)-$($m.Groups[2].Value)"] = $true
    }
}
$phantom = @()
foreach ($f in $tableFiles) {
    $fp = Join-Path $RepoRoot $f
    if (-not (Test-Path -LiteralPath $fp)) { continue }
    $txt = [System.IO.File]::ReadAllText($fp)
    foreach ($m in [regex]::Matches($txt, '\b(GAP|DEFER)-(\d{3})\b')) {
        $id = "$($m.Groups[1].Value)-$($m.Groups[2].Value)"
        if (-not $defined.ContainsKey($id)) { $phantom += "$f → $id" }
    }
}
$phantom = @($phantom | Sort-Object -Unique)
Assert-Cell -Name "C5 编号引用完整（台账定义了 $($defined.Count) 条）" -Expect '幻影引用 = 0 且扫描集 > 0' `
    -Actual ([pscustomobject]@{ Exit = $phantom.Count; Stdout = ($phantom -join '; ') }) `
    -Predicate { $phantom.Count -eq 0 -and $tableFiles.Count -gt 0 }
# ⚠️ 为什么 C5 也要带「扫描集非空」这个前提（而 C3 已经守着同一件事）：
# 本格与 C3 **共用同一个 `$tableFiles`**（同一变量、同一时刻的值）。枚举塌空时两条路都会响，
# 但**响的是 C3，C5 自己仍是绿的** —— 而 C5 的 PASS 在那一刻**没有任何意义**（它一个字都没扫）。
# 借邻格的失败来解释自己的绿，是把判据的成立条件寄生在别处的失败上；C5 的立条理由正是
# 「防幻影引用」，而报告 `幻影引用 = 0` 却一个文件都没读，是本条最不该出现的那种绿。
# **刻意不**加 `$defined.Count -gt 0`：**零条定义是合法状态**——新采用方的台账模板里可能
# 一条 `GAP-` 都还没有，那时「零引用、零定义」确实是对的。加它会**误报合法输入**，
# 而「误报的判据比没有判据更糟——它会教人忽略它」（本文件 C6 第一版判据的历史教训，D3）。

# ================================================================ D · 双运行时对等（GAP-026 ②）
# Claude Code 与 Antigravity 走两个入口、两套挂载。二者【刻意不完全相同】（见 D2），
# 但"刻意不同"必须是【声明过的不同】——否则哪天有人为了"对齐"把 AGENTS.md 加进 GEMINI.md，
# 就会撞上 24KB 截断，而那个静默失效正是 GAP-023 踩过的坑。
"== D · 双运行时对等（GAP-026 ②）=="

function Get-HeadingLines {
    param([string]$Path)
    $p = Join-Path $RepoRoot $Path
    if (-not (Test-Path -LiteralPath $p)) { return @() }
    return @(Select-String -LiteralPath $p -Pattern '^#{2,3} ' | ForEach-Object { $_.Line })
}

# --- D1 · 两入口章节数相等（GEMINI.md 自称"与 CLAUDE.md 对等、结构保持一致"）
$zhIn = Get-HeadingLines 'CLAUDE.md'
$enIn = Get-HeadingLines 'GEMINI.md'
Assert-Cell -Name "D1 CLAUDE.md 与 GEMINI.md 章节数相等（$($zhIn.Count)/$($enIn.Count)）" -Expect '两数相等且 >0' `
    -Actual ([pscustomobject]@{ Exit = $zhIn.Count; Stdout = $enIn.Count }) -Predicate { $zhIn.Count -eq $enIn.Count -and $zhIn.Count -gt 0 }

# --- D2 · GEMINI.md 【刻意】不 @ 展开 AGENTS.md
# 为什么断言"没有"：Antigravity 的 user_rules 单文件上限 24,000 B，内联展开 AGENTS.md（>50 KB）
# 会把它静默截断到 24KB（GAP-023 实测）。故 AGENTS.md 走 user_rules + PreInvocation 分片续载。
# 这一格防的是"为了对等而误加 @AGENTS" —— 那会让规则源静默丢一半。
$gi = Join-Path $RepoRoot 'GEMINI.md'
$inlineAgents = 0
$giExists = Test-Path -LiteralPath $gi
if ($giExists) {
    $inlineAgents = @(Select-String -LiteralPath $gi -Pattern '@\[?\s*AGENTS' -AllMatches).Count
}
# ⚠️ 前提：**`GEMINI.md` 必须真的存在**。少了它，文件一缺 `$inlineAgents` 就是 0 ⇒ PASS ——
# 即「删掉文件」就能满足「防 24KB 截断」，那是**用消失来通过**。
# **为什么这不是"误报合法状态"**：`GEMINI.md` 是**框架源文件**（`git ls-files` 里有它），
# 框架仓里它缺席 = 被删了；采用方不跑本脚本的 F/D 组也是同样的口径（本脚本本来就假定
# 工作区根有框架文件——C1 对 `AGENTS.md`/`AGENTS.en.md` 缺席的处置也是 FAIL，不是 SKIP）。
Assert-Cell -Name 'D2 GEMINI.md 【不】@ 展开 AGENTS.md（防 24KB 截断）' -Expect '命中 = 0 且文件存在' `
    -Actual ([pscustomobject]@{ Exit = $inlineAgents; Stdout = '' }) `
    -Predicate { $inlineAgents -eq 0 -and $giExists }

# --- D3 · 守卫用到的退出码 ⊆ stop-adapter 覆盖的退出码
# stop-adapter.ps1 把 Claude Code 的协议翻成 Antigravity 的协议。它显式处理：
#   stdout {"decision":"block"} -> continue（阻断）· exit 1 + stderr -> 透传 + allow（提示）· exit 0 -> allow
# 若某守卫新增一个【未被覆盖】的退出码（如 exit 2），适配器会落到 allow 分支 ——
# 即【新的失败模式被静默放行】。本格就是防这个。
$adapterCovered = @(0, 1)
$guardExits = @{}
foreach ($g in @('check-progress.ps1', 'check-numbers.ps1')) {
    $gp = Join-Path $RepoRoot ('.claude/hooks/' + $g)
    if (-not (Test-Path -LiteralPath $gp)) { continue }
    foreach ($m in [regex]::Matches([System.IO.File]::ReadAllText($gp), 'exit\s+(\d+)')) {
        $guardExits[[int]$m.Groups[1].Value] = $true
    }
}
$uncovered = @($guardExits.Keys | Where-Object { $_ -notin $adapterCovered } | Sort-Object)
Assert-Cell -Name "D3 守卫退出码 ⊆ adapter 覆盖（守卫用 $($guardExits.Keys -join '/')；覆盖 $($adapterCovered -join '/')）" `
    -Expect '未覆盖 = 0' -Actual ([pscustomobject]@{ Exit = $uncovered.Count; Stdout = ($uncovered -join ',') }) `
    -Predicate { $uncovered.Count -eq 0 }

# --- D4 · 两入口含 `ONBOARDING.md` 指针，且【不得】@ 导入它（`2026-10-25`，issue #55）
# 为什么断言"有指针"：ONBOARDING 是【按需读】的接入引导。两个入口若都不提它，
# 新用户从入口出发永远走不到那一步 —— 而"文档存在但无人被指向它"是**不会响的缺失**
# （与 `AGENTS.md` §0.0「位置错不会报错」同族：它只是安静地不在场）。
# 为什么同时断言"【不】@ 导入"：`@ONBOARDING.md` 会让它变成**常驻上下文**——
# 而本框架的整套体量取舍都建立在"`AGENTS.md` 常驻、其余按需读"上（`AGENTS.md` §5 入库策略 +
# `DEFER-008` 的体量预算）。把引导也常驻，等于**用一条命令把预算推翻**，且发生时不会有任何东西响。
# **两种形态都要挡**：`@ONBOARDING.md`（裸路径）与 `@[label](ONBOARDING.md)`（Markdown 链接式导入）。
# ⚠️ 前提：**两个文件都必须存在**（同 D2 的教训）——若只断言"命中 = 0"，
# **把入口文件删掉就能通过**，那是「用消失来通过」。
$entryFiles = @('CLAUDE.md', 'GEMINI.md')
$entryBad = @()
foreach ($ef in $entryFiles) {
    $ep = Join-Path $RepoRoot $ef
    if (-not (Test-Path -LiteralPath $ep)) { $entryBad += "$ef 不存在"; continue }
    $etxt = [System.IO.File]::ReadAllText($ep)
    if ($etxt -notmatch 'ONBOARDING\.md') { $entryBad += "$ef 未指向 ONBOARDING.md" }
    foreach ($m in [regex]::Matches($etxt, '@[^\n]*ONBOARDING')) { $entryBad += "$ef 出现 @ 导入：$($m.Value.Trim())" }
}
Assert-Cell -Name "D4 两入口含 ONBOARDING.md 指针且不 @ 导入（$($entryFiles.Count) 个入口）" `
    -Expect '问题 = 0（两文件均存在 · 均含指针 · 均无 @ 导入）' `
    -Actual ([pscustomobject]@{ Exit = $entryBad.Count; Stdout = ($entryBad -join '; ') }) `
    -Predicate { $entryBad.Count -eq 0 }

# ================================================================ E · 进度页投影完整性
# 台账是唯一事实源，进度页是它的【展示投影】。投影漏条 → 按页面执行任务的人【直接漏掉任务】，
# 且【漏了不会响】（GAP-022 同族的失效形态）。
# 本类已真实咬过两次：一次是源文件 `[目前不做]` 标记被移除，一次是源文件第 11 条被整条换掉。
"== E · 进度页投影完整性 =="

# 页名由指针文件一行指定（页名的唯一事实源）
$ptrPath = Join-Path $RepoRoot '.claude/progress-page.txt'
$pagePath = $null
if (Test-Path -LiteralPath $ptrPath) {
    $pn = (Get-Content -LiteralPath $ptrPath -Raw -ErrorAction SilentlyContinue)
    if ($pn) { $pn = $pn.Trim() }
    if ($pn) { $pagePath = Join-Path $RepoRoot $pn }
}

if (-not $pagePath -or -not (Test-Path -LiteralPath $pagePath)) {
    # 页面不存在 = 尚未初始化，无判据可言（与守卫同口径，AGENTS.md §5）。**不算失败**。
    "  SKIP  E 组：进度页不存在（尚未初始化），无判据可言"
} else {
    $pageTxt = [System.IO.File]::ReadAllText($pagePath)

    # --- E1 · 页面覆盖全部 GAP-/DEFER- 编号
    # 防的是：台账新增了编号，页面没跟上 —— 读者在页面上看不到它，以为没有。
    $ledgerTxt = [System.IO.File]::ReadAllText((Join-Path $RepoRoot 'docs/ledger.md'))
    $allIds = @()
    foreach ($m in [regex]::Matches($ledgerTxt, '^\|\s*\*\*`?(GAP|DEFER)-(\d{3})`?\*\*', 'Multiline')) {
        $allIds += "$($m.Groups[1].Value)-$($m.Groups[2].Value)"
    }
    $allIds = @($allIds | Sort-Object -Unique)
    $pageIds = @()
    foreach ($m in [regex]::Matches($pageTxt, '\b(GAP|DEFER)-\d{3}\b')) { $pageIds += $m.Value }
    $missing = @($allIds | Where-Object { $_ -notin $pageIds })
    # ⚠️ **本格【不】加"台账非空"前提**（`2026-10-16` 撤回上一轮加的那一条，理由如实记）：
    # 上一轮我给的理由是「进度页由台账生成」——**那个前提不成立**：进度页是总控**手写**的 HTML，
    # 页名还是 `.claude/progress-page.txt` 里一行**自由文本**，**没有任何机械关系**把台账变成页面。
    # 在错的前提上加强制，只会把「合法状态」判成违规。
    # ⚠️ **更关键的是同源不同判**：`C5` 与 `E1` 读**同一份文件、同一个正则、同一个数**（`$defined` / `$allIds`）。
    # 我上一轮只给 `E1` 加了非空前提 ⇒ **一次跑、一个零、两个判决**——这本身自相矛盾。
    # 现在两格**一致地都不加**：零条定义是**合法状态**（新采用方的台账可以一条编号都没有）。
    Assert-Cell -Name "E1 页面覆盖全部编号（台账 $($allIds.Count) 条）" -Expect '未覆盖 = 0' `
        -Actual ([pscustomobject]@{ Exit = $missing.Count; Stdout = ($missing -join ',') }) `
        -Predicate { $missing.Count -eq 0 }

    # --- E3 · 状态条数字 = 实测
    # 为什么要有它（2026-10-15 补）：E1 查【编号覆盖】、E2 查【待办条数】，都【抓不到状态条过期】——
    # 而状态条正是读者第一眼看的「当前是什么状态」。实测踩过：页面写「提交 88 / 入库 51」，
    # 实测为 87 / 52（新增 docs/planning/ 后入库数变了，而「提交」是我按"加一"写的、没实测）。
    # 这条把「head / 提交 / 入库」三项都钉到实测上——它们是 D1 所说"必须当场量的"那一类数字。
    #
    # ⚠️ 这三项是 **git 操作**，必须走 `$GitRepo`（仓库根）而非 `$RepoRoot`（工作区根）：
    # 目标布局下工作区根**不是**仓，`git -C` 直接报错 ⇒ 三项全空/全零 ⇒ **E3/E4 以恒真方式假绿**
    # （`$realHead` 空串、`$realComm`/`$realFile` 为 0，与页面比对时必然"不等"或"相等"都失去意义）。
    # 故三项**必须显式查退出码**，取不到就报错退出——**不得留空往下走**（与 A9 前条件同一手法）。
    #
    # ⚠️ **三项一律走【主干】，不走当前检出的 HEAD**（`GAP-031`，与守卫同一口径）：
    # 页面是**主干的事实**，不是"某个特性分支此刻的事实"。若这里用 `HEAD`，则
    #   ① 页面按新口径记主干、尺子拿 HEAD 比 ⇒ **在特性分支上 E3/E4 永久假红**（D3：误报更糟）；
    #   ② 反过来，若页面被写成某分支 tip，尺子也会跟着"认可"它 —— 那把守卫的判据从尺子侧抹掉了。
    # `提交`/`入库` 两项**一并走主干**，理由同上：它们仨是同一条状态条上的同一组事实，
    # 让其中一项量主干、另两项量分支，等于让状态条自己自相矛盾。
    # **代价（显式）**：在特性分支上新增的提交/文件，要到合入主干后才计入 —— 那正是"主干事实"的含义。
    $mainline = Resolve-Mainline $script:GitRepo
    if (-not $mainline) {
        [Console]::Error.WriteLine(
            "守卫自测未运行：在 $GitRepo 解析不到主干（origin/HEAD / refs/heads/main / HEAD 三级全不中）。" +
            "E3/E4 无基准可用，故明确报错——这不是「通过」。")
        exit 1
    }
    $realHeadProbe = Invoke-GitChecked { git -C $script:GitRepo rev-parse --short $mainline.Ref 2>$null }
    $realCommProbe = Invoke-GitChecked { git -C $script:GitRepo rev-list --count $mainline.Ref 2>$null }
    # `入库` 仍用 `ls-files`，但**在同一棵树**上取（`ls-tree -r <主干>`）：它本就是"仓库跟踪的文件数"，
    # 只是从"当前 index/工作树"改为"主干那一棵树"。自托管布局下二者读数相同（实测 `53 / 53`），
    # 故这不改变既有结论，只在特性分支上让口径与其余两项一致。
    $realFileProbe = Invoke-GitChecked { git -C $script:GitRepo ls-tree -r --name-only $mainline.Ref 2>$null }
    if ($realHeadProbe.Exit -ne 0 -or $realCommProbe.Exit -ne 0 -or $realFileProbe.Exit -ne 0 -or -not $realHeadProbe.Text) {
        [Console]::Error.WriteLine(
            "守卫自测未运行：在 $GitRepo 取不到 E3/E4 的实测基准（主干 $($mainline.Name) 的 HEAD / 提交数 / 入库文件数）。" +
            "留空会让 E3/E4 以恒真方式假绿，故明确报错——这不是「通过」。")
        exit 1
    }
    $realHead = $realHeadProbe.Text
    $realComm = $realCommProbe.Text
    $realFile = @($realFileProbe.Text -split "`n" | Where-Object { $_ -ne '' }).Count

    # 页面侧的三个读数（正则从展示层抠；抠不到 = 状态条确实缺那一项，由下面的 $barBad 报出）
    $barHead = [regex]::Match($pageTxt, '<div>head <b>([0-9a-fA-F]{7,40})</b>[^<]*</div>')
    $barComm = [regex]::Match($pageTxt, '<div>提交 <b>(\d+)</b>[^<]*</div>')
    $barFile = [regex]::Match($pageTxt, '<div>入库 <b>(\d+)</b>[^<]*</div>')
    $barBad = @()
    if (-not $barHead.Success) { $barBad += '状态条缺 head' }
    elseif ($barHead.Groups[1].Value -ne $realHead) { $barBad += "head 页=$($barHead.Groups[1].Value) 实测=$realHead" }
    if (-not $barComm.Success) { $barBad += '状态条缺 提交' }
    elseif ([int]$barComm.Groups[1].Value -ne [int]$realComm) { $barBad += "提交 页=$($barComm.Groups[1].Value) 实测=$realComm" }
    if (-not $barFile.Success) { $barBad += '状态条缺 入库' }
    elseif ([int]$barFile.Groups[1].Value -ne [int]$realFile) { $barBad += "入库 页=$($barFile.Groups[1].Value) 实测=$realFile" }
    Assert-Cell -Name "E3 状态条 head/提交/入库 = 实测" -Expect '不一致 = 0' `
        -Actual ([pscustomobject]@{ Exit = $barBad.Count; Stdout = ($barBad -join '; ') }) -Predicate { $barBad.Count -eq 0 }
    # --- E4 · memory.md 的状态行数字 = 实测
    # 为什么要有它（2026-10-15 补）：同一轮里我把「提交数 / 入库数」写错过三次
    # （页面状态条 · memory 提交数 · memory 入库数）——全是"按加一写、没实测"。
    # 页面那三项目前由 E3 钉住，而 memory.md 的同类数字【此前无任何东西在查】。
    # memory.md 不存在时跳过（首次使用尚未初始化，AGENTS.md §5 同口径）。
    $memPath = Join-Path $RepoRoot 'memory.md'
    if (-not (Test-Path -LiteralPath $memPath)) {
        "  SKIP  E4：memory.md 不存在（尚未初始化）"
    } else {
        $memTxt = [System.IO.File]::ReadAllText($memPath)
        $memBad = @()
        $mHead = [regex]::Match($memTxt, 'HEAD \*\*`([0-9a-fA-F]{7,40})`\*\*')
        $mComm = [regex]::Match($memTxt, '\*\*(\d+)\*\* 个提交')
        $mFile = [regex]::Match($memTxt, '入库 \*\*(\d+)\*\* 文件')
        if (-not $mHead.Success) { $memBad += 'memory 状态行缺 HEAD' }
        elseif ($mHead.Groups[1].Value -ne $realHead) { $memBad += "memory HEAD=$($mHead.Groups[1].Value) 实测=$realHead" }
        if (-not $mComm.Success) { $memBad += 'memory 状态行缺 提交数' }
        elseif ([int]$mComm.Groups[1].Value -ne [int]$realComm) { $memBad += "memory 提交=$($mComm.Groups[1].Value) 实测=$realComm" }
        if (-not $mFile.Success) { $memBad += 'memory 状态行缺 入库数' }
        elseif ([int]$mFile.Groups[1].Value -ne [int]$realFile) { $memBad += "memory 入库=$($mFile.Groups[1].Value) 实测=$realFile" }
        Assert-Cell -Name 'E4 memory.md 状态行 HEAD/提交/入库 = 实测' -Expect '不一致 = 0' `
            -Actual ([pscustomobject]@{ Exit = $memBad.Count; Stdout = ($memBad -join '; ') }) -Predicate { $memBad.Count -eq 0 }
    }
    # --- E2 · 页面的「用户待办」条数与源文件一致
    # 源文件不入库、无判据盯着它 —— 改动它不会有任何东西响。本格就是那个"盯着它"的东西。
    $todoSrc = Join-Path $RepoRoot '我要做什么.txt'
    if (Test-Path -LiteralPath $todoSrc) {
        $srcIds = @()
        foreach ($l in [System.IO.File]::ReadAllLines($todoSrc)) {
            if ($l -match '^(\d+)、') { $srcIds += [int]$Matches[1] }
        }
        # 页面 ② 组表格：取 "id=todo" 到下一个 h2 之间的 <tr><td>NN</td>
        $a = $pageTxt.IndexOf('id="todo"')
        $b = if ($a -ge 0) { $pageTxt.IndexOf('<h2', $a + 1) } else { -1 }
        $todoPageIds = @()
        if ($a -ge 0 -and $b -gt $a) {
            $seg = $pageTxt.Substring($a, $b - $a)
            foreach ($m in [regex]::Matches($seg, '<tr><td>(?:<b>)?(\d+)(?:</b>)?</td>')) { $todoPageIds += [int]$m.Groups[1].Value }
        }
        $todoMissing = @($srcIds | Where-Object { $_ -notin $todoPageIds })
        Assert-Cell -Name "E2 页面待办覆盖源文件（源 $($srcIds.Count) 条 / 页 $($todoPageIds.Count) 条）" -Expect '漏条 = 0' `
            -Actual ([pscustomobject]@{ Exit = $todoMissing.Count; Stdout = ($todoMissing -join ',') }) -Predicate { $todoMissing.Count -eq 0 }
    } else {
        "  SKIP  E2：源文件 我要做什么.txt 不存在"
    }
}

# --- E5 · `memory.md` 的「业务仓」行 = 文件系统实测（`2026-10-25`，issue #55）
# 为什么要有它：`memory.md` 的「状态」节是**总控手写的投影**，而「接入了哪些业务仓」是
# **文件系统里可实测的事实**（`AGENTS.md` §0.0「带项目布局」：业务项目各自含 `.git`、不被框架仓跟踪）。
# 两处一旦不同成熟度，读者会按记忆里的旧清单行事 —— 与 `E3`/`E4` 同一族（手写数字 vs 实测），
# 而这一类**已经真实咬过三次**（页面状态条 · memory 提交数 · memory 入库数）。
#
# ⚠️ **本格必须放在上面那个 `if (-not $pagePath …) { } else { }` 块的【外面】**：
# 它只依赖 `memory.md`，**不依赖进度页**。放进块内会让它随「页面缺失（尚未初始化）」一起 `SKIP`，
# 从而继承 `GAP-028` 的缺陷 —— **一个与页面无关的判据，却因页面不存在而永不执行**。
# 那种"跳过"在观测上与"检查过了"同形（D3），而它恰恰是**新项目首次使用**时的常态。
#
# 判据两侧：
#   实测值 = 工作区根下**每个含 `.git` 的子目录**的名字，`Sort-Object` 后以 `, ` 连接；
#            **零个 ⇒ `未接入`**（合法状态，不是失败）。
#            判定**必须**用 `Test-Path <dir>/.git`，**不得**只看目录名 —— 目录名不带任何承诺。
#            （与 `Resolve-GitRepo` / `Get-RepoFiles` 同一手法：`.git` 是**目录**（普通仓）或**文件**
#             （submodule / worktree）时 `Test-Path` 都命中 —— 两种形态都确实是**独立的仓**。）
#   记忆值 = `memory.md` 里**行首**匹配 `^业务仓：(.*)$` 的第一条捕获，`Trim()`。
#            行首锚点是刻意的：「业务仓的编号空间」等叙述是**行内**文字（`memory.md` 实测确认），
#            不该被当成这一行。
#   `memory.md` 不存在 ⇒ `SKIP`（`AGENTS.md` §5「首次使用即初始化」，与 `E4` 同口径）。
#   **行缺失 ⇒ FAIL**（不是 SKIP）：缺行 = 投影缺失，不是合法状态 ——
#   与 `AGENTS.md` §4.0「① 必须留一行」同源：**没有那一行，"做过判断"与"没做过"不可区分**。
$memBizPath = Join-Path $RepoRoot 'memory.md'
if (-not (Test-Path -LiteralPath $memBizPath)) {
    "  SKIP  E5：memory.md 不存在（尚未初始化）"
} else {
    $subRepoNames = @()
    foreach ($subDir in @(Get-ChildItem -LiteralPath $RepoRoot -Directory -Force -ErrorAction SilentlyContinue)) {
        if (Test-Path -LiteralPath (Join-Path $subDir.FullName '.git')) { $subRepoNames += $subDir.Name }
    }
    $subRepoNames = @($subRepoNames | Sort-Object)
    $actualBiz = if ($subRepoNames.Count -eq 0) { '未接入' } else { $subRepoNames -join ', ' }

    $memBiz = [regex]::Match([System.IO.File]::ReadAllText($memBizPath), '(?m)^业务仓：(.*)$')
    if (-not $memBiz.Success) {
        # 缺行 = 投影缺失。**显式 FAIL 并打印实测值** —— 否则读者只知道"红了"，不知道该填什么。
        $script:Fail++
        "  FAIL  E5 memory.md 缺「业务仓：」行（实测应为：$actualBiz）"
    } else {
        $memBizVal = $memBiz.Groups[1].Value.Trim()
        Assert-Cell -Name "E5 memory.md「业务仓」行 = 实测（记忆=$memBizVal 实测=$actualBiz）" `
            -Expect '两值相等' -Actual ([pscustomobject]@{ Exit = $memBizVal; Stdout = $actualBiz }) `
            -Predicate { $memBizVal -eq $actualBiz }
    }
}

# ================================================================ F · 角色只读围栏（GAP-001 残余）
# `tools:` 是声明，挂载才是事实 —— 但【声明本身】得先自洽，否则派发时才发现就晚了。
# 本组守一条【安全不变量】与它的对偶：
#   只读角色（description 标「只读」）= 机械只读 ⇒ tools 里【不得】有任何 shell
#   写方角色                        = 能干活   ⇒ tools 里【应有】一个 shell
# 两半都要，缺一半就会漏：
#   只查「只读不得有 shell」→ 漏掉「写方没声明 shell」⇒ 派去干活却发现干不了（GAP-001 的原形态）
#   只查「写方应有 shell」→ 漏掉「只读被加上 shell」⇒ 机械只读静默失效、无人报警
# 「完全没有 tools: 声明」= 退回默认工具集（可能含写权限）⇒ 对只读角色是同一族风险。
"== F · 角色只读围栏（GAP-001 残余）=="

$shellNames = 'PowerShell|Bash|cmd|zsh|fish|sh'
$agentDir = Join-Path $RepoRoot '.claude/agents'
$roViolations = @()   # 只读角色却带 shell（或完全没声明）
$rwViolations = @()   # 写方角色却没有 shell
$roCount = 0; $rwCount = 0

# ⚠️ **`F1`/`F2` 的非空前提：`2026-10-16` 撤回上一轮加的 `$roCount -gt 0` / `$rwCount -gt 0`。**
# 理由（我上一轮的理由错在哪，如实记）：
#   我写的是「框架仓的 `.claude/agents/` **必然**同时含只读角色与写方角色」。**对本仓成立，对采用方不成立**——
#   而这把尺子**正是发给采用方的**。`docs/adopting.md` 明写「**只实例化你会派发的**」⇒
#   **只装只读角色（或一个都不装）是文档明确支持的合法状态**，不是病态。
#   在那种状态上判 FAIL，是把**合法输入**报成违规 —— 而 `D3` 的原话是
#   **「误报的判据比没有判据更糟——它会教人忽略它」**。这正是 `GAP-018` 的原形：
#   **规则措辞依赖了某一个具体仓库的状态**（本仓恰好两半都有）。
# ⇒ 改用**与状态无关**的形态（`D1` 的 `$zhIn.Count -gt 0` 已是同一手法）：
#   ① **目录不存在** ⇒ 该组 `SKIP`（不判、不占 PASS/FAIL；见下方 `if`）——用 `SKIP` 表达
#      「本工作区没装角色层」，而不是 `FAIL`（把"没装"当成违规）；
#   ② **目录存在但一个角色都没有** ⇒ `FAIL`。**这一条才是真问题**：
#      一个**建好了却没放任何角色**的 `.claude/agents/` 是**半成品**，`AGENTS.md` §4.0 的注册制/派发规则
#      全落空，而它看起来"目录在、像装好了"。⇒ 它必须响。
#      **为什么它不会误报**：合法采用方的两种状态是"目录不存在"与"目录里有他会派发的角色"；
#      "目录在、里面空"**不在** `adopting.md` 支持的状态里。
# 机械形态：`$agentFileCount` = `Get-ChildItem` 实得数（**不是**"非空前提"式的计数，故不骗人）。
$agentFileCount = @(Get-ChildItem -LiteralPath $agentDir -Filter '*.md' -File -ErrorAction SilentlyContinue).Count
$agentDirExists = Test-Path -LiteralPath $agentDir

foreach ($f in @(Get-ChildItem -LiteralPath $agentDir -Filter '*.md' -ErrorAction SilentlyContinue | Sort-Object Name)) {
    if ($f.Name -eq 'README.md') { continue }   # 文档不是角色，无 frontmatter
    $txt = [System.IO.File]::ReadAllText($f.FullName)
    $descMatch = [regex]::Match($txt, '(?m)^description:\s*(.+)$')
    $toolsMatch = [regex]::Match($txt, '(?m)^tools:\s*(.+)$')
    $isReadOnly = $descMatch.Success -and $descMatch.Groups[1].Value -match '只读'
    $toolsLine = if ($toolsMatch.Success) { $toolsMatch.Groups[1].Value.Trim() } else { '' }
    $hasShell = $toolsLine -match $shellNames

    if ($isReadOnly) {
        $roCount++
        # 只读必须以『仅 Read / Grep / Glob』收口；带 shell 即破围栏；无声明同样不合格
        if ($toolsLine -eq '') { $roViolations += "$($f.Name) — 无 tools: 声明（退回默认工具集）" }
        elseif ($hasShell) { $roViolations += "$($f.Name) — 只读却带 shell：$toolsLine" }
        elseif ($toolsLine -match 'Write|Edit') { $roViolations += "$($f.Name) — 只读却带 Write/Edit：$toolsLine" }
    } else {
        $rwCount++
        if (-not $hasShell) { $rwViolations += "$($f.Name) — 写方却无 shell：$toolsLine" }
    }
}

if (-not $agentDirExists) {
    # 没装角色层 = 合法状态（采用方可以只要框架的守卫与文档），不判 ⇒ SKIP。
    "  SKIP  F 组：.claude/agents/ 不存在（本工作区未装角色层），无判据可言"
} elseif ($agentFileCount -eq 0) {
    # 目录在、里面一个角色都没有 = **半成品**（见上方注释）⇒ 必须响，且**不依赖任何角色状态**
    $script:Fail++
    "  FAIL  F 组：.claude/agents/ 存在但一个角色都没有（半成品——注册制与派发规则全落空）"
} else {
    Assert-Cell -Name "F1 只读角色不含 shell/Write/Edit 且有声明（$roCount 个只读角色）" -Expect '违规 = 0' `
        -Actual ([pscustomobject]@{ Exit = $roViolations.Count; Stdout = ($roViolations -join '; ') }) `
        -Predicate { $roViolations.Count -eq 0 }

    # 对照：`C5` 的 `$defined.Count` 是**合法零输入**（新采用方的台账可以一条编号都没有）⇒ 那一处**刻意不加**前提。
    # 而 `F1`/`F2` 的零角色**不在** `adopting.md` 支持的状态里（"目录在、里面空"），故由上面那一格兜住。
    Assert-Cell -Name "F2 写方角色已声明 shell（$rwCount 个写方角色）" -Expect '违规 = 0' `
        -Actual ([pscustomobject]@{ Exit = $rwViolations.Count; Stdout = ($rwViolations -join '; ') }) `
        -Predicate { $rwViolations.Count -eq 0 }
}


# --- C7 · `.ps1` 里不得有「仅靠大小写区分」的变量名（2026-10-15 补）
# 为什么要有它：**PowerShell 的变量名大小写不敏感** —— `$h` 与 `$H` 是**同一个变量**。
# 我本人就在这一条上出过事故：写同步脚本时用 `$h` 存页面内容、`$H` 存 HEAD sha，
# 于是「HEAD sha」被页面内容覆盖，**整页被注入自身**，`memory.md` 同样被污染。
# 同类还有 `$c`/`$C`（CRLF 计数 vs 提交数）· `$f`/`$F`（文件名 vs 入库数）。
#
# ⚠️ **本格的诚实边界**：它只扫**仓库内入库的 `.ps1`**。**我那次事故的脚本是临时脚本**
# （在 `.git/` 下、不入库）—— **本格抓不到它**。故本格是**对同一族的预防**，不是那次事故的修复。
# 预防的价值：任何人往后写进仓库的钩子脚本，都不会再踩这个静默别名坑。
#
# ⚠️ 枚举走 `Get-RepoFiles`（布局无关，同 C3 的理由）：目标布局下框架的 `.ps1` **不在任何仓里**，
# `ls-files` 枚举不到 ⇒ 本格扫 0 个文件而报 `冲突 = 0` —— **零输入而绿，与「扫过了没有冲突」同形**。
# 故谓词里加 `$V_Ps1Count -gt 0`：**扫到的 `.ps1` 个数必须 > 0**。
# （本仓现有 5 个入库 `.ps1`：`.agents/hooks/` 两个 + `.claude/hooks/` 三个。）
$V_CASE_HITS = @()
$V_PS1 = @(Get-RepoFiles '*.ps1')
$V_Ps1Count = $V_PS1.Count
foreach ($V_F in $V_PS1) {
    $V_P = Join-Path $RepoRoot $V_F
    if (-not (Test-Path -LiteralPath $V_P)) { continue }
    $V_T = [System.IO.File]::ReadAllText($V_P)
    # 只扫【非注释行】—— 注释里引用 `$h`/`$H` 作举例，不是变量使用（本格第一版即栽在此）。
    # 且排除【作用域前缀】（`$script:` / `$env:` …）—— 那是 `$<scope>:`，不是名为 scope 的变量。
    $V_CODE = ([System.IO.File]::ReadAllLines($V_P) |
        Where-Object { -not $_.TrimStart().StartsWith('#') }) -join "`n"
    $V_NAMES = [regex]::Matches($V_CODE, '\$([A-Za-z_][A-Za-z0-9_]*)\b(?!:)') |
        ForEach-Object { $_.Groups[1].Value } | Sort-Object -CaseSensitive -Unique
    # ⚠️ 必须 -CaseSensitive：Sort-Object -Unique 默认【大小写不敏感】，会把 $EAP_TEST 与 $eap_test 折叠成一个 ⇒ 冲突组永远为 0（本格第一版即栽在此，实测抓到）。
    # 同族先例：check-numbers.ps1 用 HashSet + StringComparer::Ordinal（GAP-019 的修复）。
    foreach ($V_G in ($V_NAMES | Group-Object { $_.ToLower() } | Where-Object { $_.Count -gt 1 })) {
        $V_CASE_HITS += "$V_F : " + (($V_G.Group | Sort-Object) -join ' / ')
    }
}
Assert-Cell -Name "C7 .ps1 无「仅靠大小写区分」的变量名（扫到 $V_Ps1Count 个 .ps1；PowerShell 大小写不敏感）" `
    -Expect '冲突 = 0 且扫到的 .ps1 个数 > 0' `
    -Actual ([pscustomobject]@{ Exit = $V_CASE_HITS.Count; Stdout = ($V_CASE_HITS -join '; ') }) `
    -Predicate { $V_CASE_HITS.Count -eq 0 -and $V_Ps1Count -gt 0 }

# --- C6 · 全仓「格数总数」陈述一致（2026-10-15 补；**口径经两次收窄**）
# 为什么要有它：格数被抄在 8 个文件里，**没有任何东西让它们同步** —— 同一轮里我因此错了 4 次。
#
# ⚠️ 第一版判据【是错的，如实记】：它扫全仓所有「NN 格」，于是把**合法数字**也报了 ——
# 规划总数（45）· 历史对比（「方案原文称 29 格」）· 时间线（「增至 19 格」）· 分组内数（「A 11」）。
# **误报的判据比没有判据更糟**：它会教人忽略它（D3：判据必须测它声称要测的东西）。
# 故【只认「总数」的固定说法】，不含历史/规划/分组：
$totalPatterns = @(
    '共\s*\*{0,2}(\d+)\s*\*{0,2}\s*格',        # 「共 35 格」
    '一键[：:\s]\s*\*{0,2}(\d+)\s*\*{0,2}\s*格', # 「一键：35 格」
    '\*{0,2}(\d+)\s*格\s*·\s*A–F',              # 「35 格 · A–F」
    '六组\s*/\s*\*{0,2}(\d+)\s*\*{0,2}\s*格',    # 「六组 / 35 格」
    'A–F,\s*\*{0,2}(\d+)\s*cells',              # 英文
    'PASS\s*=\s*(\d+)\s*/\s*FAIL'               # 「PASS = 35 / FAIL」
)
$foundTotals = @{}
foreach ($f in @(Get-RepoFiles '*.md')) {
    # 排除 roadmap：它【合法地】含历史对比（『方案原文称 29 格』）与规划数（『三组共 13 格』）。
    # 一个判据若把合法输入也报出来，就是在教人忽略它（D3）。
    if ($f -like '*roadmap-production*') { continue }
    $fp = Join-Path $RepoRoot $f
    if (-not (Test-Path -LiteralPath $fp)) { continue }
    $txt = [System.IO.File]::ReadAllText($fp)
    foreach ($p in $totalPatterns) {
        foreach ($m in [regex]::Matches($txt, $p)) { $foundTotals[[int]$m.Groups[1].Value] = $true }
    }
}
$actualCells = $script:Pass + $script:Fail + 1   # +1 = C6 自己这一格（此刻尚未计入）
$staleTotals = @($foundTotals.Keys | Where-Object { $_ -ne $actualCells } | Sort-Object)
# ⚠️ 谓词里的 `$foundTotals.Count -gt 0` 与 `$staleTotals.Count -eq 0` **必须同时成立**：
# 枚举塌空时 `$foundTotals` 是**空的**，而"没有任何总数陈述与 $actualCells 不符"**恒真** ⇒
# 本格会以 `实际 34；文中出现 `（出现集为空）**静默全绿** —— 那正是本次要修的病。
# 「一条总数都没找到」与「找到的都对」是**两件事**，必须分开要求。
# 顺带说：本格的格名把「文中出现 …」印出来，**就是为了让空集可见** —— 但只有这次加上非空前提之后，
# 空集才真正**会响**；在此之前它只是"看起来像信息、实则照绿不误"。
Assert-Cell -Name "C6 全仓格数【总数】陈述一致（实际 $actualCells；文中出现 $($foundTotals.Keys -join '/')）" `
    -Expect "非 $actualCells 的总数陈述 = 0 且总数陈述至少 1 处" `
    -Actual ([pscustomobject]@{ Exit = $staleTotals.Count; Stdout = ($staleTotals -join ',') }) `
    -Predicate { $staleTotals.Count -eq 0 -and $foundTotals.Count -gt 0 }

# ================================================================ 小结
""
"---- 小结 ----"
"  PASS = $script:Pass"
"  FAIL = $script:Fail"
""
if ($script:Fail -gt 0) {
    "守卫自测【未通过】——有格的读数与预期不符，守卫可能已失明。"
    "判据是【每一格的分支】，不是两个 SHA 的字面值。"
    exit 1
}
"守卫自测【全部通过】——两条守卫在最该报警的输入上都报了警，"
"且在最该静默的输入上都静默。silence 现在携带信息。"
exit 0
