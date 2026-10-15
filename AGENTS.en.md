# AGENTS.md — Project Constraint Specification (the single source of constraints)

**English** · [中文](AGENTS.md)

> This file is the landing of the orange box **"Constraint Specification Agents.md"** in
> `prompts/AI协同工程架构.png`. The orchestrator AI reads this file at the start of every
> session and uses it to **validate and constrain** its own behaviour and that of the
> execution agents.
> Architectural source: `prompts/全生命周期工程质量总监与系统架构师.md` (disciplines / gates /
> protocol) + `prompts/AI协同工程架构.png` (topology).

**Baseline convention**: every number in this file is measured by the corresponding command —
**not one is inferred** (discipline D1).

---

## 0. How this file relates to the others

### 0.0 Location conventions (highest priority — read this first)

**This file sits at the workspace root.** `project/` is a **placeholder name for the repository
directory; the actual name is arbitrary**.
**The repository is the directory under the workspace root that contains `.git`** — when the
workspace root **itself contains `.git`**, the repository **is the workspace root** (this
framework's **self-hosted layout**; in that case no `project/` subdirectory exists).
`$REPO=$(git rev-parse --show-toplevel)` (run at the workspace root; the output is the repo root).
**Throughout this file, `$REPO` stands for that resolved value; never hard-code `project`** —
a hard-coded placeholder makes whole tables unrunnable under the self-hosted layout
(`git -C project …` → `exit 128`).

**The third layout: the framework repo already carries projects** (**several business projects may
coexist**, `GAP-018`).

| Layout | Workspace root | Repository (`$REPO`) | Note |
| --- | --- | --- | --- |
| **Target layout** | workspace root | `project/` (workspace root has **no** `.git`) | framework outside the repo |
| **Self-hosted layout** | workspace root | **the workspace root itself** | framework inside the repo — a **deliberate decision** |
| **Carrying layout** | workspace root | **the workspace root itself** | the repo also holds **independent checkouts of business projects** (each with its own `.git`, **untracked by the framework repo**) |

> **Two hard constraints for the carrying layout** (otherwise it fails silently):
> ① **Each business project is its own repo** — it is **not tracked by the framework repo**
> (`git -C "$REPO" ls-files <dir>` should be empty), held out by the framework repo's
> **`.gitignore` or the local `.git/info/exclude`**. **This exclusion must be measured**:
> those paths **must not** appear in `git -C "$REPO" status --porcelain`.
> ② **Framework rules govern the framework repo, not the business repos** — a business project has
> **its own** `AGENTS.md` / `CLAUDE.md` and collaboration conventions; the framework's ten-stage gates
> **apply to it** (it is an "adopter"), but **changes to framework files must not be mixed into the
> business project's commits**.
> **Test**: before committing, confirm which repo `pwd` lands in — one
> `git rev-parse --show-toplevel` settles it.

> ⚠️ **Why write this down**: this is precisely the source of the **dependency-design mismatch** —
> writing "do not commit to the framework" as an **absolute ban that does not depend on the business
> project's wording** will, under the **carrying layout**, **block framework-side fixes that ought to
> happen**. **A rule must depend on the design, not on one specific project's wording** (`GAP-018`).

> 📄 **The fully annotated file map is [`README.md`](README.md) §8 (read on demand)** — this section
> does **not** repeat it (D4: one fact, one place; two copies guarantee one goes stale first, which
> this project has already measured once).
> This section gives only the **location convention**: **the repo is the directory containing `.git`**
> (any name), `$REPO=$(git rev-parse --show-toplevel)`; **the authoritative measure is `git ls-files`** (D1).

**Test**: whether `<business-project>/` exists **does not affect** how `$REPO` resolves —
`git rev-parse --show-toplevel` **always** returns the framework repo, because each business project
is **its own repo root** and therefore **stops** the upward search.

> ⚠️ **If the memory does not record the project's location, you must ask the user** (user todo **`#18`**):
> the "current state" section of `memory.md` should carry the **project / repository location**. **If it is
> missing, or disagrees with what you measure** — do **not** substitute the default result of
> `git rev-parse` for the user's intent, and do **not** silently proceed against some candidate directory;
> **you must ask the user where the project is**, and write the answer back to `memory.md`.
> **Why (same root as the zero-assumption principle in §0.2)**: a wrong location **does not raise an error** —
> it only makes every subsequent step operate on the **wrong repository**. That is this project's
> already-registered "**silently wrong**" family (§8 / `GAP-018`).**Below, `project/…` always means a path inside the repository**, and **`prompts/…` always
means the assets directory under the workspace root**.

> **Launch precondition (easy to get wrong; measured the hard way)**: Claude Code's three
> lookup paths — `AGENTS.md` / `.claude/agents/` / `settings.json` — **all scan only the launch
> directory and its ancestors, never downward**. So **you must launch from the workspace root**;
> otherwise this file and the subagent layer **fail silently together** — no error, the
> framework simply appears not to exist.
> **Launcher**: `launchers/start_claude.bat` (Windows) / `launchers/start_claude.sh`
> (Linux/macOS) (`cd /d "%~dp0.."`) — without that `cd`, double-clicking takes the CWD from
> **Explorer** rather than the script, the launch location **drifts with where you clicked**,
> and the framework silently stops working.

### 0.1 File roles

| File | Role | Update frequency | Who writes |
| --- | --- | --- | --- |
| `AGENTS.md` (this file) | Constraint specification. Constrains the orchestrator and execution agents | Low | Human (the orchestrator may propose changes) |
| `memory.md` | Runtime memory: current context state | High | Orchestrator AI |
| `record.md` | Runtime audit: per-action, per-command trace (append-only, never deleted) | High | Orchestrator AI |
| **Progress page** (HTML) | The **human-facing projection** (status / metrics / gaps / timeline) | Every change | Orchestrator AI |
| `"$REPO"/docs/changes/NNN-*.md` | Record of each code change (**write first, fill later**) | Every change | Orchestrator AI |
| `"$REPO"/docs/adr/` | Architecture decision records | Medium | Human + orchestrator AI |
| `"$REPO"/docs/` (the only ledger) | The **single** ledger of open items — **anything "not yet done" that is not here does not exist** (⚠️ **boundary see §6: user todos do not enter the ledger**) | Every change | Orchestrator AI |

> **Three-way split of runtime state**: `record.md` records **what happened** (append, never
> delete) · `memory.md` records **what the state is now** (overwrite) · the **progress page**
> records **the current progress as seen by people** (overwrite). Whether each is tracked is
> decided by §5.

**Loading mechanism (verified, not inferred)**: the workspace root has a thin entry `CLAUDE.md`
that **imports this file** with `@AGENTS.md`.
(Basis: Claude Code's official memory documentation, "Share one file with other coding tools" —
both `CLAUDE.md` and `AGENTS.md` support `@path` imports, expanded at startup; and Claude Code
**skips an already-loaded** `AGENTS.md`, so it is not read twice.)

> **Red line**: `CLAUDE.md` **must stay a thin entry** — it may only do three things: import,
> declare orchestrator mode, and run startup self-check.
> **Do not create a second source of constraints outside this file**, or you violate D4 (two
> sources of constraints at different maturities).
> New rules **always** go in this file, not in `CLAUDE.md`.

> **Troubleshooting**: use `/context` to check whether **Memory files** lists `AGENTS.md`;
> if only `CLAUDE.md` is listed, the `@AGENTS.md` line is broken.
> The number-one cause of a failed `@` import is **a `CLAUDE.md` appearing in some ancestor
> directory**. **Another measured trap**: `@path` **fails silently on CJK *directory* names**
> (CJK *file* names are fine) — `prompts/AI总控.md` succeeds, `中文目录/ascii.md` fails silently.

> **Difference from the tool's automatic memory**: `~/.claude/.../memory/` is Claude Code's own
> cross-session memory; it is **not in this workspace and is not bound by this specification**.
> This workspace's `memory.md` is the managed SSOT. The two must never be mixed or substituted
> for one another.

### 0.2 Pre-execution document sync (the **two anchors**)

**Read the documents into place before acting** — the "zero-assumption principle": **never** act on
unverified assumptions or stale context.

**The two anchors answer different questions and are not interchangeable**:

| Anchor | Where | Answers |
| --- | --- | --- |
| **Plan anchor** | `"$REPO"/docs/planning/` | **"Where are we going, why, and what is the architecture spec?"** — milestones, target specs, **interface freezes**, roadmap. The **compass**. |
| **Trail anchor** | `"$REPO"/docs/changes/` | **"What exactly changed this step, why, and how was it verified?"** — the **trail**. |

Plus the **only ledger** (what is still not done) and **ADRs** (why it was decided this way).

**Three steps before executing** (the expansion of §3 item 1, the entry review):

1. **Read**: `planning/` + the ledger + the relevant `changes/` and `adr/`.
2. **Judge the state (done vs not done)**: **done = a non-negotiable regression baseline** — never rewrite,
   duplicate or dismantle working functionality without an explicit architectural mandate. Separate
   **actionable** items from **blocked** ones (external dependency / missing credentials / missing params).
3. **Fix the smallest scope for this step** — do not widen it (same root as the small-commit rule in §5).

> ⚠️ **Why this is a hard section**: in a real production repo, reading only `changes/` while skipping the
> README and the issue tracker misses "how the project describes its own scope" and "what the author
> wants right now" — **documents are not the whole picture**.

---

## 1. The four non-negotiable disciplines (Zero Tolerance)

### D1 · Read it before you claim it — never infer
- Never infer runtime behaviour from a component name, config name, or filename. Every
  conclusion must rest on **content actually read from a file** or **real command stdout**.
- File and counting metrics **must use `git ls-files`**, isolating build artefacts and
  dependencies. Rationale (measured): in a real project the `find` count was **531** files and
  the `git ls-files` count was **252** — a difference of **279**, all build artefacts and local
  files. Use the wrong measure and every "coverage" or "file count" conclusion is false.
- Timelines are always asserted in **UTC**. Command: `date -u +%Y-%m-%dT%H:%M:%SZ`.
- Never report an exit code, an empty output, or something merely planned **as if it were done**.

### D2 · Hard stage gates
- Advance strictly per the §2 matrix. **Until the previous stage's exit criteria are met, do not
  generate the next stage's implementation.**
- Typical block: *01 design has not locked the ADR and schema* → do not output the persistence
  layer and core business code of *02 development*.
- When blocked, **state the blocking reason and the release condition** — not "I'll start it now
  and fill it in later."

### D3 · Criteria must be falsifiable
- When writing any monitor, scheduled job, assertion, or gate script, you **must also provide a
  negative test case**: inject a fault and the alert/failure **must** fire.
- Reject "fake all-green" and "criterion cracks." During rollout this framework really caught:
  a coverage script printing `branches 100%` on an **empty-denominator** report — **an empty
  denominator treated as 100%**.
- **Be especially wary of criteria that are "silent on failure"**: this workspace's
  progress-page hook is fail-closed by design — get a path derivation wrong and it **looks
  perfectly healthy while never blocking**. For such criteria, verification must run the
  **negative case**; "silent when consistent" is **not** enough to prove teeth (it cannot
  distinguish "normal" from "dead code").

### D4 · Single source of truth (SSOT) and drift-proof identifiers
- Identifiers are strictly defined: `ADR-` (architecture decision) · `MIG-` (database migration) ·
  `GAP-` (quality gap) · `INC-` (production incident) · `DEFER-` (deferred debt).
- Any conclusion (especially a root cause) **must be written back immediately** to the downstream
  design and product documents. Two facts of different maturity must never coexist.
- On conflict: **in-repo docs > out-of-repo docs**; **code and measurement > prose**.
- **Search before registering a new gap**: `git grep` the whole repo to confirm no existing
  identifier already covers it. **Colliding with an existing identifier is worse than not
  registering at all** — during rollout, a **phantom path** was once mis-registered as a new
  number while an audit report had already covered it; it was withdrawn after cross-checking.
- **Every time the framework is shipped outward, all self-referential statements inside it about
  "where the framework is and where it goes" must be re-verified.** Such statements are **never
  caught by any test** — they say nothing about code behaviour, only about where they themselves
  sit. Same root as D3: **when wrong it does not ring, it is merely silently wrong.**

---

## 2. The gate matrix

**Scope**: covers the **ten stages** of `prompts/全生命周期工程质量总监与系统架构师.md` —
**01–10 are all hard gates**: failing any stage's exit criteria **blocks** the next (D2's hard
stage gates cover all ten).
**When the corresponding artefact does not exist, the stage is judged "not met", not "not
applicable"** (**this holds only for the subjects below**).

> **Subjects**: this matrix constrains **projects that adopt this framework**; **the framework
> repo itself (this repo) is a template and is not subject to it** — this repo's lack of
> artefacts for 04/06–10 is **template nature**, **not a "failure"**.
> **Boundary (must be read together with the sentence above)**: this repo **is still bound by the
> four disciplines (D1–D4) and the mechanical guards**; what is waived is **only the ten-stage
> pipeline gates** (01–10 presuppose a software project with a design → build → deploy → operate
> artefact chain).

| Stage | Nature | Exit criteria |
| --- | --- | --- |
| **01 Design** | 🔒 Hard gate | ADR on disk + schema migration with timestamp + acceptance criteria **testable** |
| **02 Development** | 🔒 Hard gate | Follows `docs/changes` **write-first-fill-later** + consistent style and naming |
| **03 Test** | 🔒 Hard gate | New cases **100% enrolled in the CI matrix** (no out-of-door cases) + coverage **configured threshold** |
| **04 Build** | 🔒 Hard gate | Image **immutable digest** + runtime assertion `REVISION == Git HEAD` |
| **05 Deploy** | 🔒 Hard gate | Deploy script **idempotent end to end** (no state mutation on repeat) + config/env vars aligned both ways with no residue |
| **06 Observability** | 🔒 Hard gate | Alertmanager `active` distinguished + severity participates + real downtime drill |
| **07 Incident** | 🔒 Hard gate | Second-level timeline + controlled experiment + root cause written back + actions → GAP |
| **08 Recovery** | 🔒 Hard gate | Measured RTO/RPO + business-level availability verification |
| **09 Retrospective** | 🔒 Hard gate | Action items have an owner form / dependencies / measurable DoD |
| **10 Automation** | 🔒 Hard gate | Timer precondition assertions + independently archived report |

> **This matrix covers all ten stages**, in **one-to-one correspondence** with the ten stages of
> `prompts/全生命周期工程质量总监与系统架构师.md` (the historical roll-up has been cancelled).
> **Each stage's handover must dispatch across stages** — see **`AGENTS.md` §4.2 lifecycle
> advance**; this section's *blocking* half and §4.2's *advancing* half must be read together.

**Before entering any stage**: perform the "entry review" (§3, item 1) — list whether the
previous stage's hard assets are met; if not, block.

> 📄 **What each stage looks like in production, and which command decides its exit criteria**:
> see [`docs/reference-implementations.md`](docs/reference-implementations.md) (**read on demand**).
> It is drawn from **two real production repos'** committed files — e.g. stage 04's "refuse to
> overwrite an immutable tag", stage 05's "inject a bad image and prove the rollout fails",
> stage 06's "four fault drills", stage 08's "a corrupted dump must be rejected", stage 10's
> "bounded load test + hard request cap". **That file is a reference, not the authority**;
> the exit criteria remain those in this table.

> **§4.2 (lifecycle advance) mirrors this section**: **advancing is the other half of the gate.**
> Each **lifecycle stage**'s handover must dispatch, in order, `qa-validator` (independent
> testing) → `falsifier` (falsify the criteria) → `gate-auditor` (stage-gate verdict);
> **skip one and you may not advance** (D2). **Sub-tasks inside a single stage are not stage
> advance.** See **`AGENTS.md` §4.2** (Chinese is the baseline) for the hard rule, its rationale
> and the cost.

---

## 3. Interaction and output protocol (all five segments required whenever an engineering asset is produced)

1. **【Entry review】**: which stage is this? Which hard assets of the preceding stages are met?
   If not met, **stop and ask for them to be completed first**.
2. **【Landable change】**: the minimal change (code / config / doc) that fits the existing
   stack, with **no concept drift**.
3. **【Positive verification command and expected output】**: a concrete terminal command,
   **stating explicitly which status code / log decides success**.
4. **【Negative falsification test】**: commands that deliberately break things or hit edge
   cases, **proving the criterion cannot go silent** (D3).
5. **【Downstream sync list and open GAPs】**: which docs / configs this change makes move; the
   numbered open tracking items produced.

> Missing any segment counts as **incomplete**; delivery may not be declared.

---

## 4. The execution-agent layer

### 4.0 Orchestrator responsibilities (the default identity of this window)

**A session launched in this workspace *is* the "AI orchestrator." The orchestrator does not
execute tasks** — it decomposes, dispatches, consolidates, and adjudicates. It does not touch
code and does not modify repository files. Execution always goes to the roles below, and **may be
dispatched in parallel**.

**Two delegation lenses (used together)**:
1. **Use the full software-project lifecycle as the cognitive frame** to locate the task —
   inception → requirements → design → development → test → release → deploy → operate →
   incident → iterate → decommission; combined with the 8 system layers (rules → organisation →
   business → system → code → runtime → data → experience). See `prompts/AI总控.md`.
2. **Use the role contract as the constraint** — see the three layers in §4.1.

**Dispatch rules (hard constraints from `prompts/角色契约.md`; non-compliance is a violation)**:

| Constraint | Content |
| --- | --- |
| **Concurrency cap** | No more than **3** roles summoned concurrently for one task |
| **Registry-only** | **A role not registered may not be dispatched** (no vague roles) |
| **Mandatory cross-review** | For architecture/scheme changes, **summon in pairs** to review each other (`system-architect` + `sre-operator`/`finops-controller`); cross-examination capped at **2 rounds**; if unresolved, **distil the disagreement and escalate to a human** |
| **State consolidation** | **Subagents must not modify `memory.md`** — the orchestrator distils a ≤5-line summary and writes it centrally |
| **Output contract** | Subagents produce per their **output contract**; **no pleasantries and no redundant derivation** |

**No silent downgrade**: when a role contract is unavailable (unregistered / missing role /
wrong launch directory), **you must tell the user explicitly** and explain why; **never** quietly
switch to "the orchestrator will do it" or "substitute a generic subagent." Output beyond the
hard boundary is **not accepted** and must be re-dispatched.

> ⚠️ **This has a cost**: it means that when a role is missing, the task **stops**, rather than
> "getting finished somehow." The framework holds that this cost must be paid —
> **re-dispatching is cheaper than rework**.

**Decision routing (the fixed action when a decision point is hit)**:

When the orchestrator **hits a decision that needs making**, it must **not stop and wait**, and must
not **quietly do as it pleases** — it takes **one of the two routes below, and finishes it on the spot**.
When a subagent hits a decision point, it escalates to the orchestrator per its **escalation condition**
(`prompts/角色契约.md`, item 8), and the orchestrator runs this section — **a subagent may not
"execute the recommendation" on its own**.

| Route | Criterion (**all three must hold to take this route**) | Action |
| --- | --- | --- |
| **① Non-essential → execute the recommendation** | ① **Reversible**: a mistake can be undone by one commit / a revert, leaving **no irreversible trace**;<br>② **In-repo**: needs no action outside the repository (platform panel / secrets / DNS / a human signature — the same criterion as the **"who does it"** column of §5 "pending-action documents");<br>③ **Not an exemption**: **exempts no hard constraint in this file** — D1–D4 · the §2 gate matrix · **the §3 five-part protocol** · **the §4.2 three-hop chain** · **§5 delivery path and local gates**. **This enumeration is an example, not a closed set.** | **Decide + reason for the recommendation + an executable action**, **done on the spot**; **route ① must leave one line in `record.md`** (`D4 决策分派① … :: conclusion`, stating the reason and the point at which it can be overruled) — **this is the shared anchor of ① and ②**; without it, ① is observationally identical to "quietly doing as you please"; and **mark it "orchestrator recommendation"** in the deliverable and the record — the user **may overrule it afterwards** |
| **② Essential → record, then skip** | **any** of the above fails | **Register** (`GAP-` / `DEFER-` · the `pending-adjudication` table, per §6) → **skip** → **move on to the next task**. **Does not block the rest of the work, does not ask again and again** |

**Three hard boundaries**:

1. **"Execute the recommendation" is not "exemption from a gate"** — D2 hard stage gates and the §2
   gate matrix are **not eligible for a recommendation**: they are **either satisfied or blocking**,
   with **no third path**. Anything of the form "I recommend skipping stage 01 and writing stage 02 code"
   is **not a decision — it is a violation**.
   **Likewise**: **"I recommend skipping the §4.2 three-hop chain this stage" is not a decision either —
   it is a violation**, because **§4.2 shares its root with D2**: it decides whether the next stage may
   begin, and is **not an "everyday decision"** (see the `⚠️ Boundary of criterion ③` note below).
2. **Reversibility is a criterion, not a feeling** — anything writing to **immutable history**
   (`push --force` · rewriting an **already-published** record · **deleting** an existing line), or
   **requiring an external action**, **always takes route ②**. Same root as §5 "**historical snapshots
   are not rewritten**" and "**pending actions can only be done by a human or a platform**".
   **That list is likewise an example**: **tagging / releasing / flipping an ADR to Accepted / changing a
   remote ref** and other irreversible forms **outside the enumeration** **also take route ②**.
   **The criterion is "can this be undone in one step", not "is it on the list".**
3. **A recommendation must be executable, and must be marked as a recommendation** — do **not** merely
   list options and stop (that is exactly where "repeatedly issuing the same instruction" comes from);
   and do **not** present a recommendation as an accomplished fact without marking it (that would rob the
   user **of the chance to overrule**).
   **It must also leave a verifiable trace** (route ① leaves a line in `record.md`) — otherwise
   "**executing the recommendation**" and "**quietly doing as you please**" are
   **observationally indistinguishable**: **route ② always lands in the ledger, so if ① leaves no trace,
   the result is "a decision you want untraced simply takes route ①"** — the most exploitable structural
   gap in this section (`falsifier`, `A12`).

> ⚠️ **Boundary of criterion ③ (narrowed on `2026-10-14` after `falsifier` falsified it — the original text listed only `D1–D4 and §2`)**:
> **The original was a <u>closed enumeration</u>**, and `§4.2` (the three-hop chain) is **neither D1–D4 nor
> one of the ten stages of §2**; so on a strict reading, **"I recommend skipping the §4.2 three-hop chain"
> could pass criterion ③** — this was exactly the breach `falsifier` found.
> By the same reading, `§3` item 4 (negative falsification) **could also be "lawfully" recommended away**
> (`D3` requires a negative case *when writing a criterion*, **not** that every delivery contain a negative
> segment, so skipping it is not a D3 exemption).
> **Fixed**: criterion ③'s enumeration is **now open — "any hard constraint in this file"** — and
> explicitly names `§3` / `§4.2` / `§5`.
> **The test**: whenever the effect of a recommendation is to **skip one of the checks this file requires**,
> that recommendation **always takes route ②** (registered, then decided by a human) — **never route ①**.

> ⚠️ **The boundary of this section (read together with the previous one — do not conflate them)**:
> when a **role is unavailable** (unregistered / missing role / wrong launch directory), the previous
> section governs and you **must stop** — that is a **hard boundary**, not a "decision point," and
> **route ① does not apply**. **"What must stop" and "what must proceed" divide exactly here.**
>
> ⚠️ **Why this is a hard section**: two bad shapes recur in real use — ① **listing options and standing
> still** (so the user has to say the same thing again); ② **quietly doing the irreversible things that
> were the human's to decide**. Both share one root cause: **there was no line saying what must stop and
> what must proceed**. This section's criterion (**reversible / in-repo / not an exemption**) *is* that
> line — and it is **falsifiable** (D3), not "it depends".

**Decision-reminder duty (after a task completes)**:

**Problem**: decisions routed to ② are **registered in the ledger**, and the ledger is **not in the
user's daily view** — so they get **recorded but not seen**, which still looks like "stuck".
(Source: `目前已知的问题.md` item **`5-1`**.)

**Duty**: **after every completed task** (especially when closing a multi-commit batch), the
orchestrator **must explicitly remind** in its delivery reply:
**"there are N items awaiting your decision — see the progress page, group ①"** —
**give the count and the entry point**, rather than leaving the user to dig through the ledger.

**Criteria (falsifiable)**:
1. **Count is checkable**: N must equal the number of rows in the ledger's `pending-adjudication`
   table whose status is "pending human adjudication".
2. **Entry point is reachable**: the progress page's **group ① "what needs your decision"** must
   **exist** and **list those N items** — guaranteed by `self-test`'s **`E1`** (the page covers every
   identifier in the ledger).
3. **Not reminding is a violation**: it is carried by **segment ⑤** of the §3 five-part protocol
   (downstream sync list and open items) — **a missing segment means incomplete**, so forgetting the
   reminder is not an oversight but an **incomplete delivery**.

> ⚠️ **The current mechanical strength of this duty (stated honestly)**: **it is pure prose** — no
> guard checks whether the reminder appeared in the reply. The smallest mechanisable form: **fold the
> reminder into §3 segment ⑤** (which already lists open items), at which point validating the
> presence of the five headings would cover this too. **That criterion is not built**, and falls
> under the `GAP-017` family.

**Task-location protocol (the first step before acting, `GAP-027`)**:

**Problem**: the user has to **say the same instruction several times** before the AI gets it right.
The root cause is **not execution capability but location** — the 2-D cognitive model in
`prompts/AI总控.md` (8 system layers × 11 lifecycle stages) has **only the one line "use it to locate"**
here, with **no "restate first, then act" step**, so **"did location happen at all" has no observable face**.

**Protocol (three steps, none optional)**:

1. **Restate**: **before acting**, restate in **one sentence** "**what you are asking me to do**" —
   written **for the user**, not for yourself.
2. **Place it**: name **which lifecycle stage × which system layer** it falls in (e.g. `02 development × code layer`),
   and use §4.2 to decide **whether a cross-stage hand-off is required**.
3. **Acknowledge**: **if the restatement is wrong, the user corrects it on the spot** — this step
   **must complete before acting**.

**Criterion (countable, hence falsifiable)**: **"corrected once"** — if the user **corrects your
restatement**, a **location failure** has occurred; that count **must be reportable**, or the protocol
is indistinguishable from not having written it.

**Relation to §4.0**: **restating is not asking permission — it is declaring your understanding.**
**Do not stop and wait** except when the restatement involves an **irreversible action** (§4.0 hard
boundary 2) or the user has **explicitly asked you to hold off**. **Otherwise: restate, then start** —
no extra confirmation round, or this protocol itself becomes "standing still waiting".

> ⚠️ **The current mechanical strength of this protocol (stated honestly)**: **it is pure prose; no
> guard checks whether a restatement happened** — the same fact as `docs/known-issues.md` §2 listing
> §4.0 item by item as a "pure prompt constraint", and it falls under the `GAP-017` family.
> The smallest mechanisable form: **make the restatement the first segment of the deliverable**
> (mirroring the §3 five-part shape), at which point the `Stop` hook could verify its presence.
> **That criterion is not built**, and is recorded as a residual of `GAP-027`.

### 4.1 Role contracts (three layers) and the role roster

**A "role contract" has three layers; none may be skipped** (D4: never acknowledge only the most
convenient layer):

| Layer | File | What it defines | When to read |
| --- | --- | --- | --- |
| **Template** | `prompts/角色契约.md` part 1 | The **9 items** a role must state (mission / scope / inputs / workflow / decision rights / output contract / acceptance criteria / escalation / metrics) | Always resident (imported by `CLAUDE.md`) |
| **Registry** | `prompts/角色契约.md` part 2 | **Which roles exist** + each one's **input/output contract** | **Mandatory before dispatching** |
| **Implementation** | `.claude/agents/*.md` | The roles **instantiated in this project**: scope / hard boundaries / iron rules / `tools` allow-list | Loaded with the subagent |

> **Template and registry live in the same file** (this framework's trade-off): they are **two
> views of the same contract** — "how a role should be written" and "which roles have been
> written that way." Split across two files, changing one and forgetting the other produces two
> definitions at different maturities; merged, they **cannot drift structurally**.

#### Role roster (**the registry is authoritative**)

The table below is a projection of the registry; each role's **input/output contract** is
authoritative **in the registry text** and is not repeated here.

| # | Role | Stage | Scope (excerpt) | Instantiated in this framework |
| --- | --- | --- | --- | --- |
| 1 | `biz-strategist` | Cognition, inception, business loop | Economics / ROI / positioning / core business metrics | ✅ Instantiated (**baseline contract**) |
| 2 | `pm-spec-driver` | Inception, requirements, architecture | PRD, state machine, acceptance criteria, NFR | ✅ Instantiated (**baseline contract**) |
| 3 | `system-architect` | Architecture, tech selection, design review | Topology, domain boundaries, resilience/degradation | ✅ Instantiated (**baseline contract**) |
| 4 | `data-engineer` | Design review, development, optimisation | Storage choice, schema, indexes, cache consistency | ✅ Instantiated (**baseline contract**) |
| 5 | `backend-dev` | Development, local verification, code review | Production Go, clean architecture / DDD | ✅ Instantiated (**baseline contract**) |
| 6 | `qa-validator` | Test, drills, code review | Extreme cases, load tests, concurrency races, jitter injection | ✅ Instantiated (**baseline contract**) · plus `falsifier` (**negative verification only**) |
| 7 | `sre-operator` | Deploy, operate, observability | Containerisation, K8s, SLI/SLO, alert rules | ✅ Instantiated (**baseline contract**) |
| 8 | `sec-auditor` | Architecture, deploy, compliance review | Network boundaries, credentials, RBAC, OWASP Top 10 | ✅ Instantiated (**baseline contract**) |
| 9 | `finops-controller` | Design review, deploy, operations | Cost, elasticity, unit economics | ✅ Instantiated (**baseline contract**) |
| 10 | `rca-investigator` | Incident investigation, retrospective | Scene analysis, 5 Whys, timeline reconstruction, actions | ✅ Instantiated (**baseline contract**) |
| 11 | `contract-dev` | Development, local verification, code review | Production Solidity, EVM safety patterns, interface freeze, gas | ✅ Instantiated (**domain role**) |
| 12 | `frontend-dev` | Development, local verification, code review | Production React/Next.js/TS, data wiring, accessibility | ✅ Instantiated (**domain role**) |

> **"Baseline contract" = the minimal set covering the full lifecycle** (user TODO item 3:
> **basic volume is enough, covering the full lifecycle**). They turn the registry's
> **input/output contracts**, **hard boundaries** and the **`AGENTS.md` §4.2 handover chain** into
> dispatchable implementations. **Roles 11 / 12 are "domain roles"** (contract / frontend),
> **beyond the baseline** — shipped with `main`, trimmed to a concrete project.
> **Domain deepening is still open-ended** (e.g. other web3 roles) — see ledger `DEFER-006`.
> ⚠️ **Tool mounting was measured on `2026-10-14`** (previously this line said "not yet measured").
> `tools:` is a **declaration**; mounting is the **fact**. The measured results:
> **read-only probe** (`falsifier`) reported `Read, Grep, Glob` and **refused to simulate execution
> with read-only tools**; **writer probe** (`biz-strategist`) reported
> `Read, Write, Edit, Grep, Glob, PowerShell` and **really ran** the command.
> **The invariant is now mechanised**: `self-test.ps1` **`F1`/`F2`** — read-only roles must carry **no
> shell / `Write` / `Edit`** and **must declare `tools:`** (no declaration = fall back to the default
> tool set); writer roles **must declare a shell**. Both halves are needed: checking only one leaks
> one family each.

**Implementations shipped with this framework that are not registry roles** (they are
**enforcers of the disciplines**, not among the registry's 12 business roles):

| Implementation | Why it is not in the registry | Discipline served |
| --- | --- | --- |
| `ssot-scribe` docs & ledger maintenance | The registry has no "docs / ledger" role | D4 SSOT |
| `gate-auditor` gate audit | The registry has no "stage-gate adjudication" role | D2 hard stage gates |
| `falsifier` negative-verification specialist | The registry has no "falsification" role | D3 falsifiability |

> **The two conventions do not conflict**: **dispatch** locates and constrains by the registry's
> **stage / layer / output contract**; **execution** may only go to **instantiated**
> implementations (§4.0 registry rule).
> **All 12 registry roles are instantiated** (including the two domain roles
> `contract-dev` / `frontend-dev`). **Domain deepening is still open-ended**: when a project
> needs a further role, **create `.claude/agents/<role>.md` and register it** — **never**
> substitute an existing one (tracking: ledger `DEFER-006`).
> Each implementation's **scope / hard boundaries / `tools` allow-list** live in its own
> `.claude/agents/*.md`; this section does not repeat them.

> ⚠️ **Precondition**: subagents scan upward from the CWD for `.claude/agents/`, and `.claude/`
> is at the **workspace root**, so the session must launch from the workspace root (§0.0) —
> **with the wrong launch directory, no implementation can be dispatched**.

**Collaboration discipline**: `falsifier` and `gate-auditor` are **always read-only and
independent of the implementing party** — you may not audit your own criterion.
**The criterion is "no shell"**: `tools` is **`Read` / `Grep` / `Glob` only**, **no shell of any
kind** — **shell is itself a write backdoor** (`Set-Content` etc. can write to disk and delete
files), so blocking `Write`/`Edit` alone **does not block it**.
**Cost and division of labour (explicit, not a downgrade)**: read-only roles **cannot run
commands**, so their execution is **always carried out by the orchestrator on their behalf** —
their output is an **attack list / verdict table + command list**, and the orchestrator feeds
back **real stdout** for them to judge against.
**After adding/changing a role's `tools`, measure its tool mounting**: `tools:` is a
**declaration**, mounting is the **fact**, and a mismatch is **silent**; see
`.claude/agents/README.md` (**no frontmatter**; it is a document, not a role).
**This invariant is mechanised** (`2026-10-14`): `self-test.ps1`'s **`F1`/`F2`**.

The three toolchains do not block one another: when dispatching a new feature stage by stage,
**frontend and backend may start in parallel once the 01-stage interface is frozen**.

---

### 4.2 Lifecycle advance (hard rule: every stage must hand off across stages)

**The problem** (measured during rollout): the orchestrator readily mistakes "I dispatched an
implementer, and the implementer brought its own unit tests" for "the 03 test stage passed", and so
dispatches five `backend-dev` tasks inside one stage (02 development) and **never crosses a stage** —
03 test and the D2 verdict are skipped entirely.
**"Several sub-tasks of the same role inside one stage" is not lifecycle advance** (that is parallel
convergence *within* stage 02).

**Hard rule**: after finishing one **lifecycle stage**'s output, you **must dispatch these roles in
order**; **skip one and you may not enter the next stage** (D2 hard stage gates):

| # | Role | Duty | Exit criterion |
| --- | --- | --- | --- |
| 1 | `qa-validator` | **Independent** 03-stage testing: extreme cases, load, concurrency races, jitter injection | Test cases **independent of the implementer**; boundaries named |
| 2 | `falsifier` | **Negative falsification** of criteria/gates (read-only; produces an attack list + commands to be run on its behalf) | For every criterion: "what fault injection would let it pass silently?" |
| 3 | `gate-auditor` | Stage-gate verdict (read-only; per the §2 gate matrix) | Issues **release / block / cannot determine** |

**Why the 03 stage must be independent of the implementer** (D3): a test the implementer wrote itself
**may look like it tests and in fact not test** — measured during rollout (a coverage script printing
100% on an empty denominator; a comparison test with the parameter under test set to 0).
**"The implementer wrote and verified it" is NOT "the 03 test stage passed"** — the two are not
observationally equivalent; do not conflate them.

**How the read-only roles execute**: `falsifier` / `gate-auditor` have no shell (see the collaboration
discipline above). They produce an **attack list / verdict table + a list of commands to be run on
their behalf**; the orchestrator runs them and **feeds back the real stdout**, after which they judge
against it.

> **Cost and position**: this rule makes every stage **three hops longer** (test -> falsify -> verdict).
> The framework holds that this must be paid — **developing across a gate (02 first, 03 later) is more
> expensive than three extra hops**: what the former produces is a criterion you cannot trust, and an
> untrustworthy criterion goes on **looking correct** in every later stage.

---

## 5. Runtime artefact contract

### Initialise on first use (**no report needed**)

When `memory.md` / `record.md` are missing, the orchestrator **creates them directly** in the
**first session** using the formats below — **without asking, without reporting**: their absence
only means "this workspace has not been run yet," **not that something is wrong**.

### `memory.md` (memory / context state, overwrite-updated)
Must contain: current stage · this round's goal · key facts read (**with file:line**) · open
questions · next step.
**Never** write unverified speculation; speculation must be explicitly marked "to be verified."

### `record.md` (execution and audit record, **append-only**)
One line each, fixed format:

```
[UTC ISO8601] <stage> <action> :: <verbatim command> :: <exit> :: <conclusion>
```

Example: `[2026-01-01T08:13:45Z] 03 measured coverage gate :: npx tsx scripts/check-coverage.ts :: 0 :: 88% floor passed (LF)`

**Never modify or delete existing lines after the fact.** It is the trace of D1 "read it before
you claim it" and the only timeline basis for a retrospective.

### The progress page (HTML, the record's **second projection**, overwrite-updated)

**There are two records and they must be at the same maturity** — a hard convention of the
framework, not optional:

| Where | Role | Update mode |
| --- | --- | --- |
| `record.md` | The **source** of the behaviour record (command-level trace) | Append-only, one line each |
| **Progress page** (HTML) | The **human-facing projection** (status / case counts / coverage / gaps / timeline) | Overwrite-sync |

**The page name is not fixed**: the progress page is **renamed** as the project advances. So the
filename is not hard-coded into scripts or docs; it is named by **`.claude/progress-page.txt` (one
line)** — **renaming the page = editing this one line**, with no change to the hook or the docs.
That file is the **single source of truth for the page name** (D4).

> ⚠️ **This was indeed missed during rollout, hence the call-out**:
> `record.md` (per-command trace) and the **progress page HTML** (the display of project
> completion) are **two kinds of record for two audiences** and **must be updated in the same
> turn**. Update only `record.md` and not the page, and the page becomes **a stale fact** —
> which D4 forbids ("two facts of different maturity").
> The criterion is mechanically enforced by the Stop hook (below), **not by good intentions**.

---

### Tracking policy (deliverables vs AI runtime state)

| Category | Examples | Tracked |
| --- | --- | --- |
| **Substantive work output** | `"$REPO"/docs/changes/*` · operations records · the only ledger · ADRs | ✅ **Tracked** |
| **AI collaboration framework** | `AGENTS.md` (this file) · `.claude/agents/*` | ⬜ **Depends on layout** |
| **AI runtime state** | `record.md` · `memory.md` · the progress page | ⬜ **Depends on layout** |

The criterion in one line: **is it "a deliverable of the project" or "how the AI does its own
work"?** Only the former is tracked.

> **This repo is the framework** (a human decision; see `"$REPO"/docs/ledger.md`, `GAP-004`):
> this repository **is** the framework's own repo, and framework files and runtime state
> **living in the same repo** is a **deliberate decision** — so the last two rows are **✅ tracked**
> under this layout (under the target layout they are outside the repo and naturally untracked).
> But **runtime state must still be kept out of commits** (otherwise anyone who clones and runs
> `git add -A` imports someone else's bookkeeping): the **repo-shipped** `.gitignore` excludes
> **only runtime state** and **must not** exclude deliverables or the framework source; under the
> **target layout** the framework is outside the repo and those rules never match, so they are
> not added.

> **Corollary discipline**: tracked files **must not reference paths that do not exist** in a
> reader's checkout. Ask first: **can a reader open this after cloning?** This repo is the
> framework, so `AGENTS.md` / `.claude/` **are** in the checkout and may be referenced; whether
> `record.md` / `memory.md` / the progress page are shipped depends on the release scope —
> confirm they are in scope before referencing them.
>
> But **historical snapshots are not rewritten**: if a **published** record genuinely contains
> such a section, it is **a fact that happened**, and rewriting it would be **tampering with the
> evidence chain**. The discipline is: "only **instructions yet to be executed** must be
> accurate; **facts that already happened** need not be."

---

### Delivery path: small commits + always via PR, pushed to the upstream author

**Human decision**: changes are **not stacked up locally**; every change is **opened as a PR
against the upstream author**.

> ⚠️ **"Push to the upstream author" holds only for an *adopter*** (`GAP-018`): **the framework repo
> itself is not a template repo being adopted** — it has no "upstream author" to push to;
> **its delivery target is itself** (`origin` *is* the target repo).
> **Test**: first decide whether **this repo is the framework repo or a business project repo**,
> then decide whom to push to.
> **Do not treat a mismatched phrase as a rule**: the rest of this section (secret scan / push-scope
> review / conflict pre-check / baseline comparison) **applies to both** — only the sentence
> "push to the upstream author" is **adopter-specific**.

| Item | Value |
| --- | --- |
| `origin` | your fork (push branches here) |
| `upstream` | **the author's repo, the PR target** |
| PR base | `upstream/main` |

**Flow**:

```
git -C "$REPO" push origin <branch>                        # push to the fork
gh pr create --repo <author-repo> --base main --head <you>:<branch>   # open the PR upstream
```

> **`$REPO` is resolved in §0.0** (`git rev-parse --show-toplevel`): `git -C "$REPO" …` operates
> on the repository.

**Mandatory before pushing** (learned the hard way; not optional):

1. **Secret scan** — compare **value by value**, not just grepping key names.
   Deployment configs **have a history of plaintext credentials**; every change must confirm no
   value entered the diff.
2. **Review the push scope** — this repo is the framework (table above), so framework files
   **are** in the push scope, which is **deliberate**; still **verify rather than assume**:
   `git -C "$REPO" ls-files` is exactly the set you intend to publish, and
   `status --porcelain` shows no unexpected changes (hard-coding `project` makes the command
   unrunnable, `exit 128` — that is "the command did not run," not "the fence works").
3. **Conflict pre-check against `upstream/main`** — `git log --name-only upstream/main ^HEAD`
   for upstream additions, intersect with local changes, then `git merge-tree` dry-run.
4. **Baseline comparison** — per convention, the PR body gives a before/after table (test
   counts, coverage, floors).

> ⚠️ **Coverage readings must come from an LF working tree.** CRLF inflates by several points
> and has been measured in a real project. At a critical floor, that difference is enough to be
> green locally and red on CI.

**Small commits (hard requirement)**: **one feature / one logical unit per commit** — **never batch a
large block into a single commit**.
- The message says **what changed, why, and how it was verified** (**including the falsification
  result**); **"it looks right" is not accepted**.
- Each commit must be **independently readable and revertable**; **unrelated changes never share a commit**.
- Produce per §3's five segments and pass §4.2's test stage **before** committing; **never stuff an
  unverified block into one commit**.
- This is **part of the delivery path**: small commits let a PR be reviewed commit by commit, and let
  `git bisect` locate **which step introduced a regression** — same root as §4.2: **only what is
  verifiable at every step can be advanced**.

**Three quantitative criteria** (source: a real production repo's adoption — turning "small" from a
slogan into a measurable scale):

1. **Magnitude**: each commit should be an **increment of roughly 3% of the target capability** — i.e.
   "one independently describable unit of improvement", not "one module". **Test**: if a commit cannot
   say which single thing it improves, it is too big.
2. **Gate**: **every increment must pass the tests before it is committed**. **A broken commit must never
   enter the git history** — `git bisect` presupposes that **every step in the history runs**.
3. **Isolation**: **unrelated changes never share one commit** (already stated above) — mixing them makes
   a single revert impossible.

> ⚠️ **These three share a root with the next rule**: **"small" is measurable** (magnitude / gate /
> isolation), not a subjective sense of "a bit smaller". **The criterion is written as "roughly 3%"
> rather than "small" precisely because "small" cannot be falsified** (D3).

> ⚠️ **This rule must be pushed down to "whoever actually writes the code", or it is just a slogan**
> (measured during rollout): the code writers are **subagents**, each with a **fresh context**, and they
> do not automatically read §5 of this file. If the dispatch merely says "complete task X", they write
> the whole module in one go and the orchestrator then makes **one huge commit per agent task** — measured
> at **+1500~3400 lines** in a single commit, exactly the shape this rule forbids. **Two fixes, both required**:
> 1. **Put it in the dispatch prompt explicitly** ("commit by logical unit — commit as soon as one
>    independently verifiable unit is done; the `docs/changes` record travels with the unit"), because
>    subagents **will not** read it from §5 themselves.
> 2. **Add the same requirement to the role output contracts** (§4.1 / `prompts/角色契约.md`) so that
>    "small commits" is a role's **inherent output**, not something the orchestrator must remember to say.
> **Criterion**: one agent task's output **should not** be a single `+N`-line commit; if that happens,
> **the dispatch failed to carry the rule**, not the agent.

### Pre-commit local gate (**the set you run locally *is* the set CI runs**)

**Criterion**: **if "run it before committing" cannot actually be run on this machine, it is not a
gate — it is only a reminder.** So fix CI's checks as a **copy-pasteable command set**, split into
Gates per stack; **if it does not pass, do not commit** (same root as "a broken commit must never
enter the history").

**Three generalisable requirements**: ① **the same set** (if local and CI differ, the "green locally,
red on CI" red **carries no information**) · ② **`--race` / race detection is not optional**
(concurrency correctness is visible **only** to a race detector) · ③ **fail on a missing
precondition, never skip silently** (a silent skip makes "did not run" look like "ran").

> 📄 **The copy-pasteable Gate commands and per-item rationale are in
> [`docs/delivery-gates.md`](docs/delivery-gates.md) (read on demand)**.
> **The authority remains this section**; that file yields to it (D4).

### Pending-action documents (**the things only a human or an external platform can do**)

**The problem**: every delivery chain has a set of things **an AI cannot do** — credentials to add in a
platform panel, branch-protection required checks, domain allow-lists, platform-side env vars. They
**must be listed explicitly**, or they sit **in no ledger and owned by nobody**, surfacing as
"the feature is done but integration does not work".

**Four hard requirements**: ① **give them their own document** (e.g. `docs/CICD-待完成.md`), **not mixed
into the `GAP-` ledger** (what is owed is not code, it is an **external action**) · ② **state its nature**:
it is a **"pending action", not a historical record**, so it **must agree with the repo as measured**
(the exact opposite of §5's "historical snapshots are not rewritten" — **the criterion is "already
happened" vs "still to do"**) · ③ **each row answers only three things**: what is missing / where to add
it / **who does it** (only "a human" or "the platform"; **no row is something an AI can do**) ·
④ **mark blocking relationships and pull the blockers out into their own list** (`blocking=no` does
**not** mean "no need to do" — **that distinction must be written down**).

> 📄 **Details (including the reverse trade-off "also list the things measured to need no configuration")
> are in [`docs/delivery-gates.md`](docs/delivery-gates.md) (read on demand)**.

### Progress-page sync (mechanically enforced by a hook)

**Human convention**: **after every change**, sync the progress page so the overall progress is
at the same maturity as the repository.

This **does not rely on good intentions** — D4 forbids "two facts of different maturity," and the
progress page is untracked, so neither the ledger nor CI can reach it. Hence the Stop hook:

| Item | Path (all at the workspace root) |
| --- | --- |
| Hook config | `.claude/settings.json` (Stop event) |
| Detection script | `.claude/hooks/check-progress.ps1` |
| **Page-name pointer** | `.claude/progress-page.txt` (**one line**; the single source of truth for the page name) |
| Progress page | the filename named by the pointer, at the workspace root, sibling to `.claude/` |

**Criterion**: **only when the progress page exists** is the SHA recorded in its status bar
(`<div>head <b>…</b></div>`) compared **by prefix** (7 or 40 characters both accepted) with
`git -C "$REPO" rev-parse --short HEAD` (`$REPO` per §0.0); on mismatch it **blocks the end of
the turn** and feeds the reason back to the model, requiring the page to be updated first.
**With no page there is no criterion** — see item 1 below.

**Five deliberate design decisions**:

1. **No check when the page does not exist** — the guard **passes silently** (`exit 0`, no output)
   when the page has not been created yet. The criterion presupposes "the page exists and must not
   lag"; with no page there is **no fact that could lag**.
   **This is "not yet initialised," not "the page is missing"** — the same convention as
   "initialise on first use" above.
2. **Pointer present but page name unreadable → `exit 1` + stderr** (empty file / all whitespace /
   unreadable). The guard then falls back to the default page name and **may be looking at the
   wrong file** — a **genuine anomaly**, hence tell the user rather than stay silent; a pointer
   file that is **entirely absent** is not an anomaly (same as item 1).
   **`git` unavailable** (the `git --version` functional probe fails) **takes the same channel**.
   **Why not `systemMessage`**: it only reaches the `Ctrl+O` transcript view, not the main
   terminal (measured on this machine: the user did not see it); `exit 1` (non-zero, not 2) is a
   **documented** "non-blocking error," visible in the transcript.
3. **Silent when the SHA marker is not found** — if the page has been restructured beyond
   recognition, a false alarm on every turn is worse than staying quiet.
4. **Block rather than remind on mismatch** — **a reminder gets ignored; a block does not.**
5. **The page name comes from a pointer file** — the page is renamed as progress advances; hard-
   coding the name in the script makes one rename silently disable it.

> ⚠️ **These branches make the script "silent on failure"**: get a path or page-name derivation
> wrong and it **passes silently forever**, while "silent" is exactly how it looks when healthy.
> The script therefore **supports both layouts** (`.claude/` at the workspace root, or falling
> back inside the repo), and verification **must run two cases**: ① **page missing** → silent
> `exit 0`; ② **inject a wrong SHA** (page **present**) → **must emit `decision:block`**.
> **Only if ② still has teeth can we infer that ①'s silence means "genuinely no criterion"
> rather than "the script is dead"** — the two are observationally equivalent.
> **Re-run both cases after renaming the page.**
> **Accepted cost**: a wrong pointer (**pointing at a non-existent page name**) still leaves the
> guard silent — indistinguishable from "not yet initialised"; residual risk in ledger `GAP-002`.

> ⚠️ **Why PowerShell rather than bash**: if Git for Windows is installed somewhere that leaves
> `usr/bin` **off the Windows PATH**, a hook written as `bash …` **must fail** when executed on
> Windows, whereas `System32\WindowsPowerShell` **is** on the PATH. **The command deliberately
> contains no backslash** — backslashes were eaten twice by shell escaping; switching to
> forward-slash paths made it disappear.
> Edit that file with an editor, not with a shell heredoc.

> ⚠️ **The hook must exist at session start to be loaded**: the settings listener only watches
> directories that already had `.claude/` **at session start**. If you add/move `.claude/`
> mid-session, you **need to open `/hooks` once to reload, or restart the session** —
> **do not count on it within the current session**. Any change to `.claude/`'s location **takes
> effect only in the next session**.

---

## 6. Identifier SSOT

| Prefix | Meaning | Location | Rule |
| --- | --- | --- | --- |
| `ADR-` | architecture decision | `"$REPO"/docs/adr/` | unique sequence number, no reuse; status marked Proposed / Accepted |
| `MIG-` | database migration | `"$REPO"/backend/migrations/` | filename carries a **timestamp** |
| `GAP-` | quality gap | `"$REPO"/docs/` (the only ledger) | **anything "not yet done" must be here, or it does not exist** |
| `INC-` | production incident | same | keep the number reserved when out of scope; do not consume it |
| `DEFER-` | deferred debt | same | **a reasoned, voluntary deferral**; the reason must be stated |

> **Locations always substitute the `$REPO` resolved in §0.0; never hard-code a directory name**
> (as in the table above).
> **This repo uses the self-hosted layout** (the workspace root itself contains `.git`), so the
> ledger lives in `docs/` under the workspace root — **inside the repository**, ✅ tracked per §5.
>
> ⚠️ **Boundary: the user's todo list does *not* go into the ledger** (`我要做什么.txt`, a **local file, untracked**).
> **One-line test**: is it "**something the user asks me to do**" (a todo / feature request), or "**something the framework itself has not done (`GAP-`) or has deliberately deferred (`DEFER-`)**"? Only the **latter** enters the ledger.
> **Why (D4: one fact, one place)**: putting a user request in **both** the source file and the ledger creates **two copies** — and two copies guarantee one goes stale first.
> **In-progress** user todos are tracked by the **source file + the progress page's group ②**; the ledger references one only when it **involves a gap or a deferral** (precedent: `DEFER-002/003/005` were **revoked** once their markers were removed — rationale in `docs/ledger-evidence/ledger-appendix-a.md`, `A.11`).
> **⇒ Relation to the first row of the table above (they must be read together, or it reads as a contradiction)**: "anything 'not yet done' must be here" **covers the framework's own scope only**; **user requests are outside that scope** — their "existence" is guaranteed by the **source file**, **which is their single source of truth** (D4).>
> ⚠️ **Ownership under multiple repos (carrying layout) must be made explicit** (`GAP-018`):
> **each repo has its own ledger and its own identifier space** — the framework repo's ledger records
> **the framework's own** open items; **a business repo's ledger records its own**.
> Their `GAP-` numbers **are unrelated and must never cross-reference each other**.
> **Test**: before writing a ledger entry, run `git rev-parse --show-toplevel` to confirm **which repo
> you are in**; **a cross-repo identifier reference is a phantom reference** (the trap measured in §8 —
> a reader cannot open the file that number lives in).

### 6.2 Issues are a **public projection of the ledger**, not a second ledger

> ⚠️ **Why this must be explicit**: the ledger lives in the repo and **outside readers will not dig through
> it**; issues, by contrast, are **subscribable, discussable and labelable**. Both **track "things not yet
> done"** ⇒ **without an explicit boundary this becomes two facts of different maturity** (D4).

**The test (three mutually exclusive destinations)**:

| Content | Where |
| --- | --- |
| **Framework gaps that already have an identifier** (`GAP-` / `DEFER-`) | **an issue is a public projection of the ledger** — it carries **only "identifier + one line + a pointer to the ledger"**, and **does not copy the ledger body** |
| **Undrafted ideas** (**no identifier yet**) | **an issue** — an identifier is assigned **only once the discussion settles** (**an identifier is a registered fact, not a pending idea**) |
| **Things only a human or a platform can do** | **not an issue** — see §5 "pending-action documents" (the "who does it" column has only two values: human / platform) |

**Hard rule**: **discussion in the issue, facts in the ledger.** Once an issue settles, **write the
conclusion back to the ledger or to the source of rules**; the issue keeps only the discussion trail.
**The test**: every issue's identifier can be found in the ledger; **an issue whose identifier cannot be
found is either still under discussion or belongs to the third category.**

> ⚠️ **The two number spaces do not interfere**: issue numbers (GitHub `#N`) and ledger identifiers
> (`GAP-` / `DEFER-`) are **two separate spaces** and **must not cross-reference** — cite an issue as
> `issue #N`, cite the ledger as `GAP-0NN`. **This framework's identifier space recognises only the latter.**

**The wiki is the same**: it is a **projection**; **the rules are not restated there**, and where it
disagrees with `AGENTS.md` / `docs/`, **the repository wins** (D4). The wiki carries only **order and entry points**.

**`git grep` the whole repo before registering** to confirm no collision (see D4).

---

### 6.1 The identifier space is **repo-wide** and **cross-branch** — looking only at the current HEAD is a **false guard**

> ⚠️ **This has been falsified three times** (measured in a real project): `docs/changes/` held **three
> `022`s**; and two **parallel unmerged branches** collided twice **in the same round** (`030`/`031`
> against `029`). Every time, the guard command (`git ls-files docs/changes/` / `git grep`) **was
> green** — because it **sees only the current checkout**, while **the number space is shared across
> branches**: each branch picks independently, and they only collide once merged.

**The correct measure**:

- When picking a number, look at the **union of all branches**, not HEAD. **List each ref's tree with
  `git ls-tree`** (`git ls-tree -r --name-only <ref> -- "$REPO/docs/changes/"`), over every
  `refs/heads` + `refs/remotes`.
- ⚠️ **Do not use `git log --all --name-only`** — it **simplifies merges by default**, so **files
  introduced by a merge commit do not appear**; the union **undercounts** and you pick a number that
  is **already taken**. Measured during rollout: a file was missed exactly this way, and an occupied
  number was chosen. If you must use log, add `-m`; but **`ls-tree` is more reliable** (it lists the
  tree's current contents, independent of merge simplification).
- **When working on a parallel branch**, look one step ahead: **between your writing and your merge,
  another branch will take numbers too**. Measured here: "two postponements collided in the same
  round" — **the problem is not that one number was chosen badly; it is that the method of choosing
  does not hold**.
- **Remember this defect's shape**: it **does not ring** — the guard is green, the number has
  collided, and it blows up at merge. Same family as §8's "tool name silently dropped": **get the
  criterion wrong and, like this, it will never raise the alarm itself**.
- **Backstop**: before merging, do a conflict pre-check on **identifier-bearing files**
  (`git merge-tree`, see §5 mandatory-before-pushing 3); an identifier collision **does show up as a
  conflict** in `merge-tree` — that is the one place that will raise the alarm for you.
  (**Mechanical implementation**: the `.claude/hooks/check-numbers.ps1` Stop hook already checks the
  per-ref `ls-tree` union on this basis, and reports on collision.)

---

## 7. Baselines must be measured (numbers must be reproducible; no hearsay)

**This section is not a table of numbers; it is a demonstration of one discipline**: any number
that gets cited must be **measured on the spot**, with a **re-runnable verification command**
attached. Rationale: D1.

> **Resolve the repo root first** (§0.0): `$REPO=$(git rev-parse --show-toplevel)`.
> **Every `$REPO` below substitutes that result; never hard-code `project`** (hard-coding makes
> the whole table `exit 128`).

| Fact | Verification command (run at the workspace root) |
| --- | --- |
| branch / HEAD | `git -C "$REPO" rev-parse --abbrev-ref HEAD && git -C "$REPO" rev-parse --short HEAD` |
| tracked file count | `git -C "$REPO" ls-files \| wc -l` |
| on-disk file count (**comparison measure**; necessarily differs from the above) | `find "$REPO" -type f -not -path "*/node_modules/*" -not -path "*/.git/*" \| wc -l` |
| coverage floor | read the **actual config value**: the contract-side script + frontend `vitest.config` |
| CI jobs | `cat "$REPO/.github/workflows/ci.yml"` |

**Honest labelling**: any number cited after **more than one commit** has passed **must be
re-measured**.

> **This table is a "template", not "current fact"**: the `.github/workflows/ci.yml`, contract
> scripts, `vitest.config` etc. in these commands **may not exist at all**.
> A failing command then is **not** a "missing baseline" but **a stage not yet built** — per §2
> it is judged **not met**, and **must not** be excused because "there is no artefact."
> Criterion: first `Test-Path` / `git ls-files` to confirm the artefact exists, then decide
> whether that baseline is "to be measured" or "the stage is not built";
> **never** cite the failing reading of an unrunnable command as a set of numbers.

> **A real example (for contrast)**: at rollout, one repo showed `ls-files` 252 and on-disk 531 —
> a **difference of 279**; both numbers **must be given together** to be honest.
> That pair **changed** once the framework moved out of the repo (229→252 / 481→531): reusing
> the old values would be the opposite of D1.
> **Old snapshots must be labelled with their capture time, not used as current values.**

---

## 8. Drift actually caught during rollout (target examples)

This section lists drift **actually caught and fixed** when the framework was built. It is not a
"common problems checklist" but **instances of criterion cracks** — each one shows that
**without measurement, it keeps looking correct.**

> **This table has no number column**: it is an **example snapshot**, not the ledger. **Full
> evidence, release conditions and retrospectives live in the only ledger**
> (`"$REPO"/docs/ledger.md`, see §6); if a case here needs tracking, register it with a `GAP-`
> number in the ledger.
> This section keeps only the **lessons** and carries no tracking duty — **so that no second list
> at a different maturity appears** (D4).

| Case | Finding | Evidence | Lesson |
| --- | --- | --- | --- |
| **ignore anchoring** | `.gitignore`'s `ignition/deployments/` **has an internal slash and no leading `**/`**, making it a **root-anchored** pattern → it matched `ignition/` only at the repo root and **never matched** the same path under a subdirectory. Several deployment artefacts (including `deployed_addresses.json`) had already been committed by mistake | `git check-ignore -v --no-index <path>` → **exit=1**; `git ls-files` shows them tracked | **`check-ignore` always returns 1 for tracked files; only `--no-index` makes it trustworthy.** Otherwise you misread it as "the rule is fine" |
| **phantom path** | Several **active** docs pointed at a file that **does not exist** (the real filename was in another directory). Four docs and one source comment were all wrong | `git grep -n "<phantom path>"` → hits in active docs; zero after re-pointing | Only found when the framework was built, while **everyone who read it until then believed it was real** |
| **coverage measure** | The coverage floor was calibrated from a **CRLF local reading** → CI's LF checkout read lower and went **red on the first run**. Same source, same compiler, same tests | Run coverage in both checkouts, compare the same metric | **Line endings are part of the measurement**, not an editor preference. This project later added `.gitattributes` to force normalisation |
| **number collision** | A problem already covered by an audit report was **mis-registered as a new number** | A whole-repo `git grep` then showed an existing number covered it | **Always search before registering** — a collision is worse than a miss (see D4) |
| **all tests green ≠ covered** | A comparison test that "looked like it protected a financial formula" had the parameter under test **deliberately set to 0** in the source — the formula **was never verified**. Someone who ran the suite once and saw green **would not know there was a hole** | Reading the source comment + the record file's own account revealed it | **"All tests green" does not mean "what is under test is covered"** |
| **two doors, running one leaks** | The same formula had **two independent** criteria (one reading the source, one reading a **vector file**). In falsification, mutating the source without regenerating the vector left **the other side still green** | Measured by mutation testing | **Verification must run both**; "I ran one and it was green" is not evidence |
| **criteria drifting with the facts** | §5 once argued the framework was untracked because "the framework is outside the repo, so its position guarantees it cannot be committed." But this repo **is** the framework's own repo — the argument's **premise no longer exists**, while the text stayed | `git rev-parse --show-toplevel` → the workspace root; `git ls-files` includes `AGENTS.md` / `CLAUDE.md` / `prompts/*` / `.claude/*`; `Test-Path .gitignore` → `False` | **Self-referential statements are never caught by any test** — they say nothing about code behaviour, only about **where they themselves sit**. Same family as the next row: when wrong they do not ring, they are merely silently wrong |
| **tool names silently dropped** | When a `tools:` name does not match the **actually mounted** name it is **silently dropped, with no error**. `.claude/agents/*.md` originally wrote `Bash` while the local mounted name is **`PowerShell`** → `Bash` was dropped → the read-only role **appeared to "have no shell capability."** This was then **misdiagnosed** as "this environment does not mount Bash," and the misdiagnosis was even **written into the source of constraints** (corrected this round) | Dispatch a subagent to **self-report its tool list** and run `Get-Location; echo probe-ok`, feeding back stdout → tool list = `Read/Grep/Glob/PowerShell`, `probe-ok`, `LASTEXITCODE=0` | **A declared capability must be measured** — `tools:` is a **declaration**; mounting is the **fact**. **"The name is wrong"** and **"the capability is missing"** are **observationally indistinguishable**; the failure is **silent**, so **no test will ever catch it**. Verification method in `.claude/agents/README.md` |

> **This document does not repeat ledger detail.** The above are **examples**; full evidence,
> release conditions and retrospectives belong in the project's **only ledger**.
> This table is merely a snapshot from when the framework was built.

---

## 9. Initialisation trigger

### 9.0 Working on an **existing** project (user todo `#19`)

**Trigger**: entering a business project that **already exists** (not starting from zero) — do **not**
just start working. Follow these **five steps**:

| Step | Action | Criterion / landing point |
| --- | --- | --- |
| **1** | **Measure the location**: `git rev-parse --show-toplevel` to establish which repo you are in; **if `memory.md` has no project location ⇒ ask the user per §0.0** | a wrong location **raises no error** — it is "silently wrong" |
| **2** | **Judge the progress**: using the **software lifecycle and the project's existing documents** (`docs/planning/` · `docs/changes/` · `docs/adr/` · the ledger · `README` · issues), determine **which stage it is currently at**, and **record it** (in `memory.md` + the progress page) | **never infer from directory or file names** (D1); **the criterion is file content**, not its existence |
| **3** | **Summarise and confirm requirements**: produce a **project overview** and **confirm the requirements** — **read them from the documents where possible**, and **ask the user** where they cannot be read; **never invent requirements** for the user (zero-assumption principle, §0.2) | confirming requirements is the **human's** prerogative, not the orchestrator's |
| **4** | **Generate domain roles**: per the project's **domain business needs**, **create** the required agents under `.claude/agents/` and **register them in the registry** | same root as user todo **`#9`** / ledger **`DEFER-006`**; **never substitute** an existing role (§4.1) |
| **5** | **Raise an ADR before developing**: assess against **software engineering norms / industry standards / the software lifecycle**, **land the ADR**, **then enter development** | **this is already a rule** — the stage-01 hard gate in §2 plus **D2 hard stage gates**; this section only demands it **actually be executed**, it **adds no new rule** (user todo `#20`) |

> ⚠️ **The mechanical strength of this section (stated honestly)**: **step 5's "is there an ADR?" has no
> guard today** — it relies on self-discipline, and falls under the `GAP-017` family; roadmap **`P2.2`**
> (`PreToolUse` pre-flight validation of the `01-design` hard assets) is exactly what fills it.
> **Step 2's "judge the progress" likewise has no criterion** — it requires **reading the documents and
> judging**, and "did you read" currently has no mechanical face.

### 9.1 Creating a project **from scratch**

When the user types **"Start a new project: [project name and business summary]"**:
1. Output the standard engineering directory skeleton (an SSOT system including `docs/adr` ·
   `docs/changes` · `docs/planning` · `tests/` · `deploy/`).
2. Generate the initial quality exit checklist (DoD) spanning the **ten stages**.
3. **Lock at the 01 design stage** and raise the **3 core architecture and boundary questions**
   that must be settled to start, **refusing to write business code until they are answered**.
