# 005 · aicf-guard M0 地基（Go module 骨架 + --version + 共享库 6 件）

- **日期**：2026-10-28（UTC）
- **分支**：`feat/aicf-guard-m0`（自 `main` `8e744cd` 切出，0 提交起步）
- **关联**：`docs/adr/ADR-001-aicf-guard.md`（Accepted，`f06fcbc`）· 路线图 `docs/planning/roadmap-production.md` P1.2 · 台账 `GAP-025`② / `GAP-028` / `GAP-029` / `GAP-031` / `DEFER-014`
- **性质**：02 开发环 · M0 地基（**第 1/2 次派发**）。第 2 次（`progress` 子命令 + 转发层 + 对拍）由总控后续派，**本单元不做**。
- **记录方式**：**先写后填**（`AGENTS.md` §2 的 02 环准出 + 角色契约第 4 条）。本条先立骨架（做什么 + 准出清单）；实测结果于改动落地后回填（见文末「六、回填」）。
- **编号确认**：跨分支并集实测（开工前跑 `AGENTS.md` §6.1 口径）——`001`/`002`/`003`/`004` 占用，**`005` 可用**。

---

## 一、准入审查（§3 第 1 段）

| 项 | 状态 | 证据 |
| --- | --- | --- |
| 01 设计环准出 | ✅ | ADR-001 已 Accepted（`f06fcbc`），P0 五条收敛、M0 前 P1（R6/R10/R13）落定 |
| 前置 ADR/Schema | ✅ | ADR-001 §2.1/§2.2/§2.3/§2.4/§6.8/§8.1 已锁定 |
| 分支 | ✅ | `feat/aicf-guard-m0`，从 `main` `8e744cd` 切出，clean |
| Go 工具链 | ✅ | `go1.27.3-X:nodwarf5 linux/amd64`（本机实测） |
| 编号可用 | ✅ | 跨分支并集：001-004 占用，005 可用 |
| 写方 shell 挂载 | ✅ | 上会话探针实测（5 命令全 exit 0） |

**D2 转段**：01 已准出 ⇒ 可进 02 开发 M0。本单元是 02 开发环内的子任务（**不构成生命周期阶段推进**，不触发 §4.2 三跳链——三跳链在第 2 次派发完成 M0 整体后由总控派）。

---

## 二、本单元范围（M0 地基，第 1/2 次派发）

### 2.1 交付物

1. **Go module 骨架**：`aicf-guard/go.mod`（`go 1.21`，零外部依赖）+ `aicf-guard/main.go`（入口 + 子命令分发骨架：`progress`/`numbers`/`inject`/`adapter`/`selftest`/`doctor` 占位 + `--version` 实现）。仅用 Go 标准库。
2. **`--version` 子命令**（ADR §2.1 R4）：输出 `aicf-guard <semver> (<commit-hash>)` 一行 stdout，exit 0。构建期注入 `-ldflags "-X main.version=… -X main.commit=…"`；默认值 `dev`/`unknown`。**不读工作区、不调 git、不依赖外部状态**。
3. **共享库 6 件**（ADR §2.2，`progress` 用到的；`numbers.UnionBranches`/`files.Enum` 留 M1/M3）：
   - `internal/workspace` `Resolve()`：分层解析（① `--workspace` 旗标 · ② `CLAUDE_PROJECT_DIR` · ③ `os.Executable()` 回推 · ④ CWD 向上找 `.claude/`/`.agents/`）。仓库候选 `@[ws, ws/project]`、ws 优先、须 `git rev-parse --git-dir` exit 0（GAP-009）。
   - `internal/git`：`Checked()`（唯一 git 入口：清 `GIT_*` 整族 9 个 → 跑 → 读 exit code → 还原；返回 `{Exit,Text}`；判据恒 `.Exit`）+ `Probe()`（`git --version` 须 exit 0）+ `Canary()`（`git rev-parse --verify 0000…^{commit}` 须 exit≠0）。
   - `internal/mainline` `Resolve()`：三级回退（`refs/remotes/origin/HEAD` 须再过 `rev-parse --verify` → `refs/heads/main` → `HEAD` 兜底）。返回 `{Ref,Name}`，`Name` 用于 reason 点名（GAP-031）。
   - `internal/sha` `Compare()`：两侧各 `rev-parse --verify` 归一 40 位 lowercase hex 再比（GAP-008，不用前缀比对）。
   - `internal/page` `ReadHead()`：读进度页 + 正则抠 SHA。**保留同款正则与同款静默**（GAP-025 残余不修）：`<div[^>]*>\s*head\s*<b[^>]*>\s*([0-9a-fA-F]{7,40})\s*</b[^>]*>\s*</div[^>]*>`。
4. **共享库单测**（每件都要，含负向用例 D3）——详见 §三。
5. **`.gitignore` 同步**（ADR §6.8 R10）：追加 `/aicf-guard/bin/` · `/.claude/hooks/aicf-guard` · `/.claude/hooks/aicf-guard.exe`（带前导 `/`）。
6. **本文档**（先写后填）。

### 2.2 不做（边界）

| 项 | 为什么不做 |
| --- | --- |
| `progress` 子命令实现 + 转发层 + 对拍 | 第 2 次派发范围 |
| `numbers`/`inject`/`adapter`/`selftest`/`doctor` 实现 | M1/M2/M3/M4（ADR §3） |
| `numbers.UnionBranches` / `files.Enum` | M1/M3 |
| 切 hook 配置（去 `powershell`） | M4 |
| `memory.md` / 进度页 / `record.md` | 总控职责（注册表硬约束） |
| `AGENTS.md` / `prompts/` / 角色契约 | 元架构不动 |

---

## 三、准出清单（M0 地基，落地后逐条回填实测）

> **回填口径**：下表「实测」列取自 `2026-10-28` 本机实跑（`go1.27.3` · `git 2.56.0` · Linux）。
> 第 1/2 次派发**共用这一张表**（同一个 M0）；第 2 次派发新增的 5 个单元见 §四之二与 §七。

### 3.1 module 骨架 + `--version`

| # | 判据 | 命令 | 预期 | 实测 |
| --- | --- | --- | --- | --- |
| 1 | module 编过 | `cd aicf-guard && go build ./...` | exit 0 | ✅ **exit 0** |
| 2 | 默认 `--version`（未注入） | `cd aicf-guard && go build -o /tmp/ag . && /tmp/ag --version` | `aicf-guard dev (unknown)` + exit 0 | ✅ `aicf-guard dev (unknown)` · exit 0 |
| 3 | 注入 `--version` | `cd aicf-guard && go build -ldflags "-X main.version=v0.1.0 -X main.commit=test1234" -o /tmp/ag . && /tmp/ag --version` | `aicf-guard v0.1.0 (test1234)` + exit 0 | ✅ `aicf-guard v0.1.0 (test1234)` · exit 0 |
| 4 | 无参数 | `/tmp/ag` | exit 2 + usage on stderr | ✅ exit 2 · stdout 0B · stderr 539B |
| 5 | 未知子命令 | `/tmp/ag bogus` | exit 2 + stderr | ✅ exit 2 · stdout 0B · stderr 578B |
| 6 | 占位子命令 | `/tmp/ag numbers` | exit 1 + stderr（not implemented） | ✅ exit 1 · stderr `aicf-guard: "numbers" not implemented yet (see ADR-001 §3 for the milestone)`。**注**：原表写的是 `progress`——它在第 2 次派发已实现，占位集缩为 `numbers`/`inject`/`adapter`/`selftest`/`doctor`（`progress` 的接线另有专测：`TestProgressSubcommandBelow`） |
| 7 | `go.mod` 最低版本 | `grep '^go ' aicf-guard/go.mod` | `go 1.21`（实测抬高了则记） | ✅ `go 1.21`（**未抬高**；用到的 API 均 ≤1.21，用 go1.27.3 编译通过） |

### 3.2 共享库 6 件单测（含负向，D3）

| # | 包 | 关键用例（正向 + 负向） | 命令 | 预期 | 实测 |
| --- | --- | --- | --- | --- | --- |
| 8 | `internal/git` | `Probe()` true · `Canary()` true · `Checked` exit=0 / exit≠0 · **`GIT_DIR`+`GIT_OBJECT_DIRECTORY` 劫持不被劫持（GAP-013①/GAP-031）** · `filterGitFamily` 9 个全滤 | `go test -race ./internal/git/` | PASS | ✅ `ok aicf-guard/internal/git 1.092s` |
| 9 | `internal/workspace` | 旗标覆盖 · 旗标无效 · `CLAUDE_PROJECT_DIR` · exe 回推 · CWD 回退 · 优先级（旗标>CPD>exe>cwd）· repo `@[ws,ws/project]` ws 优先 · 无 repo | `go test -race ./internal/workspace/` | PASS | ✅ `ok 1.063s`（34 格；第 2 次派发新增 `ResolveFrom`/`FindPage` 10 格，见 §7.3） |
| 10 | `internal/mainline` | **三级回退各分支**：origin/HEAD 命中 / main 兜底 / HEAD 兜底（Name 点名）/ unborn 全不中 | `go test -race ./internal/mainline/` | PASS | ✅ `ok 1.151s`（7 格；新增「级 1 目标非 commit」格，见 §7.2） |
| 11 | `internal/sha` | 短前缀+full id 一致 · **真前缀+假后缀（40 位）不一致（GAP-008）** · 不存在的 SHA ⇒ false · 大小写 | `go test -race ./internal/sha/` | PASS | ✅ `ok 1.388s`（18 个顶层用例；新增 `ResolveFull`/`EqualFull`，见 §7.1） |
| 12 | `internal/page` | 无属性 / `b[class]` / `b[style]` / `div[class]` / 两侧空白 · **缺页/无标记 ⇒ 同款静默** · `<span>` 重构 ⇒ 静默（GAP-025 残余）· 7 位下界 / 6 位不匹配 | `go test -race ./internal/page/` | PASS | ✅ `ok 1.017s`（11 个顶层用例；新增 `ReadPageName` 与畸形首标记格，见 §7.4） |

> 第 2 次派发另增两个包（不在原表 6 件内）：`internal/progress`（`ok 1.280s`，32 格）·
> `internal/parallel`（`ok 1.646s`，11 格）。合计 **7 个包全 ok**（`go test -race ./...`）。

### 3.3 判据不变量（ADR §1.3，不得破坏）

| # | 不变量 | 验证方式 | 实测 |
| --- | --- | --- | --- |
| 13 | **THE ONE RULE**：git 调用判据是退出码 | 全仓 grep `git.Checked(` —— 除 `internal/git` 自身外，**7 处调用点**全在 3 个共享库（workspace 1 · mainline 5 · sha 1），`internal/progress` **零调用**（只经共享库） | ✅ 7 处，见下 |
| 14 | 负向金丝雀 | `Canary()` 单测：`git rev-parse --verify 0000…^{commit}` exit≠0 | ✅ `TestCanary` PASS；`progress` 侧另有 `TestRunP5CanaryUntrustworthy` + 沙箱 `CanaryNotice`（真 shim） |
| 15 | `GIT_*` 族（9 个）清空 | `filterGitFamily` 单测：9 个全滤；`Checked` 集成：注入 `GIT_DIR`+`GIT_OBJECT_DIRECTORY` ⇒ 不被劫持 | ✅ `grep -c '"GIT_' internal/git/git.go` ⇒ **9**；`TestCheckedFiltersGitEnvFamily` PASS；沙箱 `A9/A10 GIT_DIR 注入他仓` 场景 |
| 16 | 主干三级回退 reason 点名 | `mainline` 单测：HEAD 兜底 Name = `HEAD（未找到主干）` | ✅ `TestResolveHEADFallback` PASS；`progress` 侧 M8 变异（写死"当前 HEAD"）**4 格 FAIL** |
| 17 | SHA 双侧归一 full id 再比 | `sha` 单测：真前缀+假后缀（40 位）⇒ false | ✅ `TestCompareFakeSuffix` PASS；`TestEqualFull/same-7-prefix` 亦 PASS |
| 18 | HTML 正则同款 | `page` 单测：正则与 `check-progress.ps1:375` 逐字一致（`<span>` 仍静默） | ✅ **逐字节相等**（§7.4.4 的 `[ "$ps_re" = "$go_re" ]` ⇒ `IDENTICAL`）；`TestReadHead/span-restructure` 断言静默 |

`git.Checked(` 的 7 处调用点（`grep -rn 'git.Checked(' --include=*.go . | grep -v _test.go | grep -v internal/git/`）：

```
internal/workspace/workspace.go:188   rev-parse --git-dir
internal/mainline/mainline.go:52      symbolic-ref refs/remotes/origin/HEAD
internal/mainline/mainline.go:55      rev-parse --verify <origin/HEAD>^{commit}
internal/mainline/mainline.go:60      rev-parse --verify refs/heads/main^{commit}
internal/mainline/mainline.go:65      rev-parse --verify HEAD^{commit}
internal/mainline/mainline.go:90      rev-parse --short <ref>
internal/sha/sha.go:74                rev-parse --verify <id>^{commit}
```

> **一处如实标注**：`internal/parallel/scenarios.go` 里也有 `exec.Command("git")`——那是**造沙箱**（`init`/
> `commit`/`symbolic-ref`/`update-ref`），**不是**守卫的判据路径，且每次调用都核对错误（`git()` helper 返回 error）。
> 它不受 THE ONE RULE 约束（那条规则管"判定",不管"造数据"），但**读数是 `exec.Command` 而非 `git.Checked`**，
> 故在此写明，免得 `grep` 的人以为有第二处判据实现。

### 3.4 `.gitignore` 同步（ADR §6.8 R10）

| # | 判据 | 命令 | 预期 | 实测 |
| --- | --- | --- | --- | --- |
| 19 | 排除规则就位 | `grep -n aicf-guard .gitignore` | 3 行（`/aicf-guard/bin/` · `/.claude/hooks/aicf-guard` · `/.claude/hooks/aicf-guard.exe`）+ 注释 | ✅ **5 条**（比原计划多 2 条：`/aicf-guard/aicf-guard` 与 `/aicf-guard/aicf-guard.exe`——裸 `go build ./...` 会在 main 包目录留下同名二进制，原计划漏了这一形态）。行号 33–37 |
| 20 | 源码入库 | `git ls-files aicf-guard/` | `go.mod`/`main.go`/`main_test.go`/子包源码（**不**含 `bin/`） | ✅ **19 个文件**：`go.mod` · `main.go` · `main_test.go` · 7 个子包各 `*.go`(+`_test.go`) · `tools/parallel/main.go`。**不含** `bin/`、不含二进制 |
| 21 | 本地 build 后无残留 | `go build -C aicf-guard -o ../.claude/hooks/aicf-guard . && git status --porcelain` | 无 `.claude/hooks/aicf-guard`（被忽略） | ✅ 实测 `git status --porcelain` 只列出手改的两个 `.ps1`，**二进制不出现**；`git check-ignore -v` 命中 `.gitignore:36` |

---

## 四、负向证伪检验（§3 第 4 段，D3）

> 本单元的负向用例**已在 §三 的单测里逐条具名**（上表「负向」列）。此处归纳「注入什么故障能让判据静默通过」——每条都对应一个测试。
> **第 2 次派发追加的部分见 §四之二；「变异是否真被杀」的实测读数见 §七各节。**

| 证伪点 | 注入什么 | 必须的表现 | 对应测试 | 实测 |
| --- | --- | --- | --- | --- |
| `GIT_DIR` 劫持（GAP-013①） | `GIT_DIR=<他仓>` + `GIT_OBJECT_DIRECTORY=<他仓>` 后调 `Checked("-C", B, ...)` | 读数是 B 不是他仓（exit 0 且 Text=B 的 HEAD） | `TestCheckedFiltersGitEnvFamily` | ✅ PASS |
| 金丝雀失效（ADR §1.3.2） | `git rev-parse --verify 0000…^{commit}` | exit≠0（`Canary()` 返回 true=可信） | `TestCanary` | ✅ PASS |
| SHA 前缀比对（GAP-008） | 真前缀 + 假后缀（40 位）vs 真 full id | `Compare` 返回 **false**（不因前缀相同而判一致） | `TestCompareFakeSuffix` | ✅ PASS（另 `TestEqualFull/same-7-prefix` 钉住 full-id 路径） |
| HTML 正则盲区（GAP-025 残余） | `<span>head <b>deadbeef</b></span>` | `ReadHead` 返回 `("", false)`（**静默**——残余不修，A5 格钉住） | `TestReadHead/span-restructure` | ✅ PASS（沙箱 `A5` 场景同样断言静默） |
| 缺页 / 无标记 | 不存在的文件 / 无标记的 HTML | `ReadHead` 返回 `("", false)`（同款静默） | `TestReadHeadMissingFile` / `no-marker` | ✅ PASS |
| 主干三级全不中 | unborn repo（无 commit） | `Resolve` 返回 `Ok=false` | `TestResolveUnborn` | ✅ PASS（`progress` 侧 `TestRunP7MainlineUnresolvedIsHonoured`） |
| `--version` 默认值 | 不注入 ldflags 直接 build | `aicf-guard dev (unknown)`（不是空 / 不是崩） | `TestVersionDefault` | ✅ PASS。**注**：原表写的 `TestVersion` **不存在**（实际名 `TestVersionDefault`）——已按实测更正 |

---

## 四之二、第 2/2 次派发（`progress` 子命令 + 转发层 + 对拍，先写后填）

> 本节于**动手前**立骨架：范围 + 准出判据先落盘，实测结果落地后回填（见「七、回填记录 · 第 2 次派发」）。
> 第 1/2 次派发的 §三 表里的「实测」列**由本节接手回填**（同一个 M0，同一份记录）。

### 4.2.1 范围（5 个提交，一单元一提交）

| # | 单元 | 提交信息前缀 | 关键内容 |
| --- | --- | --- | --- |
| U1 | `internal/sha` 接管 + 补强 | `feat(aicf-guard): internal/sha — …` | 原工作树版本**只有 `Compare`**，而 `progress` 需要「先解析主干 full id、再判静默」的同款结构（`.ps1:345-348`）。补 `ResolveFull` / `EqualFull`，`Compare` 改为复用它们（单一实现）。新增 40 位非法 hex ⇒ false（原 `resolveFull` 会把 stderr 载荷原样返回成"full id"）。 |
| U2 | `internal/mainline` 接管 + 补强 | `feat(aicf-guard): internal/mainline — …` | 补 `ResolveFull(repo, r Result)`：`rev-parse --verify <ref>^{commit}`，失败返回 ok=false（`.ps1:345-346` 的静默分支要有单一入口）。补「`origin/HEAD` 存在但目标是**非 commit 对象**」用例。 |
| U3 | `internal/workspace` 接管 + 补强 | `feat(aicf-guard): internal/workspace — …` | 补 `ResolveAt`（显式 cwd，供单测与 `Run` 注入，避免 `os.Getwd`/`os.Executable` 的不可控输入）+ `FindPage`（两处候选，`.ps1:212-215`）。`.ps1` 的"自定位"是 `$PSCommandPath` 的**父目录**（`.ps1:185-187`）；二进制等价物是 `os.Executable` 的目录（已实现），此处只补测试钉住「**脚本路径** → ws」与「**其父目录**（= hooks 目录）→ ws」**两者等价**。 |
| U4 | `internal/page` 接管 + 补强 | `feat(aicf-guard): internal/page — …` | **复核**工作树已有的两处修法：① `TestReadHeadMultipleMarkers` 的 `first1`/`second2` 非十六进制 ⇒ 改 `deadbee1`/`deadbee2`；② 新增 `TestReadHeadNonHexMarker` 钉住区别。**结论见回填**。补 `ReadPageName`（指针文件语义，`.ps1:199-206` 的三态：缺失 / 有名字 / 有但读不出）与 `.ps1` 未覆盖的边界：`()` 组合贪婪吞掉第二个标记（实测后决定是否加用例）。 |
| U5 | `progress` 子命令 + `main.go` 接线 | `feat(aicf-guard): progress 子命令 — …` | 按 `Run(args, stdout, stderr, Deps)` 注入式设计（cmd 包）实现 §4.2.2 的**每个分支**；`--workspace` 旗标。 |
| U6 | 对拍 harness（可注入 oracle） | `test(aicf-guard): 对拍 harness — …` | 场景清单 + `AICF_ORACLE` 注入；**无 oracle ⇒ SKIP 且 exit code 可区分**。 |
| U7 | `.ps1` 薄转发层 + legacy 副本 | `refactor(hooks): check-progress.ps1 — …` | 调 `aicf-guard progress`；二进制缺失 ⇒ `exit 1`+stderr（fail-closed）。原实现移 `check-progress.legacy.ps1` 供对拍取 oracle。 |

### 4.2.2 `aicf-guard progress` 分支契约（**逐条对齐 `.ps1`**，每行一个单测）

| # | 条件 | `.ps1` 行 | 退出码 | stdout | stderr |
| --- | --- | --- | --- | --- | --- |
| P1 | 工作区解析失败（含 `--workspace` 指向非工作区） | 185-187 | 0 | 空 | 空 |
| P2 | 指针文件**存在**但页名为空/全空白 | 199-206, 224-227 | 1 | 空 | `进度页指针异常：…` |
| P3 | 无进度页（两处候选都不存在 / 指针指向不存在的页名） | 212-215, 233 | 0 | 空 | 空 |
| P4 | git 不可用（launch 失败 ⇒ `Probe()` false） | 246-250 | 1 | 空 | `进度页守卫未运行：PATH 上的 git 不可用…` |
| P5 | 金丝雀不可信（必败输入返回 0） | 265-269 | 1 | 空 | `…git 退出码不可信…` |
| P6 | 无仓库候选 | 286-291 | 0 | 空 | 空 |
| P7 | 主干三级全不中（unborn） | 314-340 | 0 | 空 | 空 |
| P8 | 主干 full id 解析失败 / 为空 | 345-348 | 0 | 空 | 空 |
| P9 | 页面无 `head <b>sha</b>` 标记（含 `<span>` 重构） | 375-376 | 0 | 空 | 空 |
| P10 | 记录 SHA 解析不了 **或** ≠ 主干 full id | 396-397 | 0 | `{"decision":"block","reason":"…"}` | 空 |
| P11 | 两侧 full id 相等 | 397 | 0 | 空 | 空 |

**block 的 `reason` 逐字对齐 `.ps1:403-405`**（`$name`/`$recorded`/`$mainName`/`$headShort` 四个插值位）：
`进度页落后于主干：<name> 记录的 HEAD 是 <recorded>，而 <mainName> 是 <headShort>。请先更新该页面再结束本轮——按 AGENTS.md 的交付约定，进度页要与代码同成熟度。需要同步的内容通常包括：状态条 head、用例数、覆盖率、GAP 台账状态与图例、以及新增的提交行。`

**`headShort`** = `rev-parse --short <mainRef>` 的 `.Text`；**空则回退 full id**（`.ps1:349-350`）。

### 4.2.3 准出判据（本单元）

| # | 判据 | 命令 | 预期 |
| --- | --- | --- | --- |
| L1 | 静态检查 + 竞态 | `cd aicf-guard && go vet ./... && go test -race ./...` | 全 PASS |
| L2 | 每个分支有单测 | `go test -race -run 'TestRun' -v ./internal/progress/` | P1–P11 各至少一格具名 |
| L3 | 变异负向（判据有牙） | 逐包改坏实现 ⇒ 对应用例 FAIL（读数见回填） | FAIL 出现，且**只有**对应用例 FAIL |
| L4 | 对拍 | `AICF_ORACLE=… go test -run Parallel -v` | **本机 SKIP**（无 PowerShell，`command -v pwsh`/`powershell` 均 exit 1）——**不得记 PASS** |
| L5 | 转发层静态核对 | `grep` 关键分支 | 二进制缺失 ⇒ `exit 1` + stderr |

---

## 五、下游同步与未竟 GAP（§3 第 5 段）

### 5.1 本单元触发的文档联动

| 文档 | 同步动作 | 本单元是否改 |
| --- | --- | --- |
| `docs/changes/005`（本文件） | 先写后填 | ✅（本文件） |
| `docs/planning/roadmap-production.md` | P1.2 进度随 M0 推进 | 否（M0 整体完成后由总控） |
| `docs/ledger.md` | `GAP-025`② / `GAP-029` 状态推进 | 否（总控职责；三跳链后） |
| `.gitignore` | 排除 `aicf-guard` 二进制产物（§6.8 R10） | ✅ |

### 5.2 未竟 GAP（本单元不新增编号，遵守「登记前先检索」D4）

| 编号 | 状态 | 说明 |
| --- | --- | --- |
| `GAP-025`② | 已缓解·残余 | HTML 正则残余（`<span>` 重构静默）**不修**——保留同款正则与同款静默（ADR §1.3.6）。`page` 单测的 `<span>` 用例与沙箱 `A5` 场景钉住残余。 |
| `GAP-029` | 已实现·待复核 | 布局无关枚举（`files.Enum`）**不在 M0**（M3）。`workspace.Resolve` 不涉及该路径。 |
| `GAP-031` | 已实现·待复核 | 主干三级回退——`mainline.Resolve` 重写同款逻辑，单测覆盖三级 + 级 1 非 commit 格；`progress` 侧沙箱 `A12`/`A13` 复现「分支 vs 主干」。**独立复核由 `falsifier` 在三跳链做**。 |
| ADR §8.3 待登记① | **已实现，编号待总控登记** | 「薄转发层在二进制缺失时的 fail-closed 契约」——U7 已实现（`exit 1` + stderr，静态核对见 §7.7）。ADR §8.3 原文要求「M0 实现时若发现某子命令的『二进制缺失』无法与原『git 不可用』分支同形，登记为独立缺口」——**发现了一处**：在 Antigravity 侧该分支会被 `stop-adapter.ps1:54-59` 降级为非阻断，见 §7.7 的「交给门禁的残余」。 |
| **新增（待总控编号）** | **阻塞对拍准出** | **本机无 PowerShell 运行时**（`pwsh`/`powershell` 均缺），M0 的对拍准出**无法在本机达成**。装置已就绪（§7.6），复跑命令已给出（§7.6.4）。这**不是**"不适用"，是「判据存在但运行时缺失」——按 `AGENTS.md` §2 该环**未满足**。 |
| **新增（待总控编号）** | **待裁定** | Antigravity 侧「二进制缺失 = 非阻断」的残余（§7.7）。候选处置与后果已列出，属**契约变更**，不在实现方权限内。 |

### 5.3 不自证（D3 + 角色硬边界）

本次（两次派发合计）的测试**不能自己放行**。本地验证（`go build`/`go vet`/`go test -race`/真二进制沙箱跑）
必须做且已做，但 **M0 准出由总控三跳链判定**（`qa-validator`→`falsifier`→`gate-auditor`，§4.2）。
本文交付「实现 + 本地验证证据 + 变异读数」，**非准出裁决**。

**其中两条必须在三跳链里被特别看**（实现方标记，不作结论）：
1. **对拍未验证**（§7.6）——ADR §6.1 把它列为**硬判据**。判据未满足时，「Go 版与 .ps1 等价」这句话**没有证据**。
2. **转发层未经实机运行**（§7.7）——本机无 PowerShell，`check-progress.ps1` 的正确性目前只有静态核对。

---

## 六、回填（改动落地后，`go build`/`go test -race`/`--version` 实测）

> 表 3.1–3.4 的「实测」列**已全部回填**（见 §三各行 ✅ 与读数）。逐单元的过程记录见「七、回填记录」。

**M0 整体读数（`2026-10-28`，本机）**

```
$ cd aicf-guard && gofmt -l . ; go vet ./...
（无输出）
$ go test -race -count=1 ./...
ok  	aicf-guard	1.038s
ok  	aicf-guard/internal/git	1.103s
ok  	aicf-guard/internal/mainline	1.160s
ok  	aicf-guard/internal/page	1.039s
ok  	aicf-guard/internal/parallel	1.646s
ok  	aicf-guard/internal/progress	1.280s
ok  	aicf-guard/internal/sha	1.370s
ok  	aicf-guard/internal/workspace	1.080s
?   	aicf-guard/tools/parallel	[no test files]
```

---

## 七、回填记录

> 逐单元回填，**按提交顺序**。每条含：改了什么 / 为什么 / 验证命令与**真实读数** / 变异负向结果。
> 环境（`2026-10-28T08:23Z` 实测）：`go1.27.3-X:nodwarf5 linux/amd64` · `git 2.56.0` ·
> `command -v pwsh` ⇒ exit 1（**无**）· `command -v powershell` ⇒ exit 1（**无**）。

### 7.1 U1 · `internal/sha`（补强 `ResolveFull` / `EqualFull`，`Compare` 改为复用）

**改了什么**

| 文件 | 改动 |
| --- | --- |
| `aicf-guard/internal/sha/sha.go` | 新增 `ResolveFull(repo, id) (string, bool)`（`.ps1:345-348` 的「主干 full id 解析失败 ⇒ 静默」需要一个**单一入口**，而原工作树版本只有 `Compare`，做不到"先解析、再判静默"）；新增 `EqualFull(a, b)`（两个**已解析** full id 的纯比较）；`Compare` 改为 `ResolveFull × 2 + EqualFull`。 |
| `aicf-guard/internal/sha/sha_test.go` | 补 `ResolveFull`/`EqualFull` 用例 + 两格 PATH shim 用例。 |

**为什么改（原实现的两处缺陷）**

1. **API 形状不够**：`progress` 需要 `.ps1:345-348` 的语义——主干 full id 解析失败时**静默**（那与"页面落后"是两个不同的判定）。只有 `Compare` 时，调用方要么复制一份 `rev-parse` 调用（**第二处读 git 退出码**，违反 THE ONE RULE / D4），要么把"主干解析失败"错判成"页面落后"。故新增独立入口。
2. **`resolveFull` 会把 stderr 载荷当 full id 返回**：`Result.Text` 在非 0 退出时是 `""`（`git.Checked` 的实现），但**在 exit 0 且 stdout 非 id 时**会把任意文本原样返回。`.ps1` 侧此路不可达（它的 `$recorded` 已被 HTML 正则约束为 hex），Go 侧补一条 `^[0-9a-f]{40}$` 形状断言是**零成本**的 fail-closed，且**不改判据**（判据仍是退出码）。
   ⚠️ **残余如实记**：一个"永远 exit 0 + 打印**合法 40 位 hex 常量**"的 shim 仍能通过 `ResolveFull`——**任何只看输出的判据都拦不住它**。这条由上游 `Probe`+`Canary`（`.ps1:246-269`）拦，见 `TestResolveFullShimExitZeroWithJunk` 的注释。

**正向实测**

```
$ cd aicf-guard && gofmt -l internal/sha/ && go vet ./internal/sha/
（无输出）                                              # 格式与静态检查干净
$ go test -race -count=1 ./internal/sha/
ok  	aicf-guard/internal/sha	1.324s
$ go test -count=1 -v ./internal/sha/ | grep -c '^--- PASS'
18                                                      # 顶层用例 18 个（含 9 个 EqualFull 子用例）
```

**负向（变异验证——判据有牙）**：逐条改坏实现，确认**对应用例 FAIL**，然后还原。

| 变异 | 改法 | 实测结果 |
| --- | --- | --- |
| M1 | 去掉 `^{commit}` peel（`id+"^{commit}"` → `id`） | `--- FAIL: TestResolveFullTreeIsNotACommit` · `TestResolveFullBlobIsNotACommit` · `TestResolveFullUnknownID` ⇒ `FAIL` |
| M2 | 形状断言短路（`if !fullIDRe…` → `if false`） | 首轮 **存活（ok）** ⇒ **补了 `TestResolveFullShimExitZeroWithJunk`** ⇒ 复跑 `--- FAIL: TestResolveFullShimExitZeroWithJunk` |
| M3 | `EqualFull` 把 empty==empty 判真 | `--- FAIL: TestEqualFull` |
| M4 | `EqualFull` 改前缀比较（`a[:7]==b[:7]`） | 首轮 **存活（ok）** ⇒ **补了 `same-7-prefix` 子用例** ⇒ 复跑 `--- FAIL: TestEqualFull` |
| M5 | `Compare` 只看"两侧都解析成功" | `--- FAIL: TestCompareDifferentCommits` |
| M6 | `ResolveFull` 对空 id 返回 ok | `--- FAIL: TestResolveFullEmpty` |

> **两格首轮存活是这次变异测试的真实收获**（D3 的价值正在此）：M2/M4 都不是"理论上的漏"，是**改坏后测试仍然全绿**。补的用例分别是 **PATH shim**（`.ps1:36-39` 记录的 V13 形态）与 **同 7 位前缀的两个合法 40 位 id**。

**判据不变量对照（ADR §1.3）**：§1.3.5（SHA 双侧归一 full id 再比）✅ 由 `ResolveFull` 强制；§1.3.1（THE ONE RULE）✅ 本包不直接读 git 退出码，只经 `git.Checked`。

### 7.2 U2 · `internal/mainline`（逐行核对后**实现未改**，补一条负向用例）

**核对结论（逐行对照 `.ps1:314-348`）**

| `.ps1` 行 | 行为 | Go 实现 | 结论 |
| --- | --- | --- | --- |
| 316-323 | 级 1：`symbolic-ref --quiet refs/remotes/origin/HEAD` **exit 0 且 Text 非空** → `rev-parse --verify --quiet "$candRef^{commit}"` **exit 0** ⇒ 命中；`Name = candRef -replace '^refs/remotes/',''` | `Resolve` 级 1 同形；`stripRemotePrefix` = `strings.TrimPrefix`（PS 的 `-replace '^…'` 锚定在开头，与 TrimPrefix 等价） | ✅ 一致 |
| 324-329 | 级 2：`refs/heads/main^{commit}` exit 0 ⇒ `Name='main'` | 同形 | ✅ |
| 330-335 | 级 3：`HEAD^{commit}` exit 0 ⇒ `Name='HEAD（未找到主干）'`（**必须点名兜底**） | 同形，字符串逐字一致 | ✅ |
| 340 | 三级全不中 ⇒ `exit 0`（静默） | 返回 `Result{Ok:false}`，**由调用方**决定静默 | ✅（决策点留在调用方，符合 `.ps1` 的分支结构） |
| — | （`.ps1` 无此分支） | `repo == ""` ⇒ 直接 `Ok:false` | 防御性新增，**不改变可观测行为**（`workspace.Resolve` 不会返回空 repo） |

**改了什么**：`aicf-guard/internal/mainline/mainline.go` **无改动**（核对后确认与 `.ps1` 一致，不做"为改而改"）；`aicf-guard/internal/mainline/mainline_test.go` 补
`TestResolveOriginHeadNonCommitFallsToMain`。**为什么补**：原有 3 条级 1 用例里，「dangling ref」在**查 ref 那一步**
就失败了，**从未走到 `^{commit}` peel**——于是"级 1 去掉 `^{commit}`"这个变异（M2）原本**无格可杀**。这是
ADR §1.3.4「`symbolic-ref` 不够，须再过一次 `rev-parse --verify`」在**对象类型**维度上的补格。

**正向实测**

```
$ cd aicf-guard && gofmt -l internal/mainline/ ; go vet ./internal/mainline/
（无输出）
$ go test -race -count=1 -v ./internal/mainline/
--- PASS: TestResolveOriginHead
--- PASS: TestResolveMain
--- PASS: TestResolveHEADFallback
--- PASS: TestResolveUnborn
--- PASS: TestResolveOriginHeadNonCommitFallsToMain      # 本次新增
--- PASS: TestResolveEmptyRepo
--- PASS: TestResolveOriginHeadUnbornFallsToMain
ok  	aicf-guard/internal/mainline	1.159s
```

**负向（变异验证）**

| 变异 | 改法 | 实测结果 |
| --- | --- | --- |
| M1 | 级 1 不再过 `rev-parse --verify`（`if true`） | `--- FAIL: TestResolveOriginHeadNonCommitFallsToMain` · `TestResolveOriginHeadUnbornFallsToMain` |
| M2 | 级 1 的 verify 去掉 `^{commit}` | `--- FAIL: TestResolveOriginHeadNonCommitFallsToMain`（**本条正是为它而加**） |
| M3 | 跳过级 2 | `--- FAIL: TestResolveMain` · `…NonCommitFallsToMain` · `…UnbornFallsToMain` |
| M4 | 级 3 的 `Name` 不点名（`"HEAD"`） | `--- FAIL: TestResolveHEADFallback` |
| M5 | `stripRemotePrefix` 不剥前缀 | `--- FAIL: TestResolveOriginHead` |
| M6 | 把级 3 提到级 1 之前（**退化回 HEAD**，即 GAP-031 复发） | `--- FAIL: TestResolveOriginHead` · `TestResolveMain` · `…NonCommitFallsToMain` · `…UnbornFallsToMain` |

> M5 首轮因**改法把 `strings` 导入变成未使用**而 build failed（不是被用例杀掉）——那不是有效变异，
> 改用 `strings.Clone(ref)`（保持导入有效）后重跑，`TestResolveOriginHead` FAIL。**build failed 不计入"判据有牙"**。
> M6 是本组最重要的一条：它就是 `GAP-031` 的**回归形态**（守卫比对当前 HEAD 而非主干），有四格同时变红。

### 7.3 U3 · `internal/workspace`（补 `ResolveFrom` + `FindPage`）

**改了什么**

| 文件 | 改动 |
| --- | --- |
| `aicf-guard/internal/workspace/workspace.go` | ① 新增 `ResolveFrom(flagWorkspace, projectDir, executable, workingDir)`——把 OS 派生的四个输入显式化；`Resolve` 改为读 OS 后**委托**给它（**只有一条实现**，`os.Executable`/`os.Getwd`/`os.Getenv` 在测试里不可注入，不抽出来则分层逻辑只能靠"测试二进制恰好放在哪"来测）。② 删除原 `resolveWorkspace`（其职责并入 `Resolve`）。③ 新增 `FindPage(ws, name)`：两处候选 `.ps1:212-215`，**ws 优先**，命中即停。 |
| `aicf-guard/internal/workspace/workspace_test.go` | 补 `ResolveFrom` 3 格 + `TestResolveUsesProjectDir`（唯一触碰 OS 管线的一格）+ `FindPage` 6 格。 |

**⚠️ 与 `.ps1` 的一处刻意差异（如实记，不藏）**

`.ps1:185-187` 的工作区推导是**无条件上溯两级**（`Parent(Parent($PSCommandPath))`），**不检查 `.claude/` 是否存在**；
Go 侧按 **ADR §2.3** 改为**上溯直到含 `.claude/`/`.agents/` 的目录**。两者在标准布局（`<ws>/.claude/hooks/<二进制>`）
下**同解**；差异只在非标准位置：

| 二进制位置 | `.ps1` 两级上溯 | Go 上溯 | 谁对 |
| --- | --- | --- | --- |
| `<ws>/.claude/hooks/aicf-guard` | `<ws>` | `<ws>` | 同 |
| `<ws>/bin/aicf-guard` | `<ws>` 的上两级（**错**） | `<ws>` | **Go 对**——ADR §2.3 明列 `<ws>/bin/` 为合法位置 |
| `<ws>/.agents/hooks/aicf-guard` | `<ws>` | `<ws>` | 同 |

**判据**：ADR §2.3 第 3 层原文「若二进制在 `<ws>/.claude/hooks/` 或 `<ws>/.agents/hooks/` 或 `<ws>/bin/` 下，
向上走到含 `.claude/` 或 `.agents/` 的目录」——`<ws>/bin/` 这一档**用两级上溯实现不了**，故差异是
**ADR 要求的**，不是漂移。这处差异**不影响对拍**：`.ps1` 转发层仍从自身位置派生路径，对拍沙箱里两者都在
`<ws>/.claude/hooks/` 下。

**正向实测**

```
$ cd aicf-guard && gofmt -l internal/workspace/ ; go vet ./internal/workspace/
（无输出）
$ go test -race -count=1 -v ./internal/workspace/
--- PASS: TestLayerFlagWins / TestLayerFlagInvalidFails / TestLayerFlagEmptyStringSkipped
--- PASS: TestLayerCPD / TestLayerCPDInvalidSkipped / TestLayerExeWalkUp / TestLayerExeWalkUpAgentsDir
--- PASS: TestLayerCWDWalkUp / TestLayerNoneResolve
--- PASS: TestLayerPrecedenceFlagOverCPD / …CPDOverExe / …ExeOverCWD
--- PASS: TestIsWorkspaceClaude / TestIsWorkspaceAgents / TestIsWorkspaceNeither / TestIsWorkspaceEmpty
--- PASS: TestResolveRepoSelfHosted / …ProjectChild / …WSPrecedence / …None / …DotGitFileNotResolving
--- PASS: TestResolveEndToEndFlagWithRepo / …FlagNoRepo / …FlagInvalid
--- PASS: TestResolveFromExecutableIsAPath / TestResolveFromRepo / TestResolveFromAllEmpty     # 新增
--- PASS: TestResolveUsesProjectDir                                                          # 新增
--- PASS: TestFindPageAtWorkspace / …AtParentOfWorkspace / …WorkspaceWinsOverParent
--- PASS: TestFindPageNone / …DirectoryCountsAsExisting / …EmptyInputs                        # 新增
ok  	aicf-guard/internal/workspace	1.061s
```

**负向（变异验证）**

| 变异 | 改法 | 实测结果 |
| --- | --- | --- |
| M1 | 无效 `--workspace` 回退到低层 | `--- FAIL: TestLayerFlagInvalidFails` · `TestResolveEndToEndFlagInvalid` |
| M2 | repo 候选顺序反转（`project` 优先） | `--- FAIL: TestResolveRepoWSPrecedence` |
| M3 | repo 候选不核对 `rev-parse --git-dir` 退出码 | 首轮改法 build failed（不可达代码）→ 改 `\|\| true`（**保留调用**）后 `--- FAIL: TestResolveRepoDotGitFileNotResolving`（GAP-009 那格） |
| M4 | `FindPage` 只试 ws 候选（去掉 pre-move 布局） | `--- FAIL: TestFindPageAtParentOfWorkspace` |
| M5 | `FindPage` 先试 parent（顺序反转） | `--- FAIL: TestFindPageWorkspaceWinsOverParent` |
| M6 | `ResolveFrom` 把 `executable` 当目录 | **存活（ok）——等价变异，非缺口**。见下 |
| M7 | `isWorkspace` 只认 `.claude`（丢 `.agents`） | `--- FAIL: TestLayerExeWalkUpAgentsDir` · `TestIsWorkspaceAgents` |

> **M6 为什么是等价变异**：把**文件路径**当起点时，第一跳 `isWorkspace(<file>)` 必然失败（普通文件下不存在
> `<file>/.claude`），于是同一轮就落到它的父目录——与正确实现的起点**逐跳相同**。两条路径只在"文件路径本身
> 是不是工作区"这一问上不同，而该问**恒为否**。故它**不是**判据缺口；`TestResolveFromExecutableIsAPath`
> 保留为「入口收的是**二进制路径**、不是目录」的契约文档。

**判据不变量对照（ADR §1.3）**：§1.3.1（THE ONE RULE）✅ 仓库候选判定仍只经 `git.Checked(...).Exit == 0`；
GAP-009（`.git` 存在 ≠ 是仓）✅ 由 M3 那格钉住；`.ps1:275-279`「ws 优先」✅ 由 M2 那格钉住。

### 7.4 U4 · `internal/page`（复核工作树的两处修法 + 补 `ReadPageName`）

#### 7.4.1 复核结论：`TestReadHeadMultipleMarkers` 的 `first1`/`second2` —— **测试数据错，不是包错**（确认）

**结论：工作树的修法正确，随本包一并接管。**

| 检查项 | 实测/推理 | 结论 |
| --- | --- | --- |
| `first1` / `second2` 是否匹配 `[0-9a-fA-F]{7,40}` | 二者都含非 hex 字符（`i`/`r`/`s`/`t`），**7 个字符里没有一个是合法 hex 序列**，故**不可匹配** | 原用例断言「应取第一个标记」时，`ReadHead` 返回 `("", false)` —— **包是对的** |
| 包是否因此有缺陷 | 无：非 hex 的 7 字符 token **本来就不是 SHA**，返回 false 正是契约（`.ps1` 同款） | **不是包错** |
| `.ps1` 会给同一答案吗 | 两者正则**逐字节相同**（已实测比对：`<div[^>]*>\s*head\s*<b[^>]*>\s*([0-9a-fA-F]{7,40})\s*</b[^>]*>\s*</div[^>]*>`，见 §7.4.4 命令）；`.NET` 与 Go 的 RE2 在这一模式上**无回溯语义差异**（无嵌套量词歧义） | **是**——但**注意**：`.ps1` 本机跑不了，此条是**同正则 + 同引擎语义的推理**，**非对拍实测** |
| 修法 `deadbee1`/`deadbee2` 是否正确 | 二者都是 7 位合法 hex ⇒ 命中；且**互不相等** ⇒ 能真正区分「取第一个」与「取第二个」。实测 `MATCH "deadbee1"` | ✅ 正确 |
| 新增 `TestReadHeadNonHexMarker` 是否钉住了该区别 | 是：它用**原来的** `first1`/`second2` 断言 `ok == false`，把「非 hex 不匹配」从"一个失败的用例"变成"一条被声明的契约" | ✅ 保留 |

#### 7.4.2 改了什么

| 文件 | 改动 |
| --- | --- |
| `aicf-guard/internal/page/page.go` | 新增 `DefaultPageName` 常量与 `ReadPageName(pointerPath) NameResult`——指针文件的**三态**（`.ps1:199-206`）：缺失⇒默认名且**不报故障**；有名字⇒trim 后返回；**有但读不出⇒报故障**（GAP-002）。补注释说明 M8/M9 的语义。 |
| `aicf-guard/internal/page/page_test.go` | 补 `TestReadHeadSkipsMalformedFirstMarker`（3 子格）+ `ReadPageName` 5 格。 |

**新发现（本次实测，值得钉住）**：正则命中「第一个**格式正确**的标记」，**不是**「第一个标记」。
畸形首标记（`<b></b>` / `<b>()</b>` / `<b>abc</b>`）根本不可匹配，引擎会**跳过它**取第二个。
实测：`<div>head <b></b></div><div>head <b>deadbee2</b></div>` ⇒ `MATCH "deadbee2"`。
**`.ps1` 走同一分支**（`[regex]::Match` 同正则）。这一点此前无人写下：一页两条状态条时，守卫**执法的是第二条**，
而读者的眼睛落在第一条 —— 已由 `TestReadHeadSkipsMalformedFirstMarker` 具名钉住。

**为什么 `ReadPageName` 必须把「读不出」归到故障而非「缺失」**：`.ps1` 先用 `Test-Path` 判存在、再
`Get-Content -ErrorAction SilentlyContinue`，故读错误落入它的 `else { $pointerFault = $true }` 分支。
Go 侧若把任意 I/O 错误都当 `os.IsNotExist`，就会**静默换回默认页名**——正是这条检查要防的那件事。

#### 7.4.3 正向实测

```
$ cd aicf-guard && gofmt -l internal/page/ ; go vet ./internal/page/
（无输出）
$ go test -race -count=1 -v ./internal/page/
--- PASS: TestReadHead                      # 22 个子用例
--- PASS: TestReadHeadMissingFile
--- PASS: TestReadHeadUnreadableFile
--- PASS: TestReadHeadMultipleMarkers       # 工作树已修：deadbee1/deadbee2
--- PASS: TestReadHeadNonHexMarker          # 工作树已加：first1/second2 ⇒ false
--- PASS: TestReadHeadSkipsMalformedFirstMarker   # 本次新增，3 子格
--- PASS: TestReadPageNameAbsentUsesDefault       # 本次新增
--- PASS: TestReadPageNameReadsTrimmedName
--- PASS: TestReadPageNameEmptyIsFault
--- PASS: TestReadPageNameUnreadableIsFault
--- PASS: TestReadPageNameInnerNewlineKept
ok  	aicf-guard/internal/page	1.018s
```

#### 7.4.4 正则逐字节比对（D1：不靠"看着一样"）

```
$ ps_re=$(sed -n '375p' .claude/hooks/check-progress.ps1 | sed -E "s/.*'([^']*)'.*/\1/")
$ go_re=$(grep -o 'regexp.MustCompile(`[^`]*`)' aicf-guard/internal/page/page.go | sed -E 's/regexp.MustCompile\(`([^`]*)`\)/\1/')
$ [ "$ps_re" = "$go_re" ] && echo IDENTICAL
IDENTICAL: <div[^>]*>\s*head\s*<b[^>]*>\s*([0-9a-fA-F]{7,40})\s*</b[^>]*>\s*</div[^>]*>
```

#### 7.4.5 负向（变异验证）

| 变异 | 改法 | 实测结果 |
| --- | --- | --- |
| M1 | 指针**缺失**也报故障 | `--- FAIL: TestReadPageNameAbsentUsesDefault` |
| M2 | 指针存在但为空**不**报故障（GAP-002 复发） | `--- FAIL: TestReadPageNameEmptyIsFault` |
| M3 | 非 `IsNotExist` 的读错误当「缺失」静默 | `--- FAIL: TestReadPageNameUnreadableIsFault` |
| M4 | 不 trim（保留尾随换行） | 首轮写法 build failed（`strings` 变未使用）→ 改 `strings.Trim(s, "\r\n")`（**只去换行、不去空格**）后 `--- FAIL: TestReadPageNameReadsTrimmedName` · `…EmptyIsFault` |
| M5 | Trim 改 Split（两行只取第一行） | `--- FAIL: TestReadPageNameInnerNewlineKept` |
| M6 | `ReadHead` 未命中仍报 `ok=true` | `--- FAIL: TestReadHead` 下 8 个子用例（含 `span-restructure` 残余格） |
| M7 | 正则收紧为 `<div>` 不带属性（**GAP-025 已修格复发**） | `--- FAIL: TestReadHead/div-class` · `/div-id` · `/div-and-b-attrs` |
| M8 | 正则放宽 `\w{7,40}`（容许非 hex） | `--- FAIL: TestReadHead/non-hex` · `TestReadHeadNonHexMarker` |

> M6/M7/M8 三条是**已发布契约的回归护栏**：M7 直接是 GAP-025 修好又被改坏的样子，
> M8 则会把 `TestReadHeadNonHexMarker`（本次接管的修法）打回原形。

**判据不变量对照（ADR §1.3）**：§1.3.6（HTML 正则同款 + 同款静默）✅ 逐字节一致（§7.4.4）+ `<span>` 残余格保留；
GAP-002（指针异常不得静默）✅ 由 M2/M3 两格钉住。

### 7.5 U5 · `progress` 子命令（M0 核心，11 个分支）

**设计：依赖注入。**`Run(args, stdout, stderr, Deps)`，`Deps` 的每个协作者都是函数；生产接线只有
`DefaultDeps()` 一处。理由**不是**"方便测试"，而是**两条 notice 分支用真 git 到不了**——真 git 要么可用、
要么这台机器坏了。不注入则「git 不可用」「金丝雀不可信」两条**永不执行**，而永不执行的分支与
写错了的分支**在观测上同形**（D3）。与此配套，`TestRunSandbox*` 用**真 git + 真共享库**跑同一套分支，
补上"单测全绿但生产接线没接对"那一类缺口。

| 文件 | 改动 |
| --- | --- |
| `internal/progress/progress.go` | 新增（约 240 行）：11 个分支 + `reasonTemplate`（逐字）+ `writeDecisionBlock`。 |
| `internal/progress/progress_test.go` | 新增：32 格（含 4 个沙箱子测）。 |
| `internal/mainline/mainline.go` | 新增 `ShortRef(repo, ref)`：`rev-parse --short`，**只用于措辞**，失败返回 `ok=false`（调用方回退 full id，`.ps1:349-350`）。 |
| `main.go` / `main_test.go` | 接上 `progress`；占位子命令表去掉 `progress`（6 → 5），补 2 格接线用例。 |

**分支落地对照**（§4.2.2 的 P1–P11，逐条有格）

| 分支 | 用例 |
| --- | --- |
| P1 工作区不可解析 | `TestRunP1WorkspaceUnresolved` |
| P2 指针异常（且**优先于**缺页） | `TestRunP2PointerFault` · `TestRunP2PointerFaultOutranksNoPage` · 沙箱 `P2_empty_pointer_is_a_notice` |
| P3 无进度页（且**不碰 git**） | `TestRunP3NoPage`（断言 `Probe` 未被调用） · 沙箱 `P3 no page at all is silent` |
| P4 git 不可用 | `TestRunP4GitUnusable` · 沙箱 `TestRunSandboxGitUnavailableNotice` |
| P5 金丝雀不可信 | `TestRunP5CanaryUntrustworthy` · 沙箱 `TestRunSandboxCanaryNotice` |
| P6 无仓库 | `TestRunP6NoRepo` · `TestRunP6NoRepoIgnoresMainline` · 沙箱 `TestRunSandboxNoRepoIsSilent` |
| P7 主干三级全不中 | `TestRunP7MainlineUnresolved` · `TestRunP7MainlineUnresolvedIsHonoured` · 沙箱 `TestRunSandboxUnbornRepoIsSilent` |
| P8 主干 full id 解析失败 | `TestRunP8MainlineFullIDFails` |
| P9 页面无标记 | `TestRunP9NoHeadMarker` · 沙箱 `A5 <span> restructure is silent` |
| P10 不一致 / 记录 SHA 解析不了 | `TestRunP10BlockOnMismatch` · `TestRunP10RecordedIDUnresolvable` · 沙箱 `A1` · `A4` |
| P11 一致 | `TestRunP11InSync` · 沙箱 `A2 in-sync is silent` |

**正向实测（进程内，`go test -race`）**

```
$ cd aicf-guard && gofmt -l . ; go vet ./...
（无输出）
$ go test -race -count=1 -v ./internal/progress/
--- PASS: TestRunP1WorkspaceUnresolved … TestRunSandboxCanaryNotice    # 32 格
ok  	aicf-guard/internal/progress	1.294s
$ go test -race -count=1 ./...
ok  	aicf-guard	1.023s
ok  	aicf-guard/internal/git	1.098s
ok  	aicf-guard/internal/mainline	1.152s
ok  	aicf-guard/internal/page	1.024s
ok  	aicf-guard/internal/progress	1.272s
ok  	aicf-guard/internal/sha	1.364s
ok  	aicf-guard/internal/workspace	1.065s
```

**正向实测（真二进制 × 本仓真工作区，`2026-10-28T08:5xZ`）**

```
$ go build -C aicf-guard -ldflags "-X main.version=v0.1.0 -X main.commit=$(git rev-parse --short HEAD)" -o /tmp/aicf-guard .
$ /tmp/aicf-guard --version
aicf-guard v0.1.0 (229c11d)          # exit 0
$ /tmp/aicf-guard progress
（无输出）                            # exit 0 —— 本仓页面与主干一致
$ git symbolic-ref --quiet refs/remotes/origin/HEAD
refs/remotes/origin/main             # exit 0 ⇒ 主干走【级 1】
$ git rev-parse --short main
8e744cd                              # 页面 <div>head <b>8e744cd</b> ⇒ 一致 ⇒ 静默
```

**负向实测（真二进制 × 沙箱，同一份真页面的副本改一个 SHA）**

```
$ /tmp/aicf-guard progress --workspace "$sb"     # 页面 head 改成 0000000
exit=0
stdout={"decision":"block","reason":"进度页落后于主干：project-progress.html 记录的 HEAD 是 0000000，而 main 是 46a3220。请先更新该页面再结束本轮——按 AGENTS.md 的交付约定，进度页要与代码同成熟度。需要同步的内容通常包括：状态条 head、用例数、覆盖率、GAP 台账状态与图例、以及新增的提交行。"}
stderr=（空）
$ … | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["decision"])'
block                                # 单行压缩 JSON，可解析，字段名 decision/reason
```

同沙箱另三态（一次性跑完）：

```
$ 页面记录沙箱主干 c60de16 → 无输出                 exit=0
$ 指针写成 "  \n"（存在但空白）→ stderr=进度页指针异常：…   exit=1
$ 指针指向不存在的页名 gone.html → 无输出            exit=0
```

**负向（变异验证，12 条）**

| 变异 | 改法 | 实测结果 |
| --- | --- | --- |
| M1 | 指针故障不再报（GAP-002 复发） | `TestRunP2PointerFault` · `…OutranksNoPage` · 沙箱 `P2` 三格 FAIL |
| M2 | 指针故障让位于缺页（分支顺序反转） | `TestRunP2PointerFault` FAIL |
| M3 | git 不可用走静默 | `TestRunP4GitUnusable` · 沙箱 `GitUnavailableNotice` FAIL |
| M4 | 删掉金丝雀 | `TestRunP5CanaryUntrustworthy` · 沙箱 `CanaryNotice` FAIL |
| M5 | 无仓库不静默 | 首轮**存活** ⇒ 用例改法后 `TestRunP6NoRepoIgnoresMainline` FAIL |
| M6 | 主干全不中当作落后（GAP-012 噪声复发） | 首轮**存活** ⇒ 用例改法后 `TestRunP7MainlineUnresolvedIsHonoured` FAIL |
| M7 | 记录 SHA 解析失败 ⇒ 静默（**V13 形态**） | `TestRunP10RecordedIDUnresolvable` · 沙箱 `A1`/`A4` FAIL |
| M8 | reason 不点名主干（写死"当前 HEAD"，**GAP-031 措辞回归**） | 4 格 FAIL |
| M9 | `ShortRef` 失败时不回退 full id | 首轮**存活** ⇒ 补 `TestRunShortRefFailureFallsBackToFullID` 后 FAIL |
| M10 | `--workspace` 不传给 `Resolve` | 5 格 FAIL |
| M11 | 多余参数静默吞掉 | `TestRunUnexpectedArgumentIsUsageError` FAIL |
| M12 | JSON 用默认编码器（HTML 转义） | `TestBlockJSONShapeNoHTMLEscaping` FAIL |

> **三条首轮存活的根因是同一个，值得记下**：M5/M6/M9 的用例**写了，但断言不可能失败**——
> M5/M6 的 stub 让 `ResolveFull` 对**任何** id 都返回同一个 full id，于是"不一致"永远不成立，
> 删掉静默分支后流程照样走到 `EqualFull(a,a)==true` → 静默 → **用例仍绿**；M9 的 `ShortRef` 在 stub 里
> 恒返回可用值，回退路径**从未被走到**。**「有测试」与「测试能失败」是两件事**（D3）——
> 这正是变异测试相对覆盖率的价值：三条都被覆盖率算作"已覆盖"。

**测试自身的两处修正（如实记）**

1. `TestRunSandboxGitUnavailableNotice` 首版把零字节 `git` 写成 **0644**，结果**输出 block**——
   `exec.LookPath` 会**跳过不可执行文件**继续找下一个 `git`，于是跑的是真 git。改 **0755**（可解析、但启动即失败）
   后落到 notice 分支。这条与 ADR §1.3.1 记录的「零字节 exe」形态一致，且是 Go 侧与 PowerShell 的
   **一处语义差异**（`Get-Command` 不检查可执行位）：结论不变（fail-closed），但**原因不同**。
2. `TestRunSandboxFeatureBranchComparesMainline` 首版断言 `"main"` 带引号（JSON 为中文未转义，`main` 是裸词），
   改为锚定 `而 main 是` 后通过。

**判据不变量对照（ADR §1.3）**：§1.3.1 THE ONE RULE ✅（本包**零** `git.Checked` 调用，只经共享库）；
§1.3.2 探针+金丝雀 ✅（M3/M4）；§1.3.4 主干三级 + reason 点名 ✅（M6/M8）；§1.3.5 SHA 双侧归一 ✅（M7）；
§1.3.6 正则同款静默 ✅（沙箱 A5）；GAP-002 指针异常 ✅（M1/M2）；GAP-012 unborn 静默 ✅（M6）。

### 7.6 U6 · 对拍 harness（`internal/parallel` + `tools/parallel`）

> ## ⚠️ 对拍准出：**未验证**（本机无 PowerShell 运行时）
>
> `command -v pwsh` ⇒ exit 1 · `command -v powershell` ⇒ exit 1（`2026-10-28` 实测，两次独立确认）。
> **本节任何一条读数都不得被读成「Go 版与 .ps1 逐字节一致」**。harness 在无 oracle 时的
> verdict 是 **`SKIP`**，**不是 `PASS`**，且二者 exit code 不同（2 vs 0）。

#### 7.6.1 设计（为什么是"可注入 oracle"而不是"写死跑 .ps1"）

| 判据 | 实现 |
| --- | --- |
| 有 oracle ⇒ 真对拍 | `-oracle <pwsh 路径>`：每场景各建一个沙箱跑两路，**exit / stdout / stderr 三者逐字节比**（stderr 与 stdout **分开**捕获——契约里 block 走 stdout、notice 走 stderr，合并就抹掉了被比的那件事） |
| 无 oracle ⇒ 明确 SKIP | 每场景一行 `SKIP <名> — oracle not configured…；parity is UNVERIFIED`，末行 `VERDICT SKIP` |
| **跳过与通过必须可区分** | exit code：`0 PASS · 1 DIFF · 2 SKIP · 3 ERROR`（`RunKind.ExitCode()`）。`go test` 只能出 0/1，故另设 `tools/parallel` 可执行入口 |
| 场景清单先于 oracle 就位 | 14 个具名场景（A1–A13 + P2/P3/P6/P4-P5），每个带**输入配方 + 期望 exit/stdout/stderr** |
| 沙箱两侧**可逐字节比** | fixture 提交钉死 `GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE`（`fixtureDate`）——否则两侧 commit id 不同，而 block 的 `reason` **内嵌** short SHA（`.ps1:403`），会因与移植无关的原因"不等" |

**为什么不是 `aicf-guard` 的子命令**：ADR §2.1 明文「除 `--version` 外不发明新子命令名」，迁移期子命令名
须与 `.ps1` 一一可比。故 harness 是独立的开发工具 `aicf-guard/tools/parallel`。

**为什么要 `.ps1` 副本放在沙箱的 `.claude/hooks/` 下跑**：`.ps1` 从**自身路径**推工作区
（`Split-Path -Parent $PSCommandPath`，`.ps1:185`）。在别处启动它会解析到另一个工作区，比的就是错的东西。
调用参数用**与 hook 配置相同的** `-NoProfile -ExecutionPolicy Bypass -File`（取自 `.claude/settings.json`）。

#### 7.6.2 正向实测（无 oracle —— 本机唯一可跑的形态）

```
$ go build -C aicf-guard -o /tmp/aicf-guard .
$ go build -o /tmp/aicf-parallel ./tools/parallel     # 在 aicf-guard/ 下
$ /tmp/aicf-parallel -guard /tmp/aicf-guard
SKIP  A1 正控 页面存在+错SHA → decision:block — oracle not configured (set AICF_ORACLE); the .ps1 was NOT run, so parity is UNVERIFIED
SKIP  A2 对照 页面存在+SHA一致 → 静默 — …
…（14 行 SKIP）…
VERDICT SKIP — 14 scenario(s)
$ echo $?
2                                                     # ← SKIP ≠ PASS（PASS 是 0）
```

> ⚠️ 用 `go run ./tools/parallel` 时 shell 看到的是 **1**（`go run` 把子进程的 2 归一成 1 并打印
> `exit status 2`）。**必须用编译后的产物**才拿得到 2/3 的区分——这一点已实测，写在这里免得下一个人误读。

#### 7.6.3 负向实测（harness 自身有牙：DIFF 与 ERROR 都能报出来）

没有 PowerShell 时，**"harness 能不能报出不一致"**必须用假二进制证明，否则它可能只会永远 SKIP。

```
$ /tmp/aicf-parallel -guard /tmp/aicf-guard -oracle /nonexistent/pwsh -legacy ../.claude/hooks/check-progress.ps1
VERDICT ERROR — scenario "A1 …" (oracle side): fork/exec /nonexistent/pwsh: no such file or directory
$ echo $?
3                                                     # ← oracle 配了但跑不起来 = ERROR，不是 SKIP/PASS
```

`go test` 侧另有 5 格直接证明 verdict 可区分（假二进制对打）：

| 用例 | 注入 | 期望 |
| --- | --- | --- |
| `TestRunDiffWithDivergingOracle` | go 打印 `from-go`、oracle 打印 `from-ps1` | `DIFF`，且 `Summary()` 同时列出两侧 |
| `TestRunExitCodeDifferenceDetected` | 输出相同、**exit 不同** | `DIFF`（stdout 不是全部契约） |
| `TestRunPassWithMatchingOracle` | 两侧完全一致 | `PASS` |
| `TestRunSkipWithoutOracle` | 不配 oracle | `SKIP`，且 exit code **≠** PASS 的 |
| `TestRunAllSkippedScenariosStaysSkip` | 唯一场景被平台门禁跳过 | **仍是 `SKIP`**（不能因"比过了 0 条"而转绿） |
| `TestRunExpectationViolationIsError` | Go 侧违反自己写下的期望 | `ERROR`——**无 oracle 时的运行不是空跑** |

#### 7.6.4 在有 PowerShell 的机器上复跑的确切命令

```bash
# 1) 取回原实现作为 oracle（U7 已把它移到 legacy 文件；见 §7.7）
git show 8e744cd:.claude/hooks/check-progress.ps1 > .claude/hooks/check-progress.legacy.ps1

# 2) 构建 + 对拍
cd aicf-guard
go build -o /tmp/aicf-guard .
go build -o /tmp/aicf-parallel ./tools/parallel
/tmp/aicf-parallel -guard /tmp/aicf-guard \
    -oracle "$(command -v pwsh || command -v powershell)" \
    -legacy ../.claude/hooks/check-progress.legacy.ps1
echo "exit=$?"     # 0 = 逐字节一致（准出）；1 = 有差异（阻断）；3 = harness/oracle 出错
```

**判据**：`exit=0` **且**末行 `VERDICT PASS` 才算对拍准出。出现任何 `DIFF` ⇒ 该 PR 阻断（ADR §2.5）。
**本机无法执行此命令**——`pwsh`/`powershell` 均不存在，故**M0 的对拍准出保持未验证**。

**判据不变量对照（ADR §2.5 / §6.1）**：对拍**未满足**（不是"不适用"）——按 `AGENTS.md` §2，对应物存在、
判据存在、但**本机无运行时**，故记为「未验证 + 原因」，交三跳链裁决。

### 7.7 U7 · `.claude/hooks/check-progress.ps1` → 薄转发层

> ⚠️ **本机无 PowerShell，本节全部结论均为静态核对。** 不得读成"已跑通"。

**改了什么**

| 文件 | 动作 |
| --- | --- |
| `.claude/hooks/check-progress.legacy.ps1` | **新增**：迁移前原实现，**逐字节相同**（`git hash-object` 两侧同为 `2b1908e8…`，见下）。它是**对拍的 oracle**，**不接任何 hook**。 |
| `.claude/hooks/check-progress.ps1` | **重写为转发层**（413 → 98 行；`git diff --stat` = `85 insertions(+), 388 deletions(-)`）：定位同目录 `aicf-guard`(/.exe) → `& $bin progress --workspace $ws` → `exit $LASTEXITCODE`。文件头保留：发布契约、THE ONE RULE 与"失败即静默"的警告、被删除的 PowerShell 特有理由、两用例验证要求。 |

**legacy 逐字节性（oracle 可信的前提）**

```
$ git show HEAD:.claude/hooks/check-progress.ps1 | git hash-object --stdin
2b1908e8e30272f80eb376135c0db75a873a301b
$ git hash-object .claude/hooks/check-progress.legacy.ps1
2b1908e8e30272f80eb376135c0db75a873a301b          # 同一 blob ⇒ 同一份实现
$ wc -l .claude/hooks/check-progress.legacy.ps1
413 .claude/hooks/check-progress.legacy.ps1
```

**静态核对（本机唯一能做的验证）**

| 判据 | 命令 | 实测 |
| --- | --- | --- |
| 二进制缺失 ⇒ **不静默** | `grep -n -A1 '缺失（aicf-guard'` | `[Console]::Error.WriteLine("进度页守卫未运行：…缺失…")` 紧接 `exit 1` ✅ |
| 转发层**无** `exit 0` 执行路径（失败绝不 open） | `grep -v '^\s*#' … \| grep -c 'exit 0'` | `0` ✅ |
| 退出码 ⊆ adapter 覆盖（self-test 的 **D3** 格） | `grep -o 'exit\s*[0-9]*'` | 执行路径只有 `1`（外加 `exit $LASTEXITCODE` 透传 0/1）⇒ D3 仍 **PASS** ✅ |
| 守卫逻辑已**完全**移出（不留第二实现，D4） | `grep -c 'Invoke-GitChecked\|symbolic-ref\|progress-page.txt\|\[regex\]::Match'` | `0` ✅ |
| 工作区推导仍按**脚本自身位置**（不依赖 CWD） | 读码 | `Split-Path -Parent` 两级，与 legacy 第 185 行同源 ✅ |
| 二进制不入库（ADR §6.8） | `go build -C aicf-guard -o ../.claude/hooks/aicf-guard .` 后 `git status --porcelain` | 只出现 ` M check-progress.ps1` 与 `?? check-progress.legacy.ps1`，**二进制不出现** ✅ · `git check-ignore -v` 命中 `.gitignore:36` |

**oracle 怎么取回（三法，任一等价）**

```bash
git show 8e744cd:.claude/hooks/check-progress.ps1 > /tmp/check-progress.ps1   # ① 迁移前的提交
git show HEAD~1:.claude/hooks/check-progress.ps1 > /tmp/check-progress.ps1    # ② 上一个提交
cp .claude/hooks/check-progress.legacy.ps1 /tmp/check-progress.ps1           # ③ 仓内留下的副本
```

**未做的（有意，附理由）**

1. **不动 `.claude/settings.json` / `.agents/hooks.json`** —— 切 hook 配置是 **M4**（ADR §3），且本机也无
   PowerShell，改了无法验证。故本提交**不声称 Linux 上守卫已恢复**——它仍是 `powershell …`，仍 exit 127。
2. **不改 `self-test.ps1`** —— 它的 A 组现在指向**转发层**，在**有二进制**的机器上行为不变（转发层透传），
   在**无二进制**的机器上会走 `exit 1` notice（A1/A4/A8/A10/A12/A13 会 FAIL，A2/A3/A5/A7 仍 PASS）。
   **这是既有格子的预期变化**，应由下一轮在有 PowerShell 的机器上实测后裁决，不在本次"顺手改尺子"（D3：实现方不自审判据）。
3. **`README.md` / `.claude/hooks/README.md` 的描述未改** —— 它们描述的是**规则**（权威源在 `AGENTS.md` §5），
   而 §5 未变。转发层是**实现细节**，已在文件头写明。

**⚠️ 交给门禁的残余（本单元发现，**不自行拍板**）**

ADR §3 规定「二进制缺失 ⇒ 按原『git 不可用』分支处置（`exit 1` + stderr）」。本次**照此实现**。但该分支在
**Antigravity 侧会被降级**：`.agents/hooks/stop-adapter.ps1:54-59` 把 `exit≠0 + stderr` 转成非阻断的
`{"decision":"continue"}` ⇒ **在 Antigravity 上删掉二进制，守卫会静默退役（只留一句 notice）**。

| 候选处置 | 后果 | 谁定 |
| --- | --- | --- |
| 维持现状（照 ADR） | Antigravity 侧缺二进制 = 非阻断 | 本单元默认 |
| 用 `{0,1}` 之外的退出码（如 2）并让 adapter 视为致命 | 更强，**但** self-test 的 **D3 格会 FAIL**（adapter 未覆盖 2），且**改发布契约** | **待总控 / `gate-auditor` 裁定**——属契约变更，不是实现细节 |

> 我**先按 ADR 实现、再上报**，而不是按自己的判断改成 exit 2：ADR 是 Accepted 的，改它要走 ADR 修订；
> 且 exit 2 会让 D3 格立刻变红——那是一个**必须由门禁看见**的信号，不该由实现方顺手抹平。

**判据不变量对照（ADR §3 薄转发层契约）**：fail-closed ✅（静态核对第 1、2 行）；不静默 ✅；
守卫逻辑唯一实现 ✅（D4）；**"二进制缺失"这一格的实机验证 = 未做**（无 PowerShell）。


---

## 八、M0 收尾：提交序列与判据状态（**非准出裁决**）

### 8.1 提交序列（`8e744cd` = M0 起点，ADR Accepted 后的 merge 提交）

| # | 提交 | 单元 | 核心内容 |
| --- | --- | --- | --- |
| 1 | `0cbfd7f` | 1/2 地基 | `go.mod`（`go 1.21`，零外部依赖）· `main.go` + `--version` · `.gitignore` |
| 2 | `918eb68` | 1/2 地基 | `internal/git`：`Checked`/`Probe`/`Canary`（THE ONE RULE） |
| 3 | `87abad3` | U1 | `internal/sha`：`ResolveFull`/`EqualFull`/`Compare` |
| 4 | `cb3f225` | U2 | `internal/mainline`：三级回退 + `ShortRef`；补「级 1 非 commit」格 |
| 5 | `ea55806` | U3 | `internal/workspace`：`ResolveFrom` + `FindPage` |
| 6 | `229c11d` | U4 | `internal/page`：复核 `first1/second2` 修法 + `ReadPageName` |
| 7 | `eecc81f` | U5 | `internal/progress`：11 个分支 |
| 8 | `805c942` | U6 | `internal/parallel` + `tools/parallel`：对拍 harness |
| 9 | `0943e49` | U7 | `check-progress.ps1` → 薄转发层 + `check-progress.legacy.ps1` |

每个提交单独 `go vet ./... && go test -race ./...` 全绿；每单元一次变异验证（共 **6+6+7+8+12** 条实现变异 +
harness 自身 11 格），读数分别在 §7.1–§7.6。

### 8.2 判据状态（**逐条如实，交 `gate-auditor` 裁决**）

| ADR 判据 | 状态 | 依据 |
| --- | --- | --- |
| `progress` 11 个分支对齐 `.ps1` | ✅ **代码级已对齐** | §4.2.2 表 × §7.5 对照表，每分支具名用例 |
| 共享库 5 件 + 新 2 件单测（含负向） | ✅ | §三 表 3.2 · §7.1–§7.6 |
| 判据不变量 §1.3.1–§1.3.6 | ✅ | §三 表 3.3 · 各节「判据不变量对照」 |
| `.gitignore` 排除（§6.8 R10） | ✅ | §三 行 19–21（实测 5 条规则、二进制不入库） |
| `--version`（§2.1 R4） | ✅ | §三 行 2–3 |
| **同沙箱对拍逐字节一致（§2.5 / §6.1）** | ⛔ **未验证** | 本机无 PowerShell。装置就绪，复跑命令 §7.6.4 |
| **selftest A 组全 PASS（§3 M0 准出）** | ⛔ **未验证** | 同上：尺子本身是 `.ps1`，本机跑不了；且 A 组的对象已变为转发层（§7.7「未做的」2） |
| 薄转发层 fail-closed | 🟡 **静态已核，未实机** | §7.7 静态核对 6 条；实机待在装有 PowerShell 的机器上验 |
| selftest 新增「二进制缺失」格（§6.6） | ⛔ **未实现** | 属 M3（selftest 子命令）。ADR §3 把它列为 **M0 准出**——**这是一处 M0 范围内未完成项**，如实登记，不辩称"不适用" |
| 跨平台构建（§6.2） | ✅ | `for t in linux/amd64 linux/arm64 darwin/amd64 darwin/arm64 windows/amd64; do GOOS=… GOARCH=… CGO_ENABLED=0 go build -o /tmp/…; done` ⇒ **5/5 exit 0**，`file` 逐条确认：`ELF 64-bit LSB … statically linked`(×2) · `Mach-O 64-bit`(×2) · `PE32+ executable (console) x86-64` |

**结论（实现方口径，不是准出）**：M0 的**代码与本地验证**部分完成；**对拍、selftest A 组、
「二进制缺失」格** **三项未完成/未验证**（跨平台构建已实测通过，见上表）。按 `AGENTS.md` §2，M0 准出**未满足**，
不得直接进 M1——需 `gate-auditor` 就「哪些可带条件放行、哪些必须补」出具裁决。

### 8.3 待总控裁定（实现方不得自行拍板）

1. **对拍准出**：本机缺 PowerShell。是（a）在有 PowerShell 的机器/CI 上补跑，还是（b）登记为
   `DEFER-` 并给 M1 让路？——**影响 M0 是否可准出**。
2. **Antigravity 侧「二进制缺失 = 非阻断」残余**（§7.7）：维持 ADR 的 `exit 1`，还是改成
   `{0,1}` 之外的退出码并扩展 adapter（**改契约**，且会让 self-test 的 D3 格 FAIL 直到 adapter 跟上）？
3. **selftest「二进制缺失」格**：ADR 把它列为 M0 准出，但 selftest 子命令在 M3。是把它拆成
   「先给 `.ps1` 加一格」还是顺延到 M3 并在 ADR 上修正？——**这是 ADR 内部的一处张力**（§3 M0 准出 vs §8.1 的 M3 范围）。
4. **`docs/changes/005` 的编号归属**：005 现同时承载「M0 地基 1/2」（已入库）与「第 2/2 次派发」。
   若总控认为应拆成 005 / 006 两份记录（ADR §8.1 的「一阶段一号」口径），**拆分应由总控做**——
   实现方不擅自改编号空间（`AGENTS.md` §6.1）。

---

## 九、人工裁定（`2026-10-28`，总控记录）——§8.3 四项的处置

> 本节由**总控**回填（实现方不得自裁，见 §8.3）。裁定来自用户，四项**逐条落地**。

| §8.3 项 | 裁定 | 落点 |
| --- | --- | --- |
| **1 对拍准出** | **登记 `DEFER-` 后放行**——但禁止把「跳过」读成「通过」 | `DEFER-019`（台账）· 本文件 §8.2 的 ⛔ 改为「按裁定顺延」· harness 的 `SKIP`(2)/`PASS`(0)/`DIFF`(1)/`ERROR`(3) 四码互异（§7.6 已实现）· **issue #69** |
| **2 Antigravity 侧 notice 降级** | **维持 ADR，不改契约，登记缺口** | `GAP-046`（台账）· 本文件 §7.7 的残余保留 |
| **3 「二进制缺失」格归属** | **顺延 M3 + 修 ADR** | `DEFER-020`（台账）· ADR-001 §3 M0 行、§8.1 M0 行、§6.6 均已加修订注 |
| **4 005 编号归属** | **不拆**——`docs/changes/005` 继续同时承载两次派发 | 本文件；ADR §8.1 的「一阶段一号」是**预计起点的提示**，非硬性拆分要求 |

### 9.1 总控在裁定后**追加发现**的一处更严重缺陷（登记为 `GAP-046` 的主条）

实现方把 item 2 描述为「**Antigravity 侧**的降级」。总控复测后认为范围更大：
**Claude Code 宿主侧同样看不见 notice**。证据（D1，`2026-10-28` 实跑）：

```
$ CLAUDE_PROJECT_DIR=$PWD bash -c 'powershell -NoProfile -ExecutionPolicy Bypass \
    -File "$CLAUDE_PROJECT_DIR/.claude/hooks/check-progress.ps1"'
bash: 行 1: powershell: 未找到命令
EXIT=127
```

随后**同一回合照常结束，用户侧零提示**。`.claude/settings.json` 的 Stop hook **只读 stdout 的 JSON**；
`exit 1 + stderr` 既不放进 reason、也不阻断。⇒ 在 `check-progress.ps1` 的**全部 413 行都不曾执行**的状态下，
宿主与「守卫跑过且判放行」**观测同形**。

**这是本仓「刻意静默 vs 已死」家族（`GAP-002`）在宿主层的同形复发**：`AGENTS.md` §5 与 `.ps1` 头注都
断言「notice 用户看得见」，该断言**从未被验证**，本条即其证伪。

### 9.2 本次未做的（如实）

- **未切 `.claude/settings.json`**（M4 范围）⇒ **Linux 上的守卫仍未恢复**（仍`powershell …` → 127）。用户痛点**未解除**。
- **未实跑对拍**（`DEFER-019`）· **未实跑 selftest A 组**（本机无 PowerShell）。
- **未改 `.agents/hooks/stop-adapter.ps1`**（`GAP-046` 的②，契约变更，需另立 PR）。

---

## 十、qa-validator 第 1 跳后的修复（`2026-10-28T09:56Z`，实现方回填）

> 03 环第 1 跳（`qa-validator`）裁决「需修复后提交」。本节逐条写：**缺陷 → 修法 →
> 正/负向实测命令与读数**。范围严格限制在下表 8 项，**未扩大**。
>
> 三条**人工已裁定、本次不动**的项：`DEFER-019`（对拍顺延）· `GAP-046`（notice 降级维持 ADR）·
> `DEFER-020`（selftest「二进制缺失」格顺延 M3）。

### 10.1 提交序列（一缺陷一提交）

| # | 提交 | 对应 qa 项 | 单元 |
| --- | --- | --- | --- |
| 1 | `a6f5f86` | P1-1 | `progress` 参数错误 `exit 2` → `exit 1` + stderr |
| 2 | `791aefb` | P2-1（总控裁定①） | 被拒绝的 `--workspace` → `exit 1` + stderr |
| 3 | `00f057f` | P1-3 / `GAP-047` | 页名指针剥前导 UTF-8 BOM |
| 4 | `240faaa` | P2-2 | 空白类注释收窄到实测（只改注释 + 测试） |
| 5 | `4ee1cf0` | P1-5 | harness 违约不再中断；摘要分列 `COMPARED` / `SKIPPED` |
| 6 | `96e52ce` | P1-6 | `A4` 双属性页面 + 新增 `A4b` |
| 7 | `ddc53f9` | P2-6 | 沙箱钉死 `--object-format=sha1` 与签名关闭 |
| 8 | `8952fd4` | P2-3（总控裁定） | 双标记页「结论依赖顺序」注释 + 双向测试，**不改行为** |

### 10.2 逐条：缺陷 → 修法 → 正/负向读数

#### F1 · `progress` 的退出码越出 `{0,1}`（qa P1-1，最重）

- **缺陷**：`progress --bogus` / `progress --workspace`（缺值）/ `progress extra` 均 `exit 2`。
  该子命令是 Stop hook，退出码由**宿主**读：Claude Code 的 Stop 事件不定义 2；
  `stop-adapter.ps1:56-74` 对已知集之外的退出码落 `allow`（`self-test.ps1:1078` 已写明）。
  ⇒ **参数写错 = 守卫静默放行**。
- **修法**：旗标解析失败改走「守卫跑不起来」同一通道（`exit 1` + stderr），措辞标明是用法错误且守卫未运行。
  `--version` / `-h` 顶层行为不动。
- **正向**：
  ```
  $ for a in "--bogus" "--workspace" "extra"; do /tmp/aicf-f1 progress $a; echo "exit=$?"; done
  flag provided but not defined: -bogus
  … aicf-guard progress: usage error: flag provided but not defined: -bogus
  (the guard did NOT run; run `aicf-guard progress --help` for usage)
  exit=1        ← 修复前为 2
  ```
  `go test -race -count=1 ./internal/progress/ ./` → `ok` / `ok`
- **负向（变异，均 FAIL）**：
  | 变异 | 触发的格 |
  | --- | --- |
  | 旗标错误恢复 `return 2` | `TestRunUsageErrorsExitOne`（unknown flag / missing value）、`TestRunNeverReturnsTwo` |
  | 多余位置参数恢复 `return 2` | 同上（3 处 FAIL） |
- **覆盖**：`TestRunNeverReturnsTwo` 用**表驱动枚举 10 类调用**（help×2 / 未知旗标 / 缺值 / 多余位置 /
  静默 / 指针 notice / git notice / 拒绝 `--workspace` / block），断言**任何路径都不返回 2**
  且落在 `{0,1}`；这是「不许再有第三个 `return 2`」的可检查形态。
- **边界（本 ADR 之外，必须写明）**：`main.go` **顶层** `run` 对「无参数」「未知子命令」仍返回 **2**。
  这两条**不进 hook 链路**（hook 调的是 `progress`），故不受本契约约束；但读者不应据此以为「整个 CLI 只有 `{0,1}`」。
  本节的契约是**子命令级**的。

#### F2 · 页名指针带 UTF-8 BOM ⇒ 守卫静默退役（qa P1-3 / `GAP-047`）

- **缺陷**：`printf '\xef\xbb\xbfproject-progress.html\n' > .claude/progress-page.txt` ⇒ `exit 0 / 空 / 空`，
  而页面明明 stale。机理：`strings.TrimSpace` 不剥 U+FEFF ⇒ 页名带 BOM ⇒ `FindPage` 两处候选都不命中。
  旧路无此缺陷（`Get-Content -Raw` 解码时剥 BOM）⇒ **这是与 legacy 的真实行为差异，修法是对齐旧路**。
- **修法**：`trimPointerName` = 剥**一个前导** BOM 后再 `TrimSpace`；BOM-only 仍走「有指针读不出名字」的 fault。
- **正向（真实二进制）**：
  ```
  BOM + 正常页名（页面 stale）  → exit 0 + {"decision":"block",…}
  BOM-only                      → exit 1 + 「进度页指针异常：…读不出页名…」
  无 BOM 对照（页面 stale）      → exit 0 + {"decision":"block",…}
  go test -race -count=1 ./...  → 全 ok
  ```
- **负向（变异）**：`trimPointerName` 改回 `return strings.TrimSpace(s)` ⇒
  `internal/page` 的 `TestReadPageNameStripsLeadingBOM` **6 个子格 FAIL**；
  `internal/progress` 的 `TestRunSandboxBranches/P2b`（BOM ⇒ 仍 block）、`/P2c`（BOM-only ⇒ notice）**FAIL**。
- **未验证**：`Get-Content` 在 `\v` / NBSP 上的具体行为**本机无 PowerShell，未实测**。
  「BOM 只在 offset 0 被消费」是**读码推理**，已在测试注释里显式标注为推理而非读数。

#### F3 · harness 提前 `return` + 摘要把 SKIP 与「从未比对」混为一个数（qa P1-5）

- **缺陷**：某场景违反自身 `Expect` 时 `return rep` ⇒ 后续场景**一条都不比**；
  末行用 `len(r.Comparisons)` ⇒ 「全 14 条跳过」与「全 14 条比过」打印同样大小。
- **修法**：① 违约记为**该场景**的 `Comparison.ExpectErr` + `Kind=ERROR`，**继续跑完**；
  仅「跑不起来」（缺二进制 / 读不了 `.ps1` / 沙箱建不起来 / 超时）仍 fatal；
  ② 摘要分列 `COMPARED n/N` / `SKIPPED k/N`，违约另计 `EXPECT-VIOLATIONS v/N` 并逐条打 `EXPECT …` 行；
  ③ **DIFF 不得把 ERROR 降级**。
- **正向**：
  ```
  $ go run ./tools/parallel -guard /tmp/aicf-f3
  … VERDICT SKIP — COMPARED 0/14, SKIPPED 14/14        ← 14 条全部被处理（修复前遇违约即止）
  ```
- **负向（变异，均 FAIL）**：违约处恢复 `return rep` ⇒ `TestRunContinuesAfterExpectationViolation`（`len=2 want 3`）
  + 计数格；摘要恢复单一 `%d scenario(s)` ⇒ `TestSummaryReportsComparedAndSkippedSeparately` ×2；
  去掉 `if rep.Kind != KindError` ⇒ 「diff never downgrades」格（`Kind=DIFF want ERROR`）。

#### F4 · `A4` 在无 oracle 时无牙（qa P1-6）

- **缺陷**：`A4` 页面用 `<b class="v">` 但 `<div>` 不带属性，而正则的属性容忍有**两半**。
  把 div 那半改成 `<div>` 的变异在无 oracle 时**静默全绿**（实测：15 条全 SKIP、exit 2，与正确实现读数相同）。
- **修法**：`A4` 改 `<div class="bar">head <b class="v">…`；新增 `A4b` 用**不同属性名**
  （`<div id="status">` + `<b style=…>`），防「只特判 `class=`」的变异同时过关；两条都断言 reason
  里的 `记录的 HEAD 是 0000000`；`progress` 包真实接线沙箱的 A4 格同步改双属性。
- **正向（无 oracle）**：`VERDICT SKIP — COMPARED 0/15, SKIPPED 15/15`
- **负向（无 oracle，注入变异）**：
  ```
  headRe 的 <div[^>]*> → <div>  → harness exit=1
    EXPECT A4 … / EXPECT A4b …
    VERDICT ERROR — COMPARED 0/15, SKIPPED 15/15, EXPECT-VIOLATIONS 2/15
  headRe 的 <b[^>]*>   → <b>    → 同上，2/15
  ```

#### F5 · 空白类注释与实现不符（qa P2-2）——**结论方向与原描述相反，已按实测改写**

- **实测（`2026-10-28`，直接跑 `unicode.IsSpace`）**：`U+000B` / `U+00A0` / `U+0085` 的 `IsSpace` **均为 true**
  ⇒ `strings.TrimSpace` **会**剥掉它们 ⇒ **Go 侧不比 .NET 窄**。原注释「Trim matches PowerShell's String.Trim()」
  不成立，但**方向与 qa 描述相反**（qa 称 Go 侧静默、.NET 侧会匹配；在 **Trim** 这一层不成立）。
- **本族真实的可测差异在上一层**——**页正则的 `\s`**：Go 的 `regexp` `\s` 只认 ASCII `[ \t\n\f\r]`，
  .NET 的 Unicode 感知。实测头正则前缀：
  ```
  "<div>\vhead"     → Go \s 不匹配（静默）
  "<div>\u00a0head" → Go \s 不匹配（静默）
  "<div>\u0085head" → Go \s 不匹配（静默）
  对照 space / tab / newline → 两侧都匹配
  ```
  与 qa 的现象读数一致，只是**原因归错了层**。
- **修法**：**只改注释 + 加测试，不改实现**（M0 目标是与旧路逐字节对齐；拓宽 `\s` 是行为变更，
  需独立决策 + 独立对拍）。归 `GAP-025` 残余，**不新开编号**。
- **正向**：`go test -race -count=1 ./internal/page/` → `ok`
- **负向（变异）**：把 `headRe` 的 `\s` 换成 Unicode 空白类 ⇒
  `TestReadHeadUnicodeWhitespaceIsASilentDivergence` 的 vtab / nbsp / nel 三格 **FAIL**（对照组三格仍 PASS）。
- **旁注**：本轮同时把「BOM 只在 offset 0 被消费」「`Get-Content` 对 `\v`/NBSP 的处理」标为**推理/未实测**。

#### F6 · fixture 只钉日期，不钉签名 / 对象格式（qa P2-6）

- **缺陷**：只注入 `GIT_AUTHOR_DATE` / `GIT_COMMITTER_DATE`。宿主配置差异 ⇒ 同配方不同 id ⇒ 假 DIFF，
  或场景直接跑不起来。
- **实测（`2026-10-28`，git 2.56.0）**：
  - `init --object-format=sha256` ⇒ `--short HEAD` 为 **8 位**、full id **64 位 hex**；
    而页正则只收 `{7,40}`、Go 侧 `fullIDRe` 只收 40 位 ⇒ 两侧对「id 能否解析」不一致。
    `--object-format=sha1` **压过** `GIT_DEFAULT_HASH=sha256`（exit 0，format `sha1`）。
  - 宿主 global `commit.gpgsign=true` + 坏 signing program ⇒ `git commit` **exit 128**；
    加 `-c commit.gpgsign=false -c gpg.format=openpgp` ⇒ **exit 0**。
- **修法**：`prepareRepo` 显式 `git init -q --object-format=sha1`；**所有** fixture git 调用统一带
  `-c commit.gpgsign=false -c gpg.format=openpgp`，并把两项写进沙箱自身 config。
  **`core.abbrev` 刻意不钉**：两侧读同一份宿主配置、影响相同，钉它反而测了生产不用的配置。
- **正向（真实二进制，宿主 hostile 配置 `GIT_CONFIG_GLOBAL=/tmp/hostile.gitconfig GIT_DEFAULT_HASH=sha256`）**：
  ```
  修前：VERDICT ERROR — COMPARED 0/1 … git commit … exit status 128: gpg 无法为数据签名
  修后：VERDICT SKIP  — COMPARED 0/15, SKIPPED 15/15
  ```
- **负向（变异，FAIL）**：去掉 `--object-format=sha1` ⇒ `object format="sha256" want sha1` / `full id … len 64 want 40`；
  去掉签名覆盖 ⇒ `fixture must survive a hostile host git config: … exit 128`。
- 另加 `TestFixtureCommitsAreDeterministic`：同配方两次 ⇒ `HEAD` 必须完全相同（否则对拍无从比字节）。

#### F7 · 被拒绝的 `--workspace` 静默退出 0（qa P2-1，**总控裁定①**）

- **缺陷**：ADR §2.3 把 `--workspace` 定为**权威覆盖**，`resolveWorkspaceLayers` 也实现了「显式给了但不是工作区 ⇒ 失败、不回退」，
  但 `decide` 随后把「Workspace 为空」一律当「未初始化」⇒ `exit 0` 静默 ⇒ 权威覆盖被拒绝却一字不报。
- **修法**：仅当 `wsFlag != ""` 时把空解析判为 notice；**自动发现找不到工作区仍静默**（那才是「未初始化」）。
- **正向**：`progress --workspace /tmp/aicf-wsneg` → `exit=1` +「--workspace 指定的目录不是工作区…」；
  在非工作区 CWD 下 `progress`（无旗标）→ `exit=0 / 空 / 空`。
- **负向（变异）**：分支改 `if false && wsFlag != ""` ⇒ `TestRunWorkspaceFlagRejectedIsNotice`（`exit=0 want 1`）
  + `main` 包 `TestProgressSubcommandBelow`（`exit=0 want 1`）。

#### F8 · 双标记页的结论依赖顺序（qa P2-3，**总控裁定：本次不改行为**）

- **裁定理由**：`[regex]::Match` 同样取第一个匹配；改了就破坏 M0 的逐字节对齐目标，会把真对拍变成假 DIFF。
- **本次只做**：`headRe` 注释写明「两个**格式正确**的标记时取第一个 ⇒ 结论是顺序的函数」，给出实测两个方向；
  新增 `TestReadHeadTwoMarkersVerdictDependsOnOrder`，**两个方向都断言**（单方向断言会被读成「正确行为的描述」）。
- **正向**：`go test -race -count=1 ./internal/page/` → `ok`
- **负向（变异）**：`ReadHead` 改成取**最后一个**标记 ⇒ 该测试两个子格 **FAIL**。

### 10.3 本轮全量读数（`2026-10-28T09:56Z`，HEAD `8952fd4`）

```
$ cd aicf-guard && gofmt -l .            → 无输出（clean）
$ go vet ./...                           → exit 0
$ go test -race -count=1 ./...
ok   aicf-guard                    1.033s
ok   aicf-guard/internal/git       1.112s
ok   aicf-guard/internal/mainline  1.162s
ok   aicf-guard/internal/page      1.033s
ok   aicf-guard/internal/parallel  1.762s
ok   aicf-guard/internal/progress  1.305s
ok   aicf-guard/internal/sha       1.363s
ok   aicf-guard/internal/workspace 1.064s
?    aicf-guard/tools/parallel     [no test files]
```
`go test -count=1 -v ./...` 计数：**顶层 PASS 139 · 子测试 PASS 89 · FAIL 0**。

### 10.4 本轮**仍然未验证**的项（如实，不得读成已通过）

| 项 | 状态 | 原因 |
| --- | --- | --- |
| **对拍（Go vs `.ps1` 逐字节）** | ⛔ **未验证**（`DEFER-019`） | 本机无 `pwsh`/`powershell`。本轮**未**、也**不能**声称对拍通过；`A4/A4b` 的牙是**无 oracle 下对变异**的读数，不是对拍 |
| **`selftest.ps1` A 组实跑** | ⛔ **未验证** | 尺子本身是 `.ps1`，本机跑不了 |
| **薄转发层实机行为** | ⛔ **未验证**（沿用 §7.7 / §9.2） | 需装有 PowerShell 的机器 |
| **`Get-Content` 对 BOM / `\v` / NBSP 的真实处理** | 🟡 **推理，未实测** | 同上；已把该推理在代码注释与测试注释里显式标注 |
| **`GAP-046` / `DEFER-020`** | 按人工裁定**不动** | 见 §九 |
| **顶层 CLI 仍返回 2** | 刻意保留 | 不进 hook 链路；边界已在 §10.2 F1 写明 |

> **范围声明**：本轮只改 `aicf-guard/` 内 6 个文件 + 本节。未改 `memory.md` / `progress.html` /
> `record.md` / `docs/ledger.md` / ADR，未 push、未建 PR。
