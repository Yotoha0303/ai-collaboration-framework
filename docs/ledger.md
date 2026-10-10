# 未竟事项 · 唯一台账（`docs/ledger.md`）

> **不在本台账里的"还没做"等于不存在**（出处：`AGENTS.md` §6）。收纳 **`GAP-` / `INC-` / `DEFER-`** 三类；`ADR-` 落 `docs/adr/`，`MIG-` 落 `backend/migrations/`（当前无对应物）。本仓为**自托管布局**，故本文件在仓内、属 ✅ 入库；**不引用仓库外文件**——证据的命令与输出**原样抄录在附录**，clone 的人可直接复核。**D.8 的脚本可整段复制粘贴重跑**（只读，不改任何文件）。

| 项 | 值 |
| --- | --- |
| 台账快照时间（UTC） | `2026-10-10T07:58:04Z`（实测 `(Get-Date).ToUniversalTime()`；前次=`2026-10-10T07:20:14Z`） |
| 快照时 HEAD | `9ce688b`（全长 `9ce688b186e1c6820ba462152193e7c9e4683112`；前次=`d591a31`，即含 `GAP-014` 登记的提交） |
| 快照时入库文件数 | `19`（`git ls-files` 行数实测；含 `.gitignore`；前次=`18`，增量=`launchers/start_claude.sh`，同轮 `AI_tools/` 更名 `launchers/`） |
| 已用 `GAP-` 最大号 | `GAP-014`（前次=`GAP-013`） |
| 已用 `INC-` / `DEFER-` | 无（`0`） |
| 页名指针快照 | `.claude/progress-page.txt` → `project-progress.html`，字节 `112,…,108,10`，SHA256 `BF4B6899…B2ADE1` |

## 一、登记表

**状态取值**：`未解除` / `已解除` / `待人工裁定`。**旧值 `不适用（该环无对应物）` 已废止**——它把"**没建**"与"**不该建**"混为一谈；现按**适用对象**区分：**采用方**无对应物判 `未解除`（该建而未建），**本仓为模板、不受十环约束**（见 `GAP-014`）。**按编号升序，编号不复用、不重号；解除时改状态并加一行留痕，不删原条目。**

| 编号 | 缺口（一句话） | 证据（复跑命令见附录 B） | 解除条件 | 状态 |
| --- | --- | --- | --- | --- |
| **`GAP-001`** | `tools:` 名单里的工具名与**实际挂载名**不一致时**被静默丢弃**，**无报错**——通用风险；本案例已修，但**机制仍在** | 子代理自报工具清单 + `Get-Location; echo probe-ok` 回灌（附录 B.5）：清单 = `Read`/`Grep`/`Glob`/`PowerShell`，`probe-ok`，exit 0。而名单原写 `Bash` → 被丢弃；**本次已改 `ssot-scribe.md` 只写真名**（附录 D.5） | 工具名由**实测**填入而非照抄；核验方法见附录 C.1。**须在每次新增/改动角色 `tools` 时执行** | `已缓解（机制仍在）` |
| **`GAP-002`** | 进度页守卫**双静默**：`.claude/progress-page.txt` 一改错，「缺页静默」与「SHA 判据」**同时失效**（二者共用同一个 `$name` 与同一套路径推导）；**且「缺页静默」与「死代码」在观测上等价**（五种因果不可分） | 攻击 A（2026-10-09 实跑复现，**附录 D.1**）：把指针指向不存在的页名（页实为存在、含错 SHA）→ 守卫 **stdout 空、静默放行** | 让「指针**存在但读不出页名**」与「页**确实缺失**」**分别处置**；改后重跑附录 C.2 的两个用例 | **`已缓解`**（残余见下） |
| **`GAP-003`** | 守卫**误报**：页面写 **40 位完整 SHA** 时，与 **7 位短 SHA** 做**字符串全等**比对，被判为「落后」 | 攻击 B（2026-10-09 实跑复现，**附录 D.2**）：页面写 `<div>head <b>3b9030ff…6b6f72</b></div>` → 守卫 emit `decision:block`（**误报**：内容其实一致） | 改为**前缀比对**，改后重跑用例 | **`已解除`**（附录 D.3 实测） |
| **`GAP-004`** | **自托管布局下，`AGENTS.md` §5「入库策略」的"保障方式：位置，而非忽略规则"论证不成立**——框架文件已被 `git ls-files` 跟踪 | `git ls-files` 共 **16** 个文件，其中**含框架全部文件**（附录 B.2） | 人工裁定后同步改写 §5 表格与 §0.0 提示（二选一：**接受"本仓即框架"**，或**把仓库拆为子目录**） | **`已解除`**（**裁定：采纳"本仓即框架"**，附录 D.4） |
| **`GAP-005`** | **只读围栏修复后引入的新缝隙**：`falsifier` / `gate-auditor` 的执行改由**总控代跑**，但「**代跑是否真的发生**」**没有判据**——代跑缺失时，其产物会停在 `无法判定`，**与"确实没有 shell"外观相同** | 围栏修改本身（附录 B.5）；**无可跑命令能区分二者**——这正是指缝的性质 | 需要一个把「代跑」**投影到留痕**的机制（如：每次代跑强制在运行态记录里留一行，且该行可被机械核验） | `未解除（部分缓解）`（最小锚见下） |
| **`GAP-006`** | 本工作区**尚无 CI / 合约 / 前端等对应物** → `AGENTS.md` §7 部分复核命令属**模板**、当前无对应物。**这不是缺口，而是"该环无对应物"**；按 §7 口径**登记备查** | `Test-Path .github` → `False`；`Test-Path Dockerfile` → `False`；`Test-Path docs` → `False`（登记本表之前） | **接回该环时解除**（届时 §7 对应行从"模板"转为"待实测"） | `已解除` |
| **`GAP-007`** | 守卫的**仓库解析顺序**把 `project/` 排在**工作区根之前**——`project/` 目录**存在但非仓库**时，一旦有人在其中 `git init`，守卫会锁定该**内层空仓** → 取不到 HEAD（unborn，`rev-parse` exit 128）→ **永久静默**，而静默正是它正常时的表现 | 对照实算（附录 D.6）：同一假 `.git` 下，**旧序**解析到 `…\project`，**新序**解析到工作区根；`git -C <新建空仓> rev-parse --short HEAD` → 空输出、**exit 128** | 候选顺序**对调**（优先工作区根），**保留两处候补**；改后重跑附录 C.2 用例 | **`已解除`**（**已独立放行**：`falsifier` 设计攻击、总控代跑 T1 + T10，两方向实测，附录 D.7） |
| **`GAP-008`** | 守卫用**双向前缀**比对 SHA（`:150` `$head.StartsWith($recorded) -or $recorded.StartsWith($head)`），故「**真前缀 + 假后缀**（至 40 位）」被判为一致 → 放行伪造 SHA | 代跑实测（`record.md` `[2026-10-09T14:48:43Z]` 负向 T5，附录 D.7）：页写 `ad4e6c8000000000000000000000000000000000`（真前缀 `ad4e6c8` + 假后缀）→ 守卫 **stdout 空、静默**，本该认出"这不是 HEAD" | 若需覆盖：把"页长 > 7 且 ≥ 前缀"的**歧义**情形改判为不静默；**判定前须人工裁定**（可能得不偿失，见右侧边界） | `已修（二次修复：--verify 须降级 EAP）` |
| **`GAP-009`** | 守卫判仓库用的是 `.git` 的**存在性**而非**有效性**（`:133` `Test-Path (Join-Path $_ '.git')`）：若 `project/.git` 是**空目录**（非有效仓），被选中即 `rev-parse` 失败 → 静默 | **潜在、当前布局不可达**：实测 T3 **BLOCK**（`record.md` `[2026-10-09T14:48:43Z]`，附录 D.7）—— 新序 `@($ws, project)` 令 `$ws` 先命中，**空目录根本不被咨询**；`falsifier` 预测"静默"**被实测推翻**。仅**目标布局**（工作区根无 `.git`、仓真在 `project/`）下可达。**该性质属 `:133` 既有，非本轮引入** | 接回目标布局时改为校验 `.git` **有效**（如 `git -C <cand> rev-parse --git-dir` 成功才采纳），而非 `Test-Path` | `已解除（沙箱独立放行；本仓不可证伪）` |
| **`GAP-012`** | `.git` **可解析但仓无 HEAD**（`git init` 后未提交的 unborn 仓）：新谓词要求的是「`.git` **有效**」而非「**有 HEAD**」⇒ 照旧锁死到该仓 ⇒ `:144` 取不到 HEAD ⇒ **静默**（既有、非本轮引入、本仓不可达） | 沙箱**覆盖例**（附录 D.11）：`ws` 为 **unborn 仓**（`rev-parse --git-dir` → `.git` **成功**、`--short HEAD` → **空 / exit 128**）+ 页写错 SHA → 守卫 **静默（stdout 空）**；**对照**同一 `ws` 补一次提交后同页同 SHA → **BLOCK**（"当前是 `4563627`"）⇒ 该静默是**真 fail-open，非死代码**。**同源旁证**（附录 D.10）：`ws/.git` **无效**时新码 **BLOCK** ⇒ 新谓词**确实**会否决候选（与 D.11 合读：洞在"`--git-dir` 成功但无 HEAD"这一格）；**补记（`2026-10-10T07:58:04Z`，边界收紧，一句话）**：**仅真 unborn（`git init` 零提交）**属此形态——**断链 ref 不属**：把 `refs/heads/<br>` 改成**全零 SHA** 后 `rev-parse --short HEAD` 仍 **exit=0 / stdout `0000000`**（附录 D.12 的 B2c）⇒ 谓词的实际语义是"**能解析** HEAD"，断链 ref 仍解析得出、守卫照旧 **BLOCK**（D.12 的 G1）；且 **unborn 的首次提交即自愈** ⇒ 现实影响 ≈ 0。**原条目文字不删** | 接回目标布局时把谓词从「`.git` 有效」收紧为「**能取到 HEAD**」（或显式识别 unborn 并 emit 提示而非静默） | `未解除（潜在·本仓不可达）` |
| **`GAP-013`** | **环境使判据失效**：① `GIT_DIR` 环境变量被设时，任意含 `.git` 的候选都会让 `--git-dir` 成功 ⇒ 谓词被**中和**（**补记更正 · 方向**：不是"静默通道"，而是**下游 BLOCK（可见）**——谓词**恰好**不再否决本应被否决的候选；**严重度低于 ②**：判错但**看得见**。实测：同一空 `.git`，**无** `GIT_DIR` → **静默**（谓词**正确地**否决该候选，附录 D.12 的 E1），**设** `GIT_DIR` 指向真仓 → **BLOCK**（自证 `GIT_DIR` 注入存活，D.12 的 E2）。**真正的效应**：`GIT_DIR` **劫持每一处 `rev-parse`**（`:138`/`:145`/`:168`/`:169`）⇒ 守卫**去读另一个仓的 HEAD**；在本仓这不是主要效应——`$ws` 本就先中，`:138` 子句早被 `Test-Path` 短路）；② `git` 不在 `PATH` 时 `CommandNotFoundException` 是**语句终止错误、不受作用域 EAP 约束** ⇒ 抛在 `Where-Object` 里 ⇒ 外层 `catch { exit 0 }` ⇒ **守卫静默死亡、零提示**（而本脚本**改用 PowerShell 的初衷正是** PATH 问题） | 本轮沙箱实测：`GIT_DIR` 未设（`''`），故 ①② 均为**读码 + 机制推演**，非本机实跑；`:144`/`:164` 未套作用域 EAP 的 git 调用已按同因补齐（附录 D.10）。**补记（`2026-10-10T07:58:04Z`；上句对 ① 已被实测取代，不删)**：① 见上列更正 + 附录 D.12 的 E1/E2（**已实测**）；② **两向 + 归因齐备（已实测，附录 D.12）**：`F1` 正常 PATH → **BLOCK**（有 JSON）；`F2` 剥 `PATH` → **exit=0、无 JSON、stderr 空**（自证 `git` 不可解析而 `powershell` 仍可解析）；`F3` **插桩副本**（`catch {` 后插一行 stderr 标记）→ **`CAUGHT:CommandNotFoundException`** ⇒ **归因成立**：命令找不到的异常在 `Where-Object` 里抛出、冒到外层 `catch { exit 0 }` ⇒ 静默。**关键机制（一句）**：**作用域 `EAP='Continue'` 关不掉这条**——它只约束"原生命令写 stderr 的非零退出"，**不管"命令找不到"**；故 ② 与 `GAP-008` **失败面不同**，尽管症状同形 | ① 解析仓库前显式清空/忽略 `GIT_DIR`（或改用 `--git-dir` 显式参数）；② 缺 `git` 时 emit 明确的 `systemMessage`，不得静默 | `未解除（既有设计属性）` |
| **`GAP-010`** | **运行态排除只在本机生效**——排除规则写在 `.git/info/exclude`（**本地文件、不随仓库分发**）⇒ clone 的人拿不到它，一建 `memory.md` / `record.md` / 进度页就容易**被 `git add -A` 带进提交**。而 §5 又明令「不要再往 `.gitignore` 里加框架忽略规则」——**那条理由（框架在仓外）只成立于目标布局**，本仓是自托管布局，两条规则互相拉扯（D4） | 排除痕迹实测（附录 D.8）：`git status --porcelain --ignored` 把 `memory.md` / `record.md` / `project-progress.html` / `project/` 四行标 `!!`，**这正是排除的来源是 `info/exclude`、而非任何随仓分发的文件** | 随仓库分发 `.gitignore`（只排运行态）+ §5 连带纪律改为**按布局条件化**（目标布局不加 / 自托管加） | **`已解除`**（本轮；附录 D.8 实测） |
| **`GAP-011`** | **`README.md` 的「框架在仓库之外」叙述与自托管现状矛盾**（与 `GAP-010` 同源的 D4 错位）：该节称"放在仓库外使框架混进交付物**结构上不可能**、**不再依赖忽略规则是否写对**"——而本仓**就是**框架仓（`GAP-004` 已裁定「本仓即框架」），前提不存在；且这句与 `GAP-010` 刚落地的「运行态**由随仓库分发的 `.gitignore` 挡**」**直接冲突** | `README.md:261-263`（改前）：`**为什么把框架放在仓库之外**…不再依赖忽略规则是否写对。`（命令与输出见附录 D.9） | 改为**按布局成立**的表述：自托管布局下框架在仓内是**有意决定**，运行态改由 `.gitignore` 挡 | **`已解除`**（本轮；附录 D.9 实测） |
| **`GAP-014`** | **本仓自身是否适用十环门禁**——本仓对 04（构建）与 06–10（观测 / 排障 / 恢复 / 复盘 / 自动化）**无任何对应物**；两种读法后果不同：**(a)** 十环约束的是**采用本框架的项目**，本仓作为**模板**只需满足框架自举那几条 ⇒ 本仓不受十环约束；**(b)** 十环**也**约束本仓 ⇒ **本仓当前在 04 与 06–10 一律不通过** | `Test-Path` 六项全 `False`（附录 B.6）：`Dockerfile` / `.github` / `deploy` / `docs/adr` / `docs/changes` / `backend/migrations` | 人工裁定 (a) 或 (b)；若裁 (b)，本仓须补 04 与 06–10 对应物或显式登记为**永久豁免项** | `已解除` |

> **`GAP-013① / ②` 补记留痕（`2026-10-10T07:58:04Z`，原条目文字不删）**：① **方向已更正**（`GIT_DIR` 的效应是"谓词被中和 ⇒ **BLOCK**（可见）"，非静默；**严重度低于 ②**）并**改为实测**（E1/E2）；② **两向 + 归因齐备**（F1/F2/F3，含"作用域 `EAP` 管不了'命令找不到'"这一关键机制），**状态 `未解除（既有设计属性）` 准确，保留不变**。命令与 stdout 见**附录 D.12**。
> **独立复核放行收口（同轮，一句话）**：第一类（`:144` 的 EAP）**不能按"关上了失败通道"放行**——判为**防御性同形、未证明有牙**，**保留**但**理由已改正**（见第一部分）。`falsifier` 的 **`G5`** 猜测（`settings.json:8` 的调用行依赖 `$CLAUDE_PROJECT_DIR`，缺失时是"与 ② 同族的静默通道"）**已实测推翻**：缺该变量时 `powershell.exe` **报错退出**（路径退化成 `/.claude/hooks/…`），是**可见失败**；故**不登记为新缺口、不占号**（命令与 stdout 见附录 D.12 的 G5）。

> **附注（`GAP-009` 同源，一行）**：`AGENTS.md` 把 `$REPO` 指向 §0.0 的 `git rev-parse --show-toplevel`，而该命令**只向上找**——在**目标布局**（仓在 `project/` 子目录）下**报错**。
> 即 hook 的解析规则与文档声明的规则**在目标布局下不一致**（D4 类：两处不同成熟度的规则）。

**`GAP-008` / `GAP-009` 修复留痕**（`2026-10-09T15:51:54Z`，实现侧口径 · **放行待 `falsifier`**，命令与 stdout 另见 `record.md` 同轮行）：
- **`GAP-008`**：`:150` 双向前缀比对 → **两侧各解析为完整 commit id 再比**（`rev-parse HEAD` vs `rev-parse --verify --quiet "<sha>^{commit}"`，`$recorded` 先 `.ToLower()`）；正则同时改**大小写不敏感**（`[0-9a-fA-F]{7,40}`）。
- **`GAP-009`**：`:133` 候选判据由 `.git` **存在性**改为「存在 **且** `git -C <cand> rev-parse --git-dir` 成功」；**两处候选保留**。
- **关键实测（刻意的实现细节，不是美化）**：① **裸形式在本机 PS 5.1 下反而不工作**——`$ErrorActionPreference='Stop'` 把 git 写 stderr 的**非零退出**升格为**终止错误**，被外层 `catch { exit 0 }` 吞掉 → **又回到静默**（`--git-dir` 那条实测 C10 = 静默）。故**新增的两处 git 调用各自套了作用域内 `$ErrorActionPreference='Continue'`**（`--verify` 处另加 `--quiet`）。② **`$recorded.ToLower()` 在本机 git 2.49.0 下是否必需未能证伪**——`rev-parse --verify "AD4E6C8^{commit}"` **本来就成功**（不区分大小写），保留它只为对 git 内部 hex 口径**显式归一**。

**`GAP-008` 二次修复留痕**（`2026-10-09T16:03:11Z`，实现侧口径 · **放行待 `falsifier`**）：**首修已被独立复核击穿**——`falsifier` 设计的 **T2**（页写一个**存在的非 commit 对象** id，如 `HEAD^{tree}` 的 40 位）实测**静默**，本该 BLOCK。**根因**：`:161` 的 `--verify "<sha>^{commit}"` 在对象类型不符时失败，**`--quiet` 挡不住**——外层 `Stop` 把 git 写 stderr 的非零退出升格为终止错误，被最外层 `catch { exit 0 }` 吞成静默；**同 `:136-139`，上一轮只修了那一处、漏了这里**。**本次**给 `:161` 套上同形的**作用域内 `$ErrorActionPreference='Continue'`**（`:160` 的 `rev-parse HEAD` 不动——此处仓库已校验过）。
> **`GAP-008` 边界（`falsifier` 指出，一行）**：正则 `{7,40}` **假定对象 id ≤ 40 位**；`--object-format=sha256` 的仓（**64 位** id）下**即使页面写的是完全正确的 SHA 也永不匹配** → 走「无标记静默」（**永久静默**）。本仓为 **sha1，不影响**；该边界**非本次引入**。

**`GAP-002` 残余（已接受的代价）**：**指针指向不存在的页名**时仍静默——它与"页确实缺失（尚未初始化）"在观测上**不可分**，故**不报**（理由见 `AGENTS.md` §5）；**缓解后新行为**：指针**存在但读不出页名**（空 / 全空白 / 不可读）→ emit `systemMessage`。

**`GAP-010` 解除留痕**：本仓新增**随仓库分发**的 `.gitignore`（只排运行态三行）；`AGENTS.md` §5 连带纪律改为**按布局条件化**（目标布局不加——框架在仓外，规则永不命中；自托管布局应当加，只排运行态，**不得**排交付物与框架源）；本机专属的 `project/` **仍**只走 `.git/info/exclude`，**不写入** `.gitignore`，并在文件内以注释写明该分工。实测见**附录 D.8**。
> **口径（一句）**：本条**不声称守卫类"有牙/无牙"**——`.gitignore` 是**声明式**规则，其证据形态是 `git check-ignore -v` 与 `git add -A --dry-run` 的**真实输出**（D1：「读到才算」），**不是**负向注入（`AGENTS.md` §5「跑两个用例」那条纪律的**范围是进度页守卫脚本**，不适用于本文件）。**已接受的代价**：进度页改名后 `.gitignore` 里那一行会**静默失效**（旧规则不命中，但不会有任何报错）——已在文件内注释中写明"改名请同步这一行"。

**`GAP-011` 解除留痕（一行）**：`README.md:261-263` 的「为什么把框架放在仓库之外…不再依赖忽略规则是否写对」→「**自托管布局**：框架与交付物同在仓内是有意决定，运行态**改由随仓库分发的 `.gitignore`** 挡在提交之外」；**同段末句「忽略规则挡得住文件，挡不住叙述」保留未动**（它与本处无关，且成立）。实测见**附录 D.9**。

**`GAP-006` 改判留痕（一行，`2026-10-10T07:14:01Z`）**：门禁矩阵**全环启用**（01–10 尽为硬门禁，`AGENTS.md` §2）后，"无对应物"由『**不适用**』改判为『**未满足 ⇒ 阻断**』——原表头 `AGENTS.md` §7 的「该环无对应物」免罪口径同轮取消。本仓**无 CI / 合约 / 前端 / 容器对应物**（`Test-Path .github` → `False`、`Test-Path Dockerfile` → `False`，本轮实测），故该环当前**不通过**。**原条目文字不删**（证据链）；状态列由 `不适用（该环无对应物）` 改为 `未解除`。**注**：本表头部「状态取值」仍列 `不适用（该环无对应物）` 一项——新口径下**已无使用场景**，保留仅为不改动历史条目。
> **上句已被取代（补记，不删）**：`2026-10-10T07:15:44Z` 已从表头**状态取值枚举中删除该旧值**并写明废止——保留它会让"枚举"与"正文"两处不同成熟度（D4）。

**`GAP-014` 登记留痕（一行，`2026-10-10T07:15:44Z`）**：本条**只登记争议，不预设结论**。**留痕**：当前**保守口径**已在生效——`GAP-006` 已按读法 **(b)** 改判为 `未解除`；故**在裁定前，本仓视为未通过 04 与 06–10**。**证据**见附录 B.6（六项 `Test-Path` 实测）。

**`GAP-014` 解除留痕（一行，`2026-10-10T07:20:14Z`）**：人工裁定 **(a)**——十环门禁约束**采用本框架的项目**，**本仓为模板、不受十环约束**；故本仓对 04 与 06–10 的「无对应物」**不是缺口**。边界同轮在 `AGENTS.md` §2 与 `README.md` §四写清：本仓**仍受四大纪律（D1–D4）与机械守卫约束**，免除的**只是十环流水线门禁**。**原条目文字不删**（证据链）；上一条「登记留痕」**保留不删**，其结论由本行取代。

**`GAP-006` 解除留痕（一行，`2026-10-10T07:20:14Z`）**：**同因**——(a) 裁定后，**本仓不受十环约束**，"无对应物"在本仓**不构成缺口**。**原条目文字不删**（证据链）；状态列由 `未解除` 改为 `已解除`。上一条「改判留痕」（`07:14:01Z`）**保留不删**，其结论（按读法 (b) 判 `未解除`）由本行取代；表头「状态取值」的废止**理由**同轮改按**适用对象**分述（见 `:16`）。

**`GAP-003` / `GAP-004` 解除留痕**：两条动作**均已落地**，实测见**附录 D.3 / D.4**。**D3 判据不得自审**——改判据者（实现方）不得自放行，故 `GAP-003` 的「`已解除`」是**实现侧口径**，独立复核须**另派只读方**（`falsifier`）补记。**不删原条目**：已发生的事实是**证据链**，不是待办事项。

**`GAP-001` 缓解留痕**：① `.claude/agents/ssot-scribe.md` 的 `tools:` 改为 `Read, Write, Edit, Grep, Glob, PowerShell`（**只列本机实测名**，不再同列 `Bash`），同处注释写明**换机须按实测改**；② `falsifier.md` / `gate-auditor.md` 仍为 `Read, Grep, Glob`（**未加任何 shell**）。**残余（故标"已缓解"非"已解除"）**：**声明与挂载不一致时仍不报错**（harness 行为，本框架改不动）；核验**靠人工规程**（附录 C.1），**不是机械判据**——没人跑 C.1 时，写错的名字会**一如既往地静默**。

**`GAP-005` 最小锚（未解除 · 部分缓解）**：**每次代跑，总控必须在运行态记录追加一行**（**命令原文 + 真实 stdout 摘要**）——据此可审计：派发的只读角色数 vs 代跑行数，缺代跑会**对不上账**。**局限（不得读成"已解决"）**：① **非实时强制**（harness 层无钩子，只能事后发现）；② 判据**依赖总控自己写那一行**——不写时「**没代跑**」与「**没派过只读角色**」都表现为无行，**不可分**；③ 锚的痕迹**在本台账之外**（运行态记录不随本仓分发），故本条**只登记"要求"**，审计须在运行态记录所在工作区做——**不声称台账自包含**。

**`GAP-007` 修复留痕**：`.claude/hooks/check-progress.ps1` 的 `$repo` 候选**顺序对调**为 `@($ws, (Join-Path $ws 'project'))`，**保留两处候补**（fail-closed 脚本的回退不得删）。**顺带抓到一处文实不符**：文件头早已写「workspace root **always wins** if it holds `.git`」，而代码先把 `project/` 排在前面（**头注释描述的是修好之后的行为，代码没兑现**）；本次把代码改到与头注释一致并重写该处行内注释。改后逐案复跑见**附录 D.6**。

**守卫边界留痕（`GAP-007` / `008` / `009`）**：**`GAP-007` 已独立放行**——`falsifier` 设计攻击、总控代跑，**两方向实测**（附录 D.7）：**T1**（`project/` 内 `git init` 空仓 + 页写错 SHA → **BLOCK**，未被内层仓劫持）+ **T10**（移除 `project/` + 页写错 SHA → **BLOCK**）。
**`GAP-008` / `GAP-009` 为两条新边界**（证据同 D.7 的 T5 / T3）。**`GAP-008` 的边界（必须读，否则会被读成严重漏洞）**：**正常写作流程不会产生它**——页要么写 **7 位真短 SHA**、要么写 **40 位真全 SHA**，触发前提是"**页已被写错**"，即守卫本要抓的那种状态；故列为**已知边界**，**不是回归**。**`GAP-009` 如实标"潜在、当前不可达"**：`falsifier` 预测"静默"，**实测 T3 为 BLOCK，预测被推翻**；该洞仅**目标布局**可达，且属 `:133` 的**既有性质，非本轮引入**。
> **本段已被后续修复取代（补记，不删）**：`GAP-008` / `GAP-009` **均已改判为 `修复待独立放行`**（见上「修复留痕」）。**`GAP-008` 不再是"已知边界"**——上述「正常写作流程不会产生它」的论证**只说明它不是回归，不说明不可修**，本轮已修。**`GAP-009` 的"当前不可达"亦不再成立**：新增的沙箱实测（`ws/.git` 为**悬空 gitfile**，`project/` 为真仓）使该候选路径**可达**，旧判据实测**静默**、新判据**BLOCK**——即**洞可达、已修、待独立放行**。

**`GAP-009` 解除留痕（一行，`2026-10-09T16:31:03Z`）**：**沙箱独立放行**——本仓 `$ws` 恒有效且 `Select-Object -First 1` 使 `project/` 侧**连谓词都不求值** ⇒ **新旧判据在本仓逐字节相同**（无输入能使二者分叉），故放行**只能**在沙箱完成；沙箱结果：判别例1（空目录）/ 例2（悬空 gitfile）**新码 BLOCK**、**旧码 `c0d828e` 同布局静默**、反向对照（无 `.git`）**旧码 BLOCK** ⇒ 洞可达、新码有牙（附录 D.10）。**原条目文字不删**（证据链）。

### D.12 `GAP-012` / `GAP-013` 独立复核（`falsifier` 设计攻击 · 总控代跑；`2026-10-10T07:58:04Z`，沙箱）

**口径**：攻击清单由**只读方** `falsifier` 设计、命令由**总控代跑**（只读围栏下无 shell，见 `GAP-005`）——同 D.7，即 D3「判据不得自审」的落地。**以下读数由台账维护方在本机 `%TEMP%` 沙箱逐案复跑**，与代跑读数一致。**本仓进度页未被触碰**（探针读数见本节末）。

**A 组：`:144`（`GAP-012`）的 EAP 是否真有牙——`falsifier` 在 `catch {` 后插一行 stderr 标记后实测。**

```
A1 (带作用域 EAP)  unborn + 错 SHA  -> stderr 空                              exit=0
A2 (裸形式)        unborn + 错 SHA  -> stderr: CAUGHT:RemoteException         exit=0
A3 (带作用域 EAP)  同一 ws 补 1 提交 -> BLOCK（"当前是 823d76d"）             exit=0
A4 (裸形式)        同一 ws 补 1 提交 -> BLOCK（"当前是 823d76d"）             exit=0
   rev-list --count HEAD = 1   <- 自证已提交，非 unborn
```

**读法（三条）**：① **`:144` 的 EAP 是惰性的**——unborn 输入下**带** EAP **静默**（A1）、**裸**形式在同输入下 **`CAUGHT:RemoteException`**（A2），而**两者落点同形**（都到 `exit 0` 静默：裸形式抛→外层 `catch`；带 EAP→`$head` 空→下一行 `exit 0`）。**未插桩**复跑同结论：两形式均 **stdout 空 / exit=0**。② **A2 的抛出是故障引起的，不是结构性**——同一裸形式在**健康仓**上 A4 **BLOCK**（有 JSON）⇒ 该抛出只由 unborn 触发。③ **`:167` 不可证伪**：`:145` 成功 ⟹ HEAD 可解析 ⟹ `:167` 不会失败（除非两次 git 调用之间 HEAD 被改——TOCTOU，沙箱造不出稳定复现）⇒ **该处无法按其"同因"注释声称的方式被击穿**。

**B 组：`GAP-012` 的边界——断链 ref 不属此形态。**

```
B2c  refs/heads/master 写成 40 个 0（直接写 ref 文件）
     git rev-parse --short HEAD -> stdout "0000000"   exit=0     <- 仍【解析得出】
G1   同一输入 + 页写 1111111 -> BLOCK（"当前是 0000000"）
     V3  对照：ref 指向不存在的【非零】sha -> rev-parse "1111111" exit=0 也 BLOCK
```

**读法**：谓词的实际语义是「**能解析** HEAD」，**不是**「HEAD 指向真提交」——断链 ref 照旧解析、守卫照旧 BLOCK ⇒ `GAP-012` 的覆盖**仅真 unborn**。
> ⚠️ **复现陷阱（一行，实测踩过）**：`git update-ref refs/heads/<br> <40 个 0>` **会删除该 ref**（退化成 unborn），**造不出**断链——`rev-parse --short HEAD` 得 **空 / exit 128**。要造断链须**直接写 ref 文件**。误用会把 B2c 复现成 `GAP-012` 的那些读数。

**E 组：`GAP-013①`（`GIT_DIR`）的方向。**

```
E1  ws/.git = 空目录，无 GIT_DIR  -> (stdout 空) exit=0        <- 谓词【正确地】否决该候选
E2  同一空 .git，GIT_DIR = 真仓   -> BLOCK（"当前是 0b6c54c"）  <- 0b6c54c 是【另一个仓】的 HEAD
```

**读法**：中和的形态下**下游是 BLOCK（可见）**，不是静默——谓词**恰好**不再否决本应被否决的候选；`reason` 里的"当前是"是**另一个仓**的 HEAD ⇒ `GIT_DIR` **劫持 `rev-parse`** 这一机制**被直接观测到**。**严重度低于 ②**：判错但**看得见**。在本仓**非主要效应**——`$ws` 本就先中，`:138` 子句早被 `Test-Path` 短路。

**F 组：`GAP-013②`（`git` 不在 `PATH`）——两向 + 归因。**

```
F1  正常 PATH                  -> BLOCK（有 JSON）                     exit=0
F2  剥 PATH                    -> stdout 空、【stderr 也空】           exit=0
    F2a 同环境探针             -> git: CommandNotFoundException（powershell 仍解析）
F3  剥 PATH + 插桩副本         -> 【stderr】CAUGHT:CommandNotFoundException
```

**读法（两条）**：① **归因成立**——异常抛在 `Where-Object` 的谓词里、冒到外层 `catch { exit 0 }` ⇒ 静默，且**连 stderr 都没有**（F2 与 F3 的唯一差别就是那行插桩）；② **关键机制**：作用域 `EAP='Continue'` **关不掉这条**——它只约束「原生命令写 stderr 的非零退出」，**不管「命令找不到」**（后者是 `CommandNotFoundException`，与 `GAP-008` 的失败面**不同**，尽管症状同形）。

**G5 组：`CLAUDE_PROJECT_DIR` 猜测——已推翻。**

```
G5-A  .claude/settings.json:8 的调用行，变量为空 -> powershell.exe 报错：
      "The argument '/.claude/hooks/check-progress.ps1' to the -File parameter does not exist."
      exit = -196608（两次复跑一致；非 0）
G5-B  同一行、变量解析为真实路径（对照）-> guard 正常运行，stdout 空，exit = 0
```

**读法**：缺该变量时是**可见失败**（非零退出 + 明确报错），**不构成"与 ② 同族的静默通道"** ⇒ `falsifier` 的猜测被实测推翻，**不登记为新缺口、不占号**。
> **口径（一句）**：`CLAUDE_PROJECT_DIR` 在本机 shell **本就未设**（`$env:CLAUDE_PROJECT_DIR` 读数为空），而 `G5-B` 用的是**路径替换后的命令**、非变量注入，故本组的对照是「**空替换 vs 真路径替换**」；**未验证** harness 注入该变量时的行为。

**本仓只读探针 + 清理复核**（无残留）：

```
guard stdout = []  exit=0            <- 页与 HEAD 一致 ⇒ 非净回归
ws = D:\MyDocuments\ai-collaboration-framework     short HEAD = 9ce688b
pointer bytes  = 112,114,111,106,101,99,116,45,112,114,111,103,114,101,115,115,46,104,116,109,108,10
pointer SHA256 = BF4B689955CB250B7959FFB1AF383944D35D0D426750FC39B9BAA0F2E6B2ADE1   （与 D.6/D.10 一致）
leftover d12* sandbox dirs = 0
```

**放行结论（本轮的收口，一句话）**：第一类（`:144` 的 EAP）**不能按"关上了失败通道"放行**——判为**防御性同形、未证明有牙**，**保留**但**理由已改正**（见 `:144` 注释）。**本节各组的执行者即台账维护方**（代跑），按 D3 **不构成**对 `falsifier` 的独立放行替代——**攻击由 `falsifier` 设计**这一点满足"设计者 ≠ 写守卫者"，但**放行的最终签署仍应由只读方给出**。

## 二、附录 A · 登记前检索留痕（**撞车检查**）

`AGENTS.md` D4：**登记新编号前必须先全仓检索**——**撞车比漏登记更糟**。以下为**首次登记前**在仓库内实跑的检索，命令与真实输出原样抄录。

```
$ git grep -n "GAP-"
AGENTS.md:149:- 标识符严格定义：`ADR-`（架构决策）· `MIG-`（数据库迁移）· `GAP-`（质量缺口）· `INC-`（线上故障）· `DEFER-`（延期债务）。
AGENTS.md:456:| `GAP-` | 质量缺口 | `"$REPO"/docs/`（唯一台账） | **任何"还没做"必须在此，否则它不存在** |
README.md:70:标识符严格定义：`ADR-`（架构决策）· `MIG-`（数据库迁移）· `GAP-`（质量缺口）·
prompts/全生命周期工程质量总监与系统架构师.md:16:   - 全局标识符严格定义：ADR-（架构决策）、MIG-（数据库迁移）、GAP-（质量缺口）、INC-（线上故障）、DEFER-（延期债务）。
prompts/全生命周期工程质量总监与系统架构师.md:30:- 07 排障：准出 = 故障复盘具备秒级时间线与对照实验 + 根因直接回写产品与架构文档 + 改进项全部转为 GAP-xx 台账。
exit=0
```

**5 处命中全部是"标识符定义/规则陈述"，无任何已用编号。** 同法检索 **`GAP-[0-9]`（带数字的具体编号）** → **零命中**（`exit=1`）。
> `exit=1` 是 `git grep` 的"零命中"约定，不是错误。故首次登记从 `GAP-001` 起，**不撞车**。

> ⚠️ **口径声明（一句）**：`git grep` **只搜已入库文件**（看不到未入库与被 `.gitignore` 掉的路径），故零命中**不等价于**全盘 `Grep` 的零命中——两种口径的差异**必须明说**；本次检索时本文件尚未入库，不影响结论。

### A.2 新增 `GAP-008` / `GAP-009` 的登记前检索（2026-10-09，实测）

```
$ git grep -n "GAP-[0-9]" -- AGENTS.md README.md CLAUDE.md .claude    # 去掉本台账后的命中：
.claude/hooks/check-progress.ps1:25:# IS the repo, so the framework files sit in the repo by design (GAP-004: the
.claude/hooks/check-progress.ps1:105:    # silent fallback this replaces is the GAP-002 defect.
.claude/hooks/check-progress.ps1:146:    # PREFIX, not equality (GAP-003): the page may carry the 40-char SHA or a
AGENTS.md:313:> **本仓即框架**（人工裁定，见 `"$REPO"/docs/ledger.md` 的 `GAP-004`）：本仓库**就是框架自身的仓**，
AGENTS.md:402:> 残余风险见台账 `GAP-002`。
README.md:163:> 这是**显式分工**，不是降级；但它引入了一条新缝隙，**已登记为 `GAP-005`**
exit=0

$ git grep -n "GAP-008"   -> （无输出） exit=1     ← 零命中
$ git grep -n "GAP-009"   -> （无输出） exit=1     ← 零命中
$ git grep -n "GAP-010"   -> （无输出） exit=1     ← 零命中
```

**读法**：**除本台账外**共 **6 行**命中，**全部是引用既有编号**，最大号只到 `GAP-005`；本台账当时登记到 `GAP-007`。三条拟用编号均**零命中**（`exit=1` 是零命中约定，不是错误）⇒ 新号从 **`GAP-008`** 起，**不撞车**（D4）。

### A.3 新增 `GAP-010` 的登记前检索（2026-10-09T16:21Z 前后，实测）

```
$ git grep -n "GAP-[0-9]"                                  # 全仓（含本台账）
（75 行；其中 67 行在本台账内）

$ git grep -n "GAP-[0-9]" -- AGENTS.md README.md CLAUDE.md .claude    # 去掉本台账后的命中：8 行
.claude/hooks/check-progress.ps1:25:# IS the repo, so the framework files sit in the repo by design (GAP-004: the
.claude/hooks/check-progress.ps1:105:    # silent fallback this replaces is the GAP-002 defect.
.claude/hooks/check-progress.ps1:133:    # (GAP-009). The scoped EAP keeps git's stderr off the outer catch, which
.claude/hooks/check-progress.ps1:150:    # to the "no HEAD marker" silence (GAP-008).
.claude/hooks/check-progress.ps1:155:    # Resolve both sides to FULL commit ids and compare those (GAP-008): any two
AGENTS.md:294:> **本仓即框架**（人工裁定，见 `"$REPO"/docs/ledger.md` 的 `GAP-004`）：本仓库**就是框架自身的仓**，
AGENTS.md:380:> 残余风险见台账 `GAP-002`。
README.md:163:> 这是**显式分工**，不是降级；但它引入了一条新缝隙，**已登记为 `GAP-005`**
exit=0

$ git grep -n "GAP-010" -- AGENTS.md README.md CLAUDE.md .claude     # 除本台账外
（无输出）  exit=1     ← 零命中
```

**读法**：**除本台账外** 8 行命中，**全部是引用既有编号**（`004`·`002`·`009`·`008`·`008`·`004`·`002`·`005`），**最大号只到 `GAP-009`**；本台账自述的最大号亦为 `GAP-009`（`:10`）。拟用编号 `GAP-010` 在**别处零命中**（`exit=1` 是零命中约定，不是错误）⇒ 新号取 **`GAP-010`**，**不撞车**（D4）。
**口径（一句）**：本次检索**含本台账自身**（故 75 行），与登记前**排除本台账**的那次（8 行）**范围不同**，两者**不可直接比较**；排除本台账只为看清"**别处**有没有占号"，**并未**缩小检索范围。

### A.4 新增 `GAP-011` 的登记前检索（`2026-10-09T16:24:57Z`，实测）

```
$ git grep -n "GAP-011"                       # 登记前，全仓
（无输出）  exit=1     ← 零命中（`exit=1` 是零命中约定，不是错误）

$ git grep -n "GAP-011"                       # 登记后复核，全仓
docs/ledger.md:10:| 已用 `GAP-` 最大号 | `GAP-011` |        <- 本台账自述
docs/ledger.md:30:| **`GAP-011`** | …                            <- 本台账条目
docs/ledger.md:48:**`GAP-011` 解除留痕（一行）**…
exit=0
$ git grep -n "GAP-011" -- AGENTS.md README.md CLAUDE.md .claude    # 除本台账外
（无输出）  exit=1
```

**读法**：登记前全仓**零命中** ⇒ 该号未被占用，**不撞车**（D4）；登记后命中**全部落在本台账内**，别处仍零命中。拟用编号的取号依据是当时台账自述的最大号 `GAP-010`（本轮先登记，`GAP-011` 紧随其后）。

### A.5 新增 `GAP-012` / `GAP-013` 的登记前检索（`2026-10-09T16:31:03Z`，实测）

```
$ git grep -n "GAP-01[2-9]" -- . ':!.claude/hooks/check-progress.ps1'   # 全仓，排除本轮新写的两行注释
（无输出）  exit=1     ← 零命中（`exit=1` 是零命中约定，不是错误）

$ git grep -n "GAP-012" -- . ':!.claude/hooks/check-progress.ps1'
（无输出）  exit=1
$ git grep -n "GAP-013" -- . ':!.claude/hooks/check-progress.ps1'
（无输出）  exit=1
```

**读法**：`GAP-012` / `GAP-013` 在**别处零命中** ⇒ 未占用，**不撞车**（D4）；取号依据是当时台账自述的最大号 `GAP-011`（`:10`）。**口径（一句）**：排除 `check-progress.ps1` 是因为该文件刚被本轮加了 `GAP-012/013` 两行**新注释**——不排除则命中是**自证**，说明不了"别处有没有占号"；**并未**缩小检索范围。

### A.6 新增 `GAP-014` 的登记前检索（`2026-10-10T07:15:44Z`，实测）

```
$ git grep -n "GAP-01[4-9]"
（无输出）  exit=1     ← 零命中（`exit=1` 是零命中约定，不是错误）
```

**读法**：`GAP-014` 全仓**零命中** ⇒ 未占用，**不撞车**（D4）；取号依据是当时台账自述的最大号 `GAP-013`（`:10`）。**未排除任何路径**（本次无刚写入的新注释需要规避）。

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

## 四、附录 C · 可复跑的核验命令

### C.1 `GAP-001` 的工具挂载核验（**改任何角色的 `tools` 后必跑**）

1. 派一个子代理，令其**自报可用工具的确切名字**，并跑 `Get-Location; echo probe-ok`。**判据**：`probe-ok` 出现 **且** `LASTEXITCODE=0` → 该会话**确实有 shell**，工具名以**自报清单**为准（本机实测为 `PowerShell`）。**名单是声明，挂载才是事实；两者不一致时无声。**

### C.2 进度页守卫的用例（**改页名后必跑**）

```powershell
# 用例① 缺页（页面不存在）-> 必须【静默 exit 0】（"尚未初始化"，放行是对的）
powershell -NoProfile -ExecutionPolicy Bypass -File .claude/hooks/check-progress.ps1
# 用例② 注入错误 SHA（页面【存在】）-> 必须 emit {"decision":"block"}
powershell -NoProfile -ExecutionPolicy Bypass -File .claude/hooks/check-progress.ps1
# 用例③ 指针文件存在但为空 -> 必须 emit {"systemMessage":…}   （GAP-002 缓解后的新分支）
# 用例④ 页面写 40 位完整 SHA（同一提交）-> 必须【静默】        （GAP-003 修复后的回归）
# 用例⑤ 在 project/ 下造一个假 .git，同一页面同一错 SHA -> 必须**仍然** emit block
#        （GAP-007 修复后的回归：内层空仓不得劫持守卫）
```

> ⚠️ **必须同时跑②与①**：只验「一致时静默」**不够**（D3）——它区分不了「正常」与「死代码」；缺页分支与死代码**在观测上等价**（`GAP-002`），**只有 ② 仍有牙，才能反推 ① 的静默是"确无判据"。**
> 跑完**务必清理**临时页面，并复核指针文件字节未被改动（`status --porcelain` 应干净）。**实测读数见附录 D.3 / D.6**。

### C.3 本台账自身的登记规程

1. **先检索** `git grep -n "GAP-[0-9]"`，确认拟登记项未被既有编号覆盖；
2. **取号** = 本文件「已用 `GAP-` 最大号」+1，**不得复用、不得跳号**；
3. **写一条**：补齐「缺口 / 证据 / 解除条件 / 状态」四列；
4. **同步快照**：更新顶部「快照时间 / HEAD / 入库文件数 / 最大号」；
5. **改状态**：解除时改状态并**补一行留痕**，**不删原条目**。

## 五、附录 D · 守卫实测（**真实 stdout，2026-10-09 由台账维护方实跑**）

> **口径声明（一句）**：本节输出均为**本次实跑**所得，非转述、非推断；但**执行者即实现方**——按 D3「判据不得自审」，这**不构成**独立放行，独立复核须**另派只读方**。

**D.1 攻击 A —— 指针指向不存在的页名（`GAP-002` 实证）**。**前置**：进度页**存在**，状态条写错 SHA `0000000`（当时 HEAD 为 `3b9030f`）。

```
$ # 把 .claude/progress-page.txt 改为 'no-such-page.html'
$ powershell -NoProfile -ExecutionPolicy Bypass -File ".claude/hooks/check-progress.ps1"
（stdout 空）
guard exit=0

--- 对照：指针还原为真实页名 project-progress.html，同一页、同一错 SHA ---
{"decision":"block","reason":"进度页落后于仓库：project-progress.html 记录的 HEAD 是 0000000，而当前是 3b9030f。…"}
```

**读法**：同一页面、同一错 SHA，**只因指针里的页名不同**（静默放行 vs 正常阻断）⇒ **指针文件是唯一开关**，一错则两分支**同时失效**（`GAP-002` 成立）。

### D.2 攻击 B —— 页面写 40 位完整 SHA（`GAP-003` 实证，**修复前**）

```
$ Set-Content project-progress.html -Value "<div>head <b>3b9030ff76f8e56dc787658578b801795c6b6f72</b></div>"
$ powershell … -File ".claude/hooks/check-progress.ps1"
{"decision":"block","reason":"…记录的 HEAD 是 3b9030ff76f8e56dc787658578b801795c6b6f72，而当前是 3b9030f。…"}
```

**读法**：页面写的 SHA 与 HEAD **指的是同一个提交**，守卫却判「落后」⇒ **字符串全等是误报源**。

**D.3 修复后复跑（`GAP-003` 解除 / `GAP-002` 缓解的实证）**。修复 `.claude/hooks/check-progress.ps1` 后，逐案复跑（页存在时皆用默认页名）：

```
CASE-1 页不存在 + 指针正常                       -> (empty stdout) exit=0   静默 ✔
CASE-2 指针存在但为空 + 页不存在                 -> {"systemMessage":"进度页指针异常：…"} ✔
CASE-3 指针存在但为空 + 页存在(SHA错)            -> {"systemMessage":"进度页指针异常：…"} ✔
CASE-4 指针存在但全空白                          -> {"systemMessage":"进度页指针异常：…"} ✔
CASE-5 页面写 40 位完整 SHA（同一提交）          -> (empty stdout) exit=0   GAP-003 已修 ✔
CASE-6 页面写错误 7 位 SHA                       -> {"decision":"block",…}   有牙 ✔
CASE-7 指针指向不存在的页名                      -> (empty stdout) exit=0   已接受的代价 ✔
CASE-8 指针文件缺失 + 页存在(SHA错)              -> {"decision":"block",…} ✔
CASE-9 指针文件缺失 + 页不存在                   -> (empty stdout) exit=0   ✔
```

**清理复核**（防"测试留下残留"变成新的静默漂移）：

```
pointer bytes   = 112,114,111,106,101,99,116,45,112,114,111,103,114,101,115,115,46,104,116,109,108,10
pointer SHA256  = BF4B689955CB250B7959FFB1AF383944D35D0D426750FC39B9BAA0F2E6B2ADE1
page exists     = False
git status ptr  = ''            （空 = 指针未被改动）
```

**读法**：`CASE-6` 仍有牙 ⇒ `CASE-1/7/9` 的静默是**确无判据**，而不是"脚本死了"；指针文件**逐字节一致**（无 BOM、无 CRLF）⇒ 未留残留。

> **一次真实险情（如实记录）**：首次复跑时测试脚本自身的 `WriteAllText` 重载**报错中断**，指针文件**停在「空」状态**；已按台账快照的字节序列**逐字节还原**并复核 SHA256 与 `git status`（如上）。**教训**：破坏性用例**必须先备份原值，且清理路径不得在崩溃点之后**——否则"测试"本身就成了新的静默漂移源。

**D.4 `GAP-004` 解除了什么（人工裁定：采纳"本仓即框架"）**。裁定后 `AGENTS.md` 的改写（§0.0 · §5 入库策略 · §5 推送前必做第 2 条 · §0.1）：

| 处 | 改前 | 改后 |
| --- | --- | --- |
| §0.0 | 「框架的**目标布局**是仓库为子目录…自托管布局下『框架在仓库之外』**不成立**」+ 独立的「仓库的识别方式」小节 | 一句话：**仓库 = 含 `.git` 的目录，名字任意；工作区根自身含 `.git` 即仓库本身**（自托管布局），`$REPO` 由 `git rev-parse --show-toplevel` 解析 |
| §5 入库策略 | 框架文件与运行态 = **❌ 不入仓库**；「**保障方式：位置，而非忽略规则**…结构上不可能」 | 两类 = **⬜ 按布局而定**；「**本仓即框架**…同在仓库内是**有意决定**」，两类布局差异收为**一句话** |
| §5 推送前第 2 条 | 「**框架文件围栏**…必须在推送范围内**不存在**」 | 「**推送范围的核对**…框架文件**在**范围内，这是有意决定；仍要核实而非假定」 |

**不拆仓库。** 残余影响（**须继续跟踪**，不随本条关闭）：按 §5 判据，`record.md` / `memory.md` / 进度页等**运行态**在自托管布局下亦属入库，是否**随仓库外发**由发布范围决定——`GAP-005` 与 §5 连带纪律仍指向此处。

### D.5 `GAP-001` 缓解的实测（2026-10-09）

```
$ git -C "$REPO" grep -n "^tools:" -- .claude/agents
.claude/agents/falsifier.md:4:tools: Read, Grep, Glob
.claude/agents/gate-auditor.md:4:tools: Read, Grep, Glob
.claude/agents/ssot-scribe.md:4:tools: Read, Write, Edit, Grep, Glob, PowerShell
```

**读法**：写方（`ssot-scribe`）只列**本机实测名** `PowerShell`，两个只读方**不含任何 shell**（机械只读，未被本次改动放松）。**残余未消**：名单与挂载不一致时**仍不报错**——故本行是 `已缓解（机制仍在）`，**不是** `已解除`；且**本行只是声明侧核对**，挂载实测须另派子代理执行（附录 C.1），**不得**据本行宣称"挂载已验证"。

### D.6 `GAP-007` 的实测：守卫的仓库解析与守卫自身（2026-10-09）

**① 当前布局解析到位**（`project/` 存在、但**无** `.git`）：

```
ws   = D:\MyDocuments\ai-collaboration-framework
repo = D:\MyDocuments\ai-collaboration-framework        <- 新序取到工作区根（自托管）
$ git -C <repo> rev-parse --short HEAD
ad4e6c8
```

**② 危险布局：`project/` 内含一个 `.git`。** 造一个**空** `.git` 目录，同一页面、同一错 SHA，复跑守卫：

```
NEW order (工作区根优先) resolves repo = D:\MyDocuments\ai-collaboration-framework
OLD order (project 优先)  resolves repo = D:\MyDocuments\ai-collaboration-framework\project
```

**③ "取不到 HEAD"单跑复现**（仓库外临时目录，用后即删）：`git init <tmp>` 后 `git -C <tmp> rev-parse --short HEAD` → **空输出、`exit 128`** ⇒ 守卫走到 `if (-not $head) { exit 0 }` ⇒ **静默放行**——与它正常时的静默**在观测上不可分**（即 `AGENTS.md` §8 那类漂移）。

**④ 修复后逐案复跑**（页面存在，逐案注入，`finally` 内逐字节还原）：

```
CASE-2 页存在 + 错 7 位 SHA            -> {"decision":"block",…}                     有牙 ✔
CASE-4 页存在 + 同提交 40 位完整 SHA   -> (empty stdout) exit=0                     静默 ✔
CASE-3 指针存在但为空                  -> {"systemMessage":"进度页指针异常：…"}     ✔
CASE-5 无指针文件 + 错 SHA             -> {"decision":"block",…}                     ✔
CASE-1 project/ 内含空 .git + 错 SHA   -> {"decision":"block",…}    GAP-007 修复后仍拦 ✔
```

**清理与完整性复核**（本仓 `project/` 下**不留** `.git`）：

```
pointer SHA256 = BF4B689955CB250B7959FFB1AF383944D35D0D426750FC39B9BAA0F2E6B2ADE1   （与攻击前一致）
pointer bytes  = 112,114,111,106,101,99,116,45,112,114,111,103,114,101,115,115,46,104,116,109,108,10
page SHA256    = 993B746055EE02F662C1895509C12B5E19AAE46AD8C1E93E00D17AF3FFDB3E04
project/.git removed = True
$ git status --porcelain
 M .claude/agents/README.md
 M .claude/agents/ssot-scribe.md
 M .claude/hooks/check-progress.ps1
 M AGENTS.md
 M docs/ledger.md
（无 ?? project/ —— 它已被 .git/info/exclude 挡在提交之外）
```

**读法**：`CASE-2/5/1` 仍有牙 ⇒ `CASE-4` 的静默是**确无判据**，不是"脚本死了"；指针文件**逐字节还原**、SHA256 与攻击前一致 ⇒ 无残留。

> **又一次真实险情（与 D.3 同一根因）**：清理代码**再次**踩坑——删掉指针后调 `Resolve-Path` 还原，**该 cmdlet 对不存在的路径直接抛错**，`WriteAllBytes` 未执行 ⇒ 指针一度**缺失**。**修法**：改用**绝对字面路径**重建。**教训升级**：D.3 的（"清理路径不得在崩溃点之后"）**不够**——**真正要守的是「还原步骤本身不得依赖被测对象当前的状态」**；fail-closed 的判据如此，**清理代码同样如此**。

**D.7 `GAP-007` 独立放行 + `GAP-008` / `GAP-009` 边界（`falsifier` 设计攻击 · 总控代跑）**。**口径**：攻击清单由**只读方** `falsifier` 设计、命令由**总控代跑**（只读围栏下无 shell，见 `GAP-005`）——此即 D3「判据不得自审」的落地：**设计攻击者不是写守卫的人**。

```
T1  在 project/ 内 git init（空仓：HEAD 空 / rev-parse exit 128）+ 页写 0000000
    -> BLOCK                       GAP-007 已修：未被内层空仓劫持
T10 移除 project/ + 页写 0000000
    -> BLOCK                       区分"改动正确"与"守卫已死"（D3 要求的反向对照）
T5  页写 ad4e6c8000000000000000000000000000000000（真前缀 ad4e6c8 + 假后缀）
    -> (stdout 空) 静默            GAP-008：双向前缀匹配放行伪造 SHA，实测复现
T3  建 project/.git（空目录）+ 页写 0000000
    -> BLOCK                       **推翻 falsifier 预测**：新序 $ws 先中，空目录不被咨询
                                   ⇒ GAP-009 仅在目标布局可达（潜在、当前不可达）
T6  页写 AD4E6C8  -> 静默          既定边界：正则 [0-9a-f] 不匹配大写（非本轮回归）
```

**还原复核**：指针 SHA256 = `BF4B6899…B2ADE1` **逐字节完好**；`project/` 仅剩 `README.md`，无残留。

**引 `record.md` 对应行**：`[2026-10-09T14:48:43Z]` 的 `T1` · `T10` · `T5` · `T3` · `T6` · `还原复核` 六行（运行态记录**不随本仓分发**，故本附录将其**命令与读数**抄录如上，使结论**可复核**）。**D.6 的"实现侧口径"至此闭合**：`GAP-007` 的独立放行**已取得**。

### D.8 `GAP-010` 的证据：运行态排除的来源，以及它随分发而变（2026-10-09T16:23Z 实跑）

**以下整段可在 clone 的检出里直接跑**（只读）。**采集时点**：本轮改动**尚未提交**，故 `git status` 显示 `?? .gitignore`——**提交后已复跑**，读数见 D.9。

```
$ git check-ignore -v memory.md record.md project-progress.html project
.gitignore:3:memory.md	memory.md
.gitignore:4:record.md	record.md
.gitignore:5:project-progress.html	project-progress.html
.git/info/exclude:15:project/	project
exit=0

$ git add -A --dry-run
add 'AGENTS.md'
add 'docs/ledger.md'
add '.gitignore'
exit=0

$ git status --porcelain
 M AGENTS.md
 M docs/ledger.md
?? .gitignore

$ git status --porcelain --ignored
 M AGENTS.md
 M docs/ledger.md
?? .gitignore
!! memory.md
!! project-progress.html
!! project/
!! record.md

$ git ls-files | wc -l
17            （本轮尚未提交；提交后含 .gitignore 应为 18——首次 `git ls-files` 的迟滞，非缺口）
```

**读法（三条，各自可独立复核）**：

1. **排除来源已分家**：三个运行态文件由 **`.gitignore:3/4/5`** 命中——**这个文件随仓库分发**，clone 的人拿到同一套规则；`project/` 由 **`.git/info/exclude:15`** 命中——**本机专属**，**刻意不随分发**（别人的 fork 里未必有 `project/`，写进 `.gitignore` 就是"指不到东西的引用"）。
2. **`--dry-run` 有牙**：它会把**将要提交**的东西逐条列出——`memory.md` / `record.md` / `project-progress.html` **一条都没有出现**，而 `AGENTS.md`（框架源）、`docs/ledger.md`（交付物）、`.gitignore`（框架文件）**都在**。即：**该排的被排掉，该进的照常进**。
3. **`--ignored` 是必需的第二只眼**：单看 `--dry-run` **分不清**"被规则排除"与"碰巧不存在"（后者同样不出现）。`--ignored` 把四个名字显式标成 `!!` ⇒ 它们是**存在且被排除**，不是"没有"。**只跑前者会把"文件根本不存在"读成"围栏有效"**——正是 `AGENTS.md` §8 那类判据夹缝。

### D.9 `GAP-010` 提交后复测 + `GAP-011` 的证据（2026-10-09T16:25:43Z 实跑）

```
$ git rev-parse --short HEAD
8537671                                   <- GAP-010 的改动已提交
$ git ls-files --error-unmatch .gitignore
.gitignore        exit=0                  <- .gitignore 确已被跟踪（不再是 ??）

$ git check-ignore -v memory.md record.md project-progress.html project
.gitignore:3:memory.md	memory.md
.gitignore:4:record.md	record.md
.gitignore:5:project-progress.html	project-progress.html
.git/info/exclude:15:project/	project

$ git add -A --dry-run
add 'README.md'
add 'docs/ledger.md'                      <- 只剩本轮两处；三个运行态一个都没出现

$ git status --porcelain --ignored
 M README.md
 M docs/ledger.md
!! memory.md
!! project-progress.html
!! project/
!! record.md

$ git grep -n "为什么把框架放在仓库之外"    # 改后：旧叙述的活性引用应为零
docs/ledger.md:30:…（本条目按「改前」原样引用，非活性叙述）
docs/ledger.md:48:…（同上，留痕行）
exit=0
（`README.md` **不再命中** ⇒ 该叙述已从 README 清除，台账内两处是**刻意保留的改前引用**，符合"不删原条目"）
```

**读法**：① `.gitignore` 已随仓库分发（`ls-files` 命中），三个运行态仍由它排除、`project/` 仍由本机 `info/exclude` 排除 ⇒ **分工在提交后依然成立**；② `--dry-run` 只剩本轮**该提交的两处**，说明**该进的在、该排的不在**；③ README 的旧叙述**已零活性命中**，D.9 同时充当 `GAP-011` 的解除证据。

### D.10 `GAP-009` 沙箱独立放行 + `:144`/`:164` 补齐（`2026-10-09T16:31:03Z` 实跑）

**口径**：**攻击由 `falsifier` 设计、命令由总控在 `%TEMP%` 沙箱代跑**（本仓不可证伪——`$ws` 恒有效 + `Select-Object -First 1` 使 `project/` 侧**连谓词都不求值**，故新旧判据在本仓**逐字节相同**）。**以下为台账维护方在本机复跑的同构实验**，读数一致。

```
sandbox = C:\Users\Yotoha\AppData\Local\Temp\gap009-83e4601d
GIT_DIR env = ''                                     <- 环境未设，故 GAP-013① 非本机实跑
2-commit repo at <ws>/project  short SHA = 2421fd8   <- 非空自证
CASE1  ws/.git = EMPTY DIR            exit=0  stdout={"decision":"block","reason":"进度页落后于仓库：sandbox-progress.html 记录的 HEAD 是 0000000，而当前是 2421fd8。…"}
CASE2  ws/.git = DANGLING GITFILE     exit=0  stdout={"decision":"block","reason":"…而当前是 2421fd8。…"}
cleanup: Test-Path sandbox = False
```

**真仓只读探针**（未写任何文件）：

```
$ powershell -NoProfile -ExecutionPolicy Bypass -File .claude/hooks/check-progress.ps1
（stdout 空）  guard exit=0                          <- 页与 HEAD 一致 ⇒ 非净回归
ws             = D:\MyDocuments\ai-collaboration-framework
ws/.git exists = True
resolves to ws = .git                               <- 正序第一个候选即解析到工作区根
short HEAD     = 61f63de
```

**读法（三条）**：① 两例均 BLOCK，且 `reason` 里的"当前是"是**沙箱 `project/` 仓**的短 SHA ⇒ 证明守卫**真用了第二候选**，而旧码 `c0d828e` 在同一布局**静默**（反向对照「无 `.git`」旧码 **BLOCK** ⇒ 洞可达、旧码非死代码）；② 归因解剖：同一句 `rev-parse --git-dir`，作用域 `EAP='Continue'` → `NO-THROW`，**裸形式（继承 `Stop`）→ `THROWN`**——这正是 `:144` / `:164` 未设防的成因；③ 本轮按**同形**给 `:144` / `:164` 各套一层作用域 EAP（**只加 3 行，其余逻辑未动**，`:145` 的 `if (-not $head) { exit 0 }` 仍在原位）。**不得把本附录读成 `GAP-012` / `GAP-013` 已实测**——`GAP-012` 的覆盖实测见 **D.11**；`GAP-013` 在本机**环境未设**（`GIT_DIR=''`、`git` 在 PATH），属**读码推演**，状态**未解除**。

### D.11 `GAP-012` 的覆盖实测：unborn 仓致静默（`2026-10-09T16:31:03Z` 实跑，沙箱）

**为何另起一例**：D.10 的两例把 `ws/.git` 造成**无效**（空目录 / 悬空 gitfile），`rev-parse --git-dir` **失败** ⇒ 新谓词**正确地否决**该候选——那证明的是"**无效 `.git` 不被采纳**"，**不是** `GAP-012` 的输入（"`.git` **有效**但**无 HEAD**"）。故本节用**真 unborn 仓**（`git init` 后**零提交**）覆盖该格；`project/` 为两提交真仓（`d731b2c`）以保证旧码会锁到它。

```
sandbox = C:\Users\Yotoha\AppData\Local\Temp\gap012-1a5825d8
project/ real repo short SHA = d731b2c
ws is UNBORN repo?  git -C ws rev-parse --git-dir -> .git          <- 谓词所需：成功
ws HEAD (unborn)   rev-parse --short HEAD -> ''  exit=128          <- 但无 HEAD
CASE-U  ws = UNBORN repo (no commits), page SHA wrong   exit=0  stdout=[]

--- control: same ws now HAS 1 commit（加一次空提交，页面未动）---
CASE-C  ws = committed repo, same wrong page SHA        exit=0  stdout=[{"decision":"block","reason":"…记录的 HEAD 是 0000000，而当前是 4563627。…"}]
cleanup: Test-Path sandbox = False
```

**读法**：同一页面、同一错 SHA，**只因 `ws` 有没有 HEAD**，结果从**静默**翻转为 **BLOCK** ⇒ 该静默是**真 fail-open**（判据被绕过），**不是死代码**；`ws` 有提交时 `$ws` 被采纳且 `:144` 取到 HEAD，故 `project/` 侧连谓词都不求值——与 `GAP-012` 的推演一致。**本仓不可达**：本仓 `$ws` 恒为有 HEAD 的真仓（`61f63de`）。**触发前提**：有人在**工作区根**（而非 `project/`）`git init` 且**尚未提交**——与 `GAP-007` 是**同一族的"内层/外层仓混淆"**，只是这次的肇事者是工作区根自己。
