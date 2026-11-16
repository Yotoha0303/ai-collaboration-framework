# 框架实战案例集 (Framework Examples)

本目录收录基于 AI 协同工程框架（AI Collaboration Framework）落地构建的工业级全栈项目与微服务实战案例。

---

## 目录结构

| 目录 | 场景 / 领域 | 说明 | 测试覆盖 |
| --- | --- | --- | --- |
| [`web3-koliance/`](web3-koliance) | Web3 去中心化衍生品与交易中台 | 极客黑客松落地实战项目，包含 EVM 智能合约（Hardhat/Foundry）、Next.js 14 App Router 客户端、Rust 撮合辅助库与端到端回归套件 | 900+ 自动化测试通过 |

---

## 典型案例：`web3-koliance`

`web3-koliance`（向后兼容主路径为 `koliance/`）是本框架全程指导开发的大型复杂系统范例：
- **职责隔离与最小权限沙箱**：架构设计、合约实现与审计验证全链路物理解耦，只读审计无命令执行权。
- **变异测试门禁与反静默放行**：对极端行情爆仓、预言机延迟注入故障负向用例，确保无空断言与假全绿。
- **单一事实源与上下文生命周期治理**：状态转移严格与 Git HEAD 保持一致，通过 900+ 项单元测试、集成测试与契约测试全面护航。

运行该案例测试：
```bash
cd examples/web3-koliance
pnpm test
```
