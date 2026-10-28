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

> 待改动落地后回填本节。
