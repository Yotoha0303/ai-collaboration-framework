# AI Collaboration Engineering Framework

> A **constraint framework** for "one human + several AIs developing real software projects."
> It does not teach an AI how to write code — it constrains the **order**, the **evidence**,
> and the **boundaries** within which an AI produces, and makes every deliverable leave a
> **reviewable trace**.

This repository is neither a project scaffold nor a prompt collection. It is the
**mechanisation of engineering discipline**: it turns four non-negotiable disciplines —
*read it before you claim it, hard stage gates, falsifiable criteria, single source of truth* —
into four executable things: a **gate matrix, role contracts, a runtime-state contract,
and mechanical guards**.

---

## 1. What problem it solves

When you put an AI to work, the failure is rarely "the model isn't smart enough." It is
usually one of these **structural failures**:

| Failure mode | Typical symptom | The framework's mechanism |
| --- | --- | --- |
| **Inference instead of measurement** | Guessing runtime behaviour from a component/file name; reporting "planned" as "done" | Discipline D1 |
| **Stages blurring together** | Writing business code before the design is locked; declaring "shippable" with no test gate | Gate matrix + D2 (hard stage gates) |
| **Fake all-green** | An empty denominator read as 100%; a criterion that is **silent on failure** | D3 (criteria must be falsifiable) |
| **Two facts of different maturity** | A root cause never written back to the design docs; a progress page permanently behind HEAD | D4 (SSOT) + mechanical guard |
| **Role overreach / silent downgrade** | A generic subagent standing in for a missing specialist; the orchestrator doing the work itself | Three-layer role contracts + registry |

The framework's position: **these failures cannot be fixed by "reminding the AI to be careful."
Only mechanisms fix them.** So the most important parts here are not the written disciplines
but the **falsifiable criteria** and the **hooks that actually block**.

---

## 2. The core cognitive model

Tasks are located on a two-dimensional coordinate system:

```
Vertical (system layers)   Rules → Organisation → Business → System → Code → Runtime → Data → Experience
Horizontal (lifecycle)     Inception → Requirements → Design → Development → Test → Release
                           → Deploy → Operate → Incident → Iterate → Decommission
```

Together these form a matrix. On receiving a task, the orchestrator AI first answers **two
questions**: *"Which stage, which layer?"* — only then does it decide whom to summon, what
input to give, and what output to demand.

Alongside the horizontal axis sit business and engineering constraints: cost, supply chain and
protocols, ecosystem extension, organisational governance, risk, security, reliability,
business value.

> The full prompt is [`prompts/AI总控.md`](prompts/AI总控.md) (Chinese).

---

## 3. The four non-negotiable disciplines (Zero Tolerance)

### D1 · Read it before you claim it — never infer
Every conclusion must rest on **content actually read from a file** or **real command stdout**.
File and counting metrics **must use `git ls-files`** — to isolate build artefacts and dependencies.
(This is not fastidiousness: in a real project the `find` count was **531** files and the
`git ls-files` count was **252** — a difference of **279**, all build artefacts and local files.
Use the wrong measure and every "coverage" or "file count" conclusion is false.)
Timelines are always asserted in **UTC**.

### D2 · Hard stage gates
Advance strictly in order. **Until the previous stage's exit criteria are met, do not generate
the next stage's implementation.**
When blocked, **state the blocking reason and the release condition** — not "I'll start it now
and fill it in later."

### D3 · Criteria must be falsifiable
When writing any monitor, scheduled job, assertion, or gate script, you **must also provide a
negative test case**: inject a fault and the alert/failure **must** fire.
**Be especially wary of criteria that are "silent on failure"** — such criteria (hooks, guard
scripts) look perfectly healthy while never blocking anything if a path derivation is wrong.
For these, verification **must** run the negative case. "Silent when consistent" is **not**
enough to prove teeth — it cannot distinguish "normal" from "dead code."

### D4 · Single source of truth (SSOT) and drift-proof identifiers
Identifiers are strictly defined: `ADR-` (architecture decision) · `MIG-` (database migration) ·
`GAP-` (quality gap) · `INC-` (production incident) · `DEFER-` (deferred debt).
Any conclusion (especially a root cause) **must be written back immediately** to the downstream
design and product documents. **Two facts of different maturity must never coexist.**
On conflict: **in-repo docs > out-of-repo docs**; **code and measurement > prose**.
**Search before registering a new gap** — `git grep` the whole repo to confirm no existing
identifier already covers it. **Colliding with an existing identifier is worse than not
registering at all.**

> The source disciplines (with the ten-stage pipeline's entry/exit checkpoints) are in
> [`prompts/全生命周期工程质量总监与系统架构师.md`](prompts/全生命周期工程质量总监与系统架构师.md) (Chinese).

---

## 4. The gate matrix

Ten pipeline stages, **all hard gates** — failing any stage's exit criteria **blocks** the next.
**When the corresponding artefact does not exist, the stage is judged "not met" — not "not applicable."**
This matrix constrains **projects that adopt the framework**; **the framework repo itself (this
repo) is a template and is not subject to it** (this repo is still bound by D1–D4 and the
mechanical guards).

| Stage | Nature | Exit criteria |
| --- | --- | --- |
| **01 Design** | 🔒 Hard gate | ADR on disk + schema migration with timestamp + acceptance criteria testable |
| **02 Development** | 🔒 Hard gate | Follows `docs/changes` *write-first-fill-later* + consistent naming |
| **03 Test** | 🔒 Hard gate | New cases **100% enrolled in the CI matrix** + coverage **configured threshold** |
| **04 Build** | 🔒 Hard gate | Immutable image **digest** + runtime assertion `REVISION == Git HEAD` |
| **05 Deploy** | 🔒 Hard gate | Deploy script **idempotent end to end** + config/env vars aligned both ways, no residue |
| **06 Observability** | 🔒 Hard gate | Alertmanager `active` distinguished + severity participates + real downtime drill |
| **07 Incident** | 🔒 Hard gate | Second-level timeline + controlled experiment + root cause written back + actions → GAP |
| **08 Recovery** | 🔒 Hard gate | Measured RTO/RPO + **business-level** availability verification |
| **09 Retrospective** | 🔒 Hard gate | Action items have an owner form / dependencies / measurable DoD |
| **10 Automation** | 🔒 Hard gate | Timer precondition assertions + independently archived report |

> Full matrix in [`AGENTS.md`](AGENTS.md) §2 (**Chinese is the baseline**; its English
> projection is [`AGENTS.en.md`](AGENTS.en.md)); the per-stage **responsible role and handover
> artefacts** are in §2.1. The two sections must be read together.

---

## 5. Role contracts come in three layers (none may be skipped)

This is the single **most commonly misunderstood** point in the framework: equating
"role contract" with `.claude/agents/*.md` is wrong — that is only the third layer.

| Layer | File | What it defines | When to read |
| --- | --- | --- | --- |
| **Template** | [`prompts/角色契约.md`](prompts/角色契约.md) part 1 | The **9 items** a role must state: mission / scope / inputs / workflow / decision rights / output contract / acceptance criteria / escalation / metrics | Always resident |
| **Registry** | [`prompts/角色契约.md`](prompts/角色契约.md) part 2 | **Which roles exist** + each one's **input/output contract** | **Mandatory before dispatching** |
| **Implementation** | [`.claude/agents/`](.claude/agents/) | The roles **instantiated in this project**: scope / hard boundaries / iron rules / `tools` allow-list | Loaded with the subagent |

### Roles in the registry (10)

`biz-strategist` · `pm-spec-driver` · `system-architect` · `data-engineer` · `backend-dev` ·
`qa-validator` · `sre-operator` · `sec-auditor` · `finops-controller` · `rca-investigator`

All ten now ship **baseline contract implementations** covering the full lifecycle.
**Domain-specific roles** (e.g. `contract-dev` for a web3 project) are added per project —
see ledger `DEFER-006`.

### Implementations that are not registry roles

The registry lists **business roles**. The following three are **enforcers of the disciplines**
and are not among those ten:

| Implementation | Discipline served |
| --- | --- |
| [`ssot-scribe`](.claude/agents/ssot-scribe.md) docs & ledger maintenance | D4 SSOT |
| [`gate-auditor`](.claude/agents/gate-auditor.md) gate audit (read-only) | D2 hard stage gates |
| [`falsifier`](.claude/agents/falsifier.md) negative verification (read-only) | D3 falsifiability |

> **"Read-only" is mechanical, but the criterion is *not* "no Write/Edit"**:
> `falsifier` / `gate-auditor` have `tools` of **`Read` / `Grep` / `Glob` only** — **no shell at all**.
> The reason: **shell is itself a write backdoor** — `Set-Content` / `Out-File` / `Remove-Item`
> can all write and delete files, so blocking `Write`/`Edit` alone **does not block it** —
> that would be a **criterion crack** (the same shape as §9, "two doors, running one leaks").
> **The cost is explicit**: read-only roles **cannot run commands**, so their execution is
> **carried out by the orchestrator on their behalf** — they produce **attack lists / verdict
> tables + command lists**, and the orchestrator feeds back **real stdout** before they judge.

### Hard constraints on dispatching subagents

| Constraint | Content |
| --- | --- |
| **Concurrency cap** | No more than **3** roles summoned concurrently for a single task |
| **Registry-only** | **A role not in the registry may not be dispatched** (no vague roles) |
| **Mandatory cross-review** | Architecture/scheme changes must be **summoned in pairs** to review each other; cross-examination capped at **2 rounds**; if unresolved, escalate the disagreement to a human |
| **State consolidation** | **Subagents must not modify the runtime memory** — the orchestrator distils it into a ≤5-line summary |
| **No silent downgrade** | If a role is unavailable (unregistered / missing), **you must say so explicitly**; **never** quietly switch to "the orchestrator will do it" or substitute a generic subagent |

> The last two are the most commonly violated. **"No silent downgrade" has a cost** — it means
> that when a role is missing, **the task stops** rather than "getting finished somehow."
> The framework holds that this cost must be paid: output outside the hard boundary is
> **not accepted**, and **re-dispatching is cheaper than rework**.

---

## 6. File map of this repository

```
AGENTS.md                        The single source of constraints. Disciplines / gate matrix /
                                 five-segment protocol / role-layer definition
AGENTS.en.md                     The same, in English (a language projection of one source of rules)
CLAUDE.md                        Thin entry point: import AGENTS.md + declare identity + self-check
README.en.md                     This file
LICENSE                          MIT

prompts/
  AI总控.md                      Orchestrator prompt (2-D model: 8 layers × 11 stages)
  角色契约.md                     Role contracts: template (9 items) + registry (10 roles)
  全生命周期工程质量总监与系统架构师.md   Source disciplines (four + ten-stage checkpoints)
  AI协同工程架构.png              Topology diagram

.claude/
  settings.json                  Stop hook config
  hooks/check-progress.ps1       Progress-page staleness guard (fail-closed)
  progress-page.txt              One line: the single source of truth for the page filename
  agents/*.md                    Instantiated roles

launchers/
  start_claude.bat / .sh         Launchers: lock the working directory

docs/
  ledger.md                      The **only** ledger of open items (GAP/INC/DEFER).
                                 **Anything "not yet done" that is not in the ledger does not exist**
```
> ⚠️ **Layouts differ, and this repo is "self-hosted"**: the repo is the directory that
> **contains `.git`** (any name). The table above is annotated for the **target layout**
> (repo is a `project/` subdirectory). **This repo's workspace root itself contains `.git`**,
> so **the repo *is* the workspace root**, and `docs/ledger.md` **is inside the repo** —
> a ✅ tracked deliverable.

---

## 7. Runtime contract: recording has **two projections**

The framework requires the **behaviour record** and the **human-facing progress page** to be
at the same maturity — this is the mechanical extension of D4:

| Where | Role | Update mode |
| --- | --- | --- |
| `record.md` | The **source** of the behaviour record (one fixed-format line per command) | Append-only; **never edit or delete existing lines** |
| **Progress page** (HTML) | The **human-facing projection** (status / case counts / coverage / gaps / timeline) | Overwrite-sync |

**The page name is not fixed** — it changes as the project advances. So the filename is not
hard-coded into scripts or docs; it is named by `.claude/progress-page.txt` (one line):
**renaming the page = editing this one line**. That file is the **single source of truth for
the page name**.

**This does not rely on good intentions; it is mechanically enforced**: a `Stop` hook compares
the HEAD marker in the progress page against `git rev-parse --short HEAD`, and on mismatch
**blocks the end of the turn** and feeds the reason back to the model.

**Four deliberate design decisions** (all worth borrowing):

1. **No check when the page does not exist** — the guard exits silently (`exit 0`) when the page
   has not been created yet. The criterion presupposes "the page exists and must not lag";
   with no page there is **no fact that could lag**. **This is "not yet initialised," not
   "the page is missing."**
2. **Silent when the SHA marker cannot be found** — if the page's structure has been changed
   beyond recognition, a false alarm on every turn is worse than staying quiet.
3. **Block on mismatch rather than remind** — "a reminder gets ignored; a block does not."
4. **The page name comes from a pointer file** — hard-coding it means one rename silently
   disables the guard.

> ⚠️ **These branches make the script "silent on failure"**: get the path or page-name
> derivation wrong and it will **pass silently forever**. So it **must** be verified with
> negative cases in **two** branches: ① **page missing** → must be **silent `exit 0`**;
> ② **inject a wrong SHA** (page present) → must emit `decision:block`.
> Verifying only "silent when consistent" cannot distinguish "normal" from "dead code" —
> in particular, the missing-page branch and dead code are **observationally equivalent**.
> **Re-run both cases after renaming the page.**

**Initialising the runtime on first use of a workspace**: if both `record.md` and `memory.md`
are absent, the workspace **has not been run yet** — **this is not an error**. The orchestrator
creates both directly in the first session, **without asking and without reporting it**
(`memory.md` is consolidated only by the orchestrator; subagents must not write it).

---

## 8. How to run it (this step is the easiest to get wrong, and getting it wrong fails silently)

All three of Claude Code's lookup paths — `AGENTS.md` / `.claude/agents/` / `settings.json` —
**scan only the launch directory and its ancestors, never downward.**

Therefore:

1. **You must launch from the framework root.** If the framework is in a subdirectory and you
   launch from a directory above it, all three paths fail **silently and together** — no error,
   the framework simply appears not to exist.
2. **`.claude/` must already exist at session start** to be loaded. If you add or move
   `.claude/` mid-session, **open `/hooks` once to reload, or restart the session** — do not
   count on it within the current session.
3. **Launchers**: [`launchers/start_claude.bat`](launchers/start_claude.bat) (Windows) and
   [`launchers/start_claude.sh`](launchers/start_claude.sh) (Linux/macOS) each `cd` to the
   workspace root first (`cd /d "%~dp0.."` / `cd "$(dirname "$0")/.."`) to lock the working
   directory. Double-clicking a `.bat` takes the CWD from Explorer, not from the script, so a
   launcher without that `cd` makes the launch location **drift with wherever you clicked**.
   (This was actually hit: the framework silently failed, and investigation found the launcher
   was a single line `claude` with no `cd`.)
4. **Troubleshooting**: use `/context` to check whether **Memory files** lists `AGENTS.md`.
   If it lists only `CLAUDE.md`, the import line is broken or the path is wrong.
   **Another measured trap**: `@path` imports **fail silently on CJK *directory* names**
   (CJK *file* names are fine). Measured: `prompts/AI总控.md` (ASCII directory + CJK filename)
   imports **successfully**; `中文目录/ascii.md` fails **silently**.

> **The framework lives inside the repository** (**self-hosted layout**: the repo is the
> workspace root): framework and deliverables **sharing one repo is a deliberate decision**,
> no longer relying on "the framework is outside the repo." Runtime state is therefore kept
> out of commits by **the `.gitignore` shipped with the repo**.
> It was once kept out by `.gitignore` and **something slipped through** — and what slipped
> through was **prose** (a change record containing an "Appendix: AI collaboration framework"
> section describing the framework itself), not a file.
> **Ignore rules can hold back files; they cannot hold back prose.**

---

## 9. How this framework grew

The framework was not designed; it was **forced** out of a real project. Every adjustment, the
evidence for it, what was rejected, and **what went wrong** deserves a record — see
[`AGENTS.md`](AGENTS.md) §8 (Chinese), which lists the drift **actually caught and fixed**
during the rollout as target examples.

These include several **costly mistakes** whose value exceeds any "best practice":

- Registering a new gap and **colliding with an existing identifier** — and the collision was
  with an item an audit report had already covered. The lesson went into D4:
  "colliding is worse than not registering." **Always search the whole repo first.**
- A fail-closed guard script **missing one fallback in its path derivation**, so it still
  failed silently under the old layout. Lesson: **every** path derivation in a fail-closed
  criterion must carry a fallback.
- A comparison test that **looked like** it protected a financial formula but **never covered
  it** (the source deliberately set the parameter under test to 0). Someone who only ran the
  suite once and saw green **would never know there was a hole**.
  Corollary: **"all tests green" ≠ "what is under test is covered."**
- A subtler version of "all green": **two independent doors, and running only one leaks**.
  In falsification testing, mutating the formula without regenerating the vector left the
  other side **still green**.
- Only after **shipping the framework once** did it become clear that every **self-referential
  statement** about "where the framework is and where it goes" must be re-verified. They are
  **never caught by any test** — they say nothing about code behaviour, only about where they
  themselves sit.
- When a tool name in a `tools:` list does not match the **actually mounted** name, it is
  **silently dropped with no error**. This framework's `falsifier` listed `Bash` while the
  local mounted name is **`PowerShell`** → dropped → the role appeared to "have no shell
  capability," which was then **misdiagnosed** as "this environment does not mount a shell" —
  and the misdiagnosis was even **written into the rules source**. Lesson: **a declared
  capability must be measured** — **"the name is wrong"** and **"the capability is missing"**
  are **observationally indistinguishable**, and the failure is silent, so **no test will ever
  catch it**.

These records **are not rewritten**. What happened is an evidence chain, not a to-do list.

---

## 10. Getting started

1. **Launch from the workspace root**: run `launchers/start_claude.bat` (Windows) or
   `launchers/start_claude.sh` (Linux/macOS). **You must** launch this way — the three lookup
   paths **scan upward only**, and launching from elsewhere makes the framework **silently
   absent** (see §8).
2. **Say what you need**: one sentence describing the task is enough. The **orchestrator** is
   responsible for locating it (lifecycle × system layer), choosing roles, dispatching,
   consolidating, and adjudicating — **you do not need to know which roles exist**.
3. **You make the calls**: for architecture changes, role instantiation, and **shipping/pushing**,
   the orchestrator **stops and asks you**; everything else it drives itself.

The three runtime files (`record.md` / `memory.md` / the progress page) are maintained by the
framework automatically — **you do not need to manage them**; the progress page is the
human-readable current status.

### Preparing to adopt it

The framework itself is **decoupled** from any specific project — everything project-specific
in `AGENTS.md` (repository paths, measured baseline numbers, the gap ledger) is a **replaceable
instance**, not an invariant of the framework.

When adopting it:

1. **Put `AGENTS.md` in your launch directory** and replace the project-specific content section
   by section (§0 location conventions, §7 baselines, §8 drift examples).
   This repo uniformly uses `project/` as the **placeholder name** for the repo subdirectory;
   rename it as appropriate.
   **But never treat the placeholder as a criterion**: the repo is identified by
   **containing `.git`**, and **its name is arbitrary** — do not decide whether a project
   exists or is missing by "is there a directory called `project`."
   Resolve the repo root with `git rev-parse --show-toplevel`; when the workspace root
   **itself contains `.git`**, the repo **is the workspace root** (in which case there is no
   `project/` subdirectory — that is a normal layout).
2. **Instantiate the roles you need** from the registry into `.claude/agents/`.
   Ten baseline lifecycle roles ship with the framework; **add domain roles as your project
   requires** (e.g. `contract-dev` for web3). This framework's `falsifier` / `gate-auditor` /
   `ssot-scribe` can be used as-is.
3. **Keep D3 and the hook's negative cases.** These are the first two things to get cut from a
   mechanism — and once cut, the system **cannot tell that anything is missing**.
4. **Do not track the three runtime files** (`record.md` / `memory.md` / the progress page).
   The one-line criterion: **is it "a deliverable of the project" or "how the AI does its own
   work"?** Only the former is tracked.

---

## License

[MIT](LICENSE).
