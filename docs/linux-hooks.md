# Linux 上的 Stop 守卫：不用 PowerShell

## 背景

`.claude/settings.json` 里两条 Stop hook 原来写死
`powershell -NoProfile -ExecutionPolicy Bypass -File …`，Linux 上没有
Windows PowerShell 5.1，全部失效（`exit 127`）。这是 ADR-001 里登记的
GAP-028②。`progress`（M0）和 `numbers`（M1）已经有 Go 实现后，Linux
上可以直接调二进制，不再经过 PowerShell。

## 本 PR 的范围（刻意收窄）

- ✅ `aicf-guard numbers`：`check-numbers.ps1` 的 Go 移植（M1）
- ✅ `check-numbers.ps1` 改为薄转发层，原实现原样保留为
  `check-numbers.legacy.ps1`（差分测试的 oracle，不接入 hook）
- ✅ 新增 `.claude/settings.linux.json`：Linux 版 Stop hook，直接调二进制
- ❌ **没有改已提交的 `.claude/settings.json`**：Windows 用户不受影响。
  正式切换提交配置是 ADR-001 的 M4，需要另外评审，本 PR 不做。
- ❌ `inject` / `adapter` / `selftest` 不在本 PR：分别是 M2 / M2 / M3，
  一个子命令一个 PR（ADR-001 §3）。

## Linux 上怎么用

```bash
cd aicf-guard && go build -o ../.claude/hooks/aicf-guard .
# 二进制不入库（.gitignore 已排除），只部署到本地 .claude/hooks/
```

然后把 `.claude/settings.linux.json` 的内容**在本地**应用到你的
Claude Code 设置（不要直接提交覆盖 `.claude/settings.json`，否则
Windows 用户的 hook 会断）。两条命令、超时与原配置一致：

- `aicf-guard progress --workspace $CLAUDE_PROJECT_DIR`（15 秒）
- `aicf-guard numbers --workspace $CLAUDE_PROJECT_DIR`（20 秒）

退出码契约与原 `.ps1` 完全一致：

- `numbers`：exit 0 + 无输出 = 无撞车；exit 1 + stderr = 撞车或守卫
  没跑起来（notice，不阻断）
- `progress`：exit 0 + 无输出 = 放行；exit 0 +
  `{"decision":"block"}` = 进度页落后；exit 1 + stderr = 提示

## 验证（合并前请在有 Go 的机器上跑）

```bash
cd aicf-guard
gofmt -l .
go vet ./...
go test ./...
```

注意：本 PR 的作者环境没有 Go 工具链，本地没有跑通上面三条，
PR 描述里如实写了这一点，合并前必须由评审方跑通。不要在没跑通
测试的情况下合并。
