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
| `page.go` | 新增 `DefaultPageName` 常量与 `ReadPageName(pointerPath) NameResult`——指针文件的**三态**（`.ps1:199-206`）：缺失⇒默认名且**不报故障**；有名字⇒trim 后返回；**有但读不出⇒报故障**（GAP-002）。补注释说明 M8/M9 的语义。 |
| `page_test.go` | 补 `TestReadHeadSkipsMalformedFirstMarker`（3 子格）+ `ReadPageName` 5 格。 |

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
3. **`README.md` / `hooks/README.md` 的描述未改** —— 它们描述的是**规则**（权威源在 `AGENTS.md` §5），
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

