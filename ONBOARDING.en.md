# ONBOARDING — getting a new user attached

> **What this file is**: an **on-demand onboarding guide** — it answers only "what is the first step after cloning".
> **Not read normally**: it is **not loaded** in day-to-day sessions and **costs no context** — **no entry point `@`-imports it**.
> **Trigger**: the first time you **clone this framework**, or when the user asks "**how do I start**" / "**what is step one**".
> **The authoritative source of rules is still `AGENTS.md`** — if this file conflicts with it, **`AGENTS.md` wins** (D4).
> This file gives **order and entry points only**; it **does not restate rules**. Once you finish it, you need not come back (section five).

---

## 1. Two paths — pick one first

- **Path A: clone the framework, then put a business repo inside it** → **described in full here** (section two).
- **Path B: embed the framework into a project you already have** → see [`docs/adopting.md`](docs/adopting.md)
  (**a pointer only; its content is not restated here** — that file covers the other path).

> **The test, in one line**: **framework first, business next ⇒ path A**; **project first, framework next ⇒ path B**.
> The two paths are **mutually exclusive**; but **after attachment** they run the same way — both **start from the workspace root**.

## 2. Path A · three steps

Finish these three steps and the **attach check** is done; after that you can close this file.

1. **Place the business repo**: put an **independent repo** (one that **has its own `.git`**) under the workspace root.
   Its name is **arbitrary** — `project/` is only a **placeholder name** used in the docs, not a required directory name.
   - **The test, in one line**: **a subdirectory that contains `.git` is a business repo**;
     **never** decide by asking "is there a directory called `project`" (`AGENTS.md` §0.0).
   - **The exclusion must be measured**: that directory's path **must not** appear in `git status --porcelain`;
     otherwise a single `git add -A` writes the whole thing into the framework repo.
   - Reference command (Windows PowerShell — list which subdirectories of the workspace root are independent repos):
     `Get-ChildItem -Directory -Force | Where-Object { Test-Path (Join-Path $_.FullName '.git') }`

2. **Launch from the workspace root**: `launchers/start_claude.bat` (Windows) /
   `launchers/start_claude.sh` (Linux/macOS).
   The three lookup paths (`AGENTS.md` / `.claude/agents/` / `settings.json`) **scan upward only, never downward** —
   launched from anywhere else, the framework is **silently absent** (no error, it just looks as if it was never installed).

3. **Say your first sentence**: e.g. "**The business repo is in `<dir>/` — take a look at how far it has got**".
   You do **not** need to read `AGENTS.md` first — the orchestrator takes over per the rules; you only need to point at the **right object**.

## 3. The AI will say this to you first

> "I will first understand how far this business repo has got — reading its project documents and code, and producing a **status baseline** for the work that follows."

**This is not small talk**; it is required by `AGENTS.md` §9.0 (the opening line + step 2's "judging the progress must land on disk").
Its purpose is to separate "**the AI is understanding**" from "**the AI has started building**" — otherwise the two look identical from the outside.

The baseline **lands inside the business repo**: `<businessrepo>/docs/planning/baseline-YYYYMMDD.md`.
**The framework repo holds no business state** — business facts go in the business repo; citing identifiers across repos is a phantom citation (`AGENTS.md` §6).

## 4. The status baseline template

**Six sections, for the AI to copy** (if the business repo already has its own `docs/` conventions, **follow those**; this template is a **default**, not a mandated format):

1. **Business overview and goals** — what was **read**, not what was inferred.
2. **List of documents read** — **path:line** (D1 "read it before you claim it"; a conclusion without a line number means it was not read).
3. **The lifecycle stage judged** — which of stages 01–10, and the **evidence** (file content, not directory names).
4. **The finished, non-negotiable baseline** — `AGENTS.md` §0.2: anything that runs **must not** be rewritten or torn out without an architecture directive.
5. **Unfinished / blocked items** — separating "**actionable**" from "**blocked**" (external dependency / missing credentials / missing parameters).
6. **The minimum scope of the next step** — do only the current step; **do not widen it in passing**.

## 5. Read it once, then stop

This file is **not `@`-imported by any entry point** (neither `CLAUDE.md` nor `GEMINI.md` imports it).
**After the first attachment you need not read it again** — from then on, rules live in `AGENTS.md` and the ledger lives in `docs/ledger.md`.

## 6. When something goes wrong

Found a defect in the framework itself (documentation drift, a criterion without teeth, a guide that leads nowhere) → open an issue at
<https://github.com/Yotoha0303/ai-collaboration-framework/issues> (user todo `#26`).
**Search the existing issues first** — tracking one thing in two places means two facts at different levels of maturity (D4).
