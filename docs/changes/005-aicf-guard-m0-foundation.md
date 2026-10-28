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

### 3.1 module 骨架 + `--version`

| # | 判据 | 命令 | 预期 | 实测 |
| --- | --- | --- | --- | --- |
| 1 | module 编过 | `cd aicf-guard && go build ./...` | exit 0 | 待回填 |
| 2 | 默认 `--version`（未注入） | `cd aicf-guard && go build -o /tmp/ag . && /tmp/ag --version` | `aicf-guard dev (unknown)` + exit 0 | 待回填 |
| 3 | 注入 `--version` | `cd aicf-guard && go build -ldflags "-X main.version=v0.1.0 -X main.commit=test1234" -o /tmp/ag . && /tmp/ag --version` | `aicf-guard v0.1.0 (test1234)` + exit 0 | 待回填 |
| 4 | 无参数 | `/tmp/ag` | exit 2 + usage on stderr | 待回填 |
| 5 | 未知子命令 | `/tmp/ag bogus` | exit 2 + stderr | 待回填 |
| 6 | 占位子命令 | `/tmp/ag progress` | exit 1 + stderr（not implemented） | 待回填 |
| 7 | `go.mod` 最低版本 | `head -1 aicf-guard/go.mod` | `go 1.21`（实测抬高了则记） | 待回填 |

### 3.2 共享库 6 件单测（含负向，D3）

| # | 包 | 关键用例（正向 + 负向） | 命令 | 预期 | 实测 |
| --- | --- | --- | --- | --- | --- |
| 8 | `internal/git` | `Probe()` true · `Canary()` true · `Checked` exit=0 / exit≠0 · **`GIT_DIR`+`GIT_OBJECT_DIRECTORY` 劫持不被劫持（GAP-013①/GAP-031）** · `filterGitFamily` 9 个全滤 | `go test -race ./internal/git/` | PASS | 待回填 |
| 9 | `internal/workspace` | 旗标覆盖 · 旗标无效 · `CLAUDE_PROJECT_DIR` · exe 回推 · CWD 回退 · 优先级（旗标>CPD>exe>cwd）· repo `@[ws,ws/project]` ws 优先 · 无 repo | `go test -race ./internal/workspace/` | PASS | 待回填 |
| 10 | `internal/mainline` | **三级回退各分支**：origin/HEAD 命中 / main 兜底 / HEAD 兜底（Name 点名）/ unborn 全不中 | `go test -race ./internal/mainline/` | PASS | 待回填 |
| 11 | `internal/sha` | 短前缀+full id 一致 · **真前缀+假后缀（40 位）不一致（GAP-008）** · 不存在的 SHA ⇒ false · 大小写 | `go test -race ./internal/sha/` | PASS | 待回填 |
| 12 | `internal/page` | 无属性 / `b[class]` / `b[style]` / `div[class]` / 两侧空白 · **缺页/无标记 ⇒ 同款静默** · `<span>` 重构 ⇒ 静默（GAP-025 残余）· 7 位下界 / 6 位不匹配 | `go test -race ./internal/page/` | PASS | 待回填 |

### 3.3 判据不变量（ADR §1.3，不得破坏）

| # | 不变量 | 验证方式 | 实测 |
| --- | --- | --- | --- |
| 13 | **THE ONE RULE**：git 调用判据是退出码 | 全仓 grep `\.Exit` —— 仅 `internal/git` 包内 + 各调用方判 `.Exit == 0`/`!= 0`，无第二处读 git exit code | 待回填 |
| 14 | 负向金丝雀 | `Canary()` 单测：`git rev-parse --verify 0000…^{commit}` exit≠0 | 待回填 |
| 15 | `GIT_*` 族（9 个）清空 | `filterGitFamily` 单测：9 个全滤；`Checked` 集成：注入 `GIT_DIR`+`GIT_OBJECT_DIRECTORY` ⇒ 不被劫持 | 待回填 |
| 16 | 主干三级回退 reason 点名 | `mainline` 单测：HEAD 兜底 Name = `HEAD（未找到主干）` | 待回填 |
| 17 | SHA 双侧归一 full id 再比 | `sha` 单测：真前缀+假后缀（40 位）⇒ false | 待回填 |
| 18 | HTML 正则同款 | `page` 单测：正则与 `check-progress.ps1:375` 逐字一致（`<span>` 仍静默） | 待回填 |

### 3.4 `.gitignore` 同步（ADR §6.8 R10）

| # | 判据 | 命令 | 预期 | 实测 |
| --- | --- | --- | --- | --- |
| 19 | 排除规则就位 | `grep -n aicf-guard .gitignore` | 3 行（`/aicf-guard/bin/` · `/.claude/hooks/aicf-guard` · `/.claude/hooks/aicf-guard.exe`）+ 注释 | 待回填 |
| 20 | 源码入库 | `git ls-files aicf-guard/` | `go.mod`/`main.go`/`main_test.go`/子包源码（**不**含 `bin/`） | 待回填 |
| 21 | 本地 build 后无残留 | `go build -o .claude/hooks/aicf-guard ./aicf-guard/ && git status --porcelain` | 无 `.claude/hooks/aicf-guard`（被忽略） | 待回填 |

---

## 四、负向证伪检验（§3 第 4 段，D3）

> 本单元的负向用例**已在 §三 的单测里逐条具名**（上表「负向」列）。此处归纳「注入什么故障能让判据静默通过」——每条都对应一个测试。

| 证伪点 | 注入什么 | 必须的表现 | 对应测试 |
| --- | --- | --- | --- |
| `GIT_DIR` 劫持（GAP-013①） | `GIT_DIR=<他仓>` + `GIT_OBJECT_DIRECTORY=<他仓>` 后调 `Checked("-C", B, ...)` | 读数是 B 不是他仓（exit 0 且 Text=B 的 HEAD） | `TestCheckedFiltersGitEnvFamily` |
| 金丝雀失效（ADR §1.3.2） | `git rev-parse --verify 0000…^{commit}` | exit≠0（`Canary()` 返回 true=可信） | `TestCanary` |
| SHA 前缀比对（GAP-008） | 真前缀 `8e744cd` + 假后缀（40 位）vs 真 full id | `Compare` 返回 **false**（不因前缀相同而判一致） | `TestCompareFakeSuffix` |
| HTML 正则盲区（GAP-025 残余） | `<span>head <b>deadbeef</b></span>` | `ReadHead` 返回 `("", false)`（**静默**——残余不修，A5 格钉住） | `TestReadHead/span-restructure` |
| 缺页 / 无标记 | 不存在的文件 / 无标记的 HTML | `ReadHead` 返回 `("", false)`（同款静默） | `TestReadHeadMissingFile` / `no-marker` |
| 主干三级全不中 | unborn repo（无 commit） | `Resolve` 返回 `Ok=false` | `TestResolveUnborn` |
| `--version` 默认值 | 不注入 ldflags 直接 build | `aicf-guard dev (unknown)`（不是空 / 不是崩） | `TestVersion` |

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
| `GAP-025`② | 已缓解·残余 | HTML 正则残余（`<span>` 重构静默）**本单元不修**——保留同款正则与同款静默（ADR §1.3.6）。`page` 单测的 `<span>` 用例钉住残余。 |
| `GAP-029` | 已实现·待复核 | 布局无关枚举（`files.Enum`）**不在本单元**（M3）。本单元 `workspace.Resolve` 不涉及该路径。 |
| `GAP-031` | 已实现·待复核 | 主干三级回退——本单元 `mainline.Resolve` 重写同款逻辑，单测覆盖三级。**独立复核由 `falsifier` 在三跳链做**。 |
| ADR §8.3 待登记 | 待登记（M0） | 「薄转发层在二进制缺失时的 fail-closed 契约」——**第 2 次派发实现转发层时登记**（本单元不做转发层）。 |

### 5.3 不自证（D3 + 角色硬边界）

本单元的测试**不能自己放行**。本地验证（`go build`/`go test -race`/`--version`）必须做，但 **M0 准出由总控三跳链判定**（`qa-validator`→`falsifier`→`gate-auditor`，§4.2），在第 2 次派发完成 M0 整体后触发。本单元交付「实现 + 本地验证证据」，**非准出裁决**。

---

## 六、回填（改动落地后，`go build`/`go test -race`/`--version` 实测）

> 待回填——见文末「七、回填记录」。

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

**改了什么**：`mainline.go` **无改动**（核对后确认与 `.ps1` 一致，不做"为改而改"）；`mainline_test.go` 补
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
| `workspace.go` | ① 新增 `ResolveFrom(flagWorkspace, projectDir, executable, workingDir)`——把 OS 派生的四个输入显式化；`Resolve` 改为读 OS 后**委托**给它（**只有一条实现**，`os.Executable`/`os.Getwd`/`os.Getenv` 在测试里不可注入，不抽出来则分层逻辑只能靠"测试二进制恰好放在哪"来测）。② 删除原 `resolveWorkspace`（其职责并入 `Resolve`）。③ 新增 `FindPage(ws, name)`：两处候选 `.ps1:212-215`，**ws 优先**，命中即停。 |
| `workspace_test.go` | 补 `ResolveFrom` 3 格 + `TestResolveUsesProjectDir`（唯一触碰 OS 管线的一格）+ `FindPage` 6 格。 |

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

