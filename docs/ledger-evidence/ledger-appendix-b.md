# 附录 B · 证据抄录（**自包含，不依赖仓库外文件**）

> 本文件是唯一台账 `docs/ledger.md` 的**取证附录 B**（体量拆分，见台账 §二）。**内容逐行未改**。


## 三、附录 B · 证据抄录（**自包含，不依赖仓库外文件**）

### B.1 仓库根的解析（布局判据）

```
$ git rev-parse --show-toplevel
D:/MyDocuments/ai-collaboration-framework
exit=0
```

**仓库由含 `.git` 识别，名字任意**——**判据是 `.git` 在谁身上，不是 `project/` 在不在**（`AGENTS.md` §0.0）。
本行在 `project/` 出现前采集（`Test-Path project` → `False` 是彼时事实）；采集后 `project/` 已被人工建出（内含 `README.md`、**无 `.git`**），是**外部项目目录**、不入本仓（挡在 `.git/info/exclude`，见附录 D.6）。

### B.2 `GAP-004` 的证据：框架文件确已被跟踪

```
$ git ls-files | wc -l
16

$ git ls-files
.claude/agents/README.md
.claude/agents/falsifier.md
.claude/agents/gate-auditor.md
.claude/agents/ssot-scribe.md
.claude/hooks/check-progress.ps1
.claude/progress-page.txt
.claude/settings.json
.gitattributes
AGENTS.md
AI_tools/start_claude.bat
CLAUDE.md
README.md
prompts/AI协同工程架构.png
prompts/AI总控.md
prompts/全生命周期工程质量总监与系统架构师.md
prompts/角色契约.md
exit=0
```

> 采集时点快照：当时目录名为 AI_tools/，现已更名为 launchers/（不改写原快照）。

其中 `AGENTS.md` / `CLAUDE.md` / `prompts/*` / `.claude/*` 正是 §5 表格里原标「❌ 不入仓库」的**框架文件与运行态**，它们**确实在仓库里**。**补充实测**：`Test-Path .gitignore` → `False`（本仓**无 `.gitignore`**）。

### B.3 `GAP-006` 的证据：该环无对应物

```
$ Test-Path .github      → False
$ Test-Path Dockerfile   → False
$ Test-Path docs         → False      （登记本表之前）
$ Test-Path project      → False      （预期：自托管布局）
```

### B.4 写死占位名的可跑性对照（实测）

```
$ git -C project status --porcelain
fatal: cannot change to 'project': No such file or directory
exit=128

$ git -C "$REPO" status --porcelain          # $REPO = git rev-parse --show-toplevel
（正常输出工作树状态）
exit=0
```

写死 `project` 时得到的是**「命令没跑」**，**不是**「围栏有效」——**不得**混为一谈（D1）。

### B.5 `GAP-001` / `GAP-005` 的证据：工具挂载与围栏

```
$ Get-Location; echo probe-ok
D:\MyDocuments\ai-collaboration-framework
probe-ok
LASTEXITCODE=0
```

子代理**自报**的工具清单 = `Read` / `Grep` / `Glob` / `PowerShell`（本机 shell 挂载名为 **`PowerShell`**，**不是** `Bash`——`Bash` 在本机解析不了、被**静默丢弃**）；只读角色的 `tools` 一行见**附录 D.5** 的 `git grep` 实测。

**为何去掉 shell**：仅去掉 `Write`/`Edit` **挡不住写**——**shell 本身就是写后门**（`Set-Content` / `Out-File` / `Remove-Item` 都能落盘、能删文件），故**两个都去掉**；**代价**是只读角色**跑不了命令**，执行**交总控代跑**——这**正是 `GAP-005` 的来源**。

### B.6 `GAP-014` 的证据：04 与 06–10 在本仓无对应物（`2026-10-10T07:15:44Z` 实跑）

```
$ Test-Path Dockerfile          → False      （04 构建环）
$ Test-Path .github             → False      （06–10：CI / 自动化）
$ Test-Path deploy              → False      （05 部署环的脚本目录）
$ Test-Path docs/adr            → False      （01 设计环的 ADR 落盘位）
$ Test-Path docs/changes        → False      （02 开发环的先写后填位）
$ Test-Path backend/migrations  → False      （MIG- 落盘位）
```

**读法（两条）**：① 六项**全 `False`** ⇒ 本仓对 04 与 06–10 **确无对应物**，故 `GAP-014` 的两种读法**都有事实基础**，争议在**"约束谁"**，不在"有没有"；② `docs/adr` / `docs/changes` / `backend/migrations` 为 `False` 而 `docs/ledger.md` 存在 ⇒ 本仓的 `docs/` **只有台账一件**，这正是"**模板仓**"的形态——此形态**支持**读法 (a)，但**不构成裁定**（裁定权在人工）。

