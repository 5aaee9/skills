---
name: sdd-workflow
description: Use when the user invokes $sdd-workflow or asks for spec-driven development with mandatory independent subagent review gates, subagent implementation, documentation updates, and git commit/push after reviewed work.
---

# SDD Workflow

Run a spec-driven development loop that combines Superpowers planning with independent review gates and subagent-driven implementation. Do not wait for explicit user approval unless the work is destructive, credential-gated, production-impacting, or materially scope-changing. Do not treat any gated phase as complete until every required reviewer returns the literal verdict line `VERDICT: APPROVE`.

## Required Skills

Load and follow these skills at the relevant phase:

- `superpowers:brainstorming` to turn the request into a concrete spec/design.
- `superpowers:writing-plans` to create the implementation plan from the reviewed spec.
- `superpowers:subagent-driven-development` to implement the reviewed plan with fresh implementer/reviewer subagents.
- `superpowers:verification-before-completion` before claiming completion, committing, or pushing.
- `superpowers:requesting-code-review` when an independent code/spec review is needed and the active subagent workflow does not already provide one.
- `opencode-agent` for spec/design, plan, and final implementation review when it is available.

## Hard Gates

Approval in this workflow means **all required independent reviewers approve**. A gate is satisfied only when every required reviewer returns a verdict line exactly matching `VERDICT: APPROVE`; user approval is neither requested nor accepted as a substitute unless a safety gate below requires user input. If a runtime status says "spec approval gate", interpret it as "spec reviewer verdict gate".

Required reviewers for spec/design, implementation plan, and final spec implementation:

- Always dispatch an independent reviewer subagent.
- If `opencode-agent` is available, also run the same bounded review through `opencode-agent`.
- When running `opencode-agent`, use opencode's default model by not passing `-m`, unless the user specified an opencode model for this workflow; if the user specified one, pass exactly that model.
- A review gate passes only when the independent reviewer subagent and, when available, the opencode reviewer both return `VERDICT: APPROVE`.
- If either reviewer returns `VERDICT: REVISE` or omits the exact approve verdict, revise and re-run both required reviewers for that gate.

- Do not require explicit user approval for the spec, plan, or implementation unless the user specifically asks for it or a safety gate requires it.
- Never block with a message asking the user to approve the spec/plan/implementation. Instead, dispatch or re-dispatch the required reviewers and continue until all required reviewers return `VERDICT: APPROVE`.
- Use the required reviewers for the spec/design. Continue revising the spec/design until all required reviewers return `VERDICT: APPROVE`.
- Do not write implementation code before the spec/design and plan have both passed all required reviews.
- Use the required reviewers for the implementation plan. Continue revising the plan until all required reviewers return `VERDICT: APPROVE`.
- Use subagent-driven development for implementation. Prefer fresh, bounded subagents with explicit file ownership and context.
- After implementation, use the required reviewers to check the final implementation against the reviewed spec. Continue fixing and re-reviewing until all required reviewers return `VERDICT: APPROVE`.
- Only after spec-compliance approval from all required reviewers, update relevant docs, run fresh verification, then `git commit` and `git push`.
- If `git push` is blocked by missing credentials, network failure, remote rejection, or branch policy, report the blocker with the successful local commit SHA and exact push error.

## Workflow

### 1. Establish scope and spec

1. Announce that `$sdd-workflow` is active.
2. Use `superpowers:brainstorming` to inspect the repo, clarify only material ambiguity, and write the spec/design file.
3. Do not pause for explicit user approval of the spec/design artifact. Proceed once the artifact is concrete enough for independent subagent review; ask the user only for destructive, credential-gated, production-impacting, materially scope-changing, or genuinely ambiguous decisions.
4. Dispatch the required reviewers with only:
   - the spec/design path and content,
   - relevant repo constraints,
   - the required verdict format below.
5. Require each reviewer to evaluate completeness, acceptance criteria, ambiguity, safety/rollback, docs impact, and whether the spec/design is concrete enough to plan from.
6. If any required reviewer returns anything other than `VERDICT: APPROVE`, revise the spec/design and re-review with all required reviewers.

Spec/design review verdict format:

```text
VERDICT: APPROVE | REVISE
ISSUES:
- [blocking issue or "None"]
REQUIRED_CHANGES:
- [change or "None"]
```

### 2. Write and independently review the plan

1. Use `superpowers:writing-plans` to create a plan from the reviewed spec.
2. Dispatch the required reviewers with only:
   - the spec/design path and content,
   - the plan path and content,
   - relevant repo constraints,
   - the required verdict format below.
3. Require each reviewer to evaluate completeness, task order, test strategy, docs coverage, rollback/safety, and whether the plan is implementable by subagents.
4. If any required reviewer returns anything other than `VERDICT: APPROVE`, revise the plan and re-review with all required reviewers.

Plan review verdict format:

```text
VERDICT: APPROVE | REVISE
ISSUES:
- [blocking issue or "None"]
REQUIRED_CHANGES:
- [change or "None"]
```

Proceed only when all required plan reviewers return `VERDICT: APPROVE`.

### 3. Implement using subagent-driven development

1. Use `superpowers:subagent-driven-development` to execute the reviewed plan.
2. Maintain the plan checklist as the source of truth.
3. For each implementation subtask, pass only the needed spec/plan excerpts, file ownership, constraints, and validation commands.
4. Do not accept subagent success claims without checking diffs and fresh verification evidence.
5. Resolve blockers directly when safe; ask the user only for destructive, credential-gated, production, or materially scope-changing decisions.

### 4. Independently review spec implementation

After the plan is implemented, dispatch the required reviewers to compare the final diff against the reviewed spec.

Reviewer input must include:

- spec/design path and content,
- reviewed plan path and content,
- base and head SHAs or the relevant diff,
- test/verification output,
- explicit instruction to judge spec compliance, not style preferences.

Spec implementation verdict format:

```text
VERDICT: APPROVE | REVISE
SPEC_COVERAGE:
- [implemented requirement or missing requirement]
BLOCKERS:
- [blocking gap or "None"]
REQUIRED_CHANGES:
- [change or "None"]
```

If any required reviewer returns `REVISE`, fix the gaps, rerun verification, and re-review with all required reviewers. Do not claim the spec is implemented until every required reviewer returns `VERDICT: APPROVE`.

### 5. Update docs, verify, commit, and push

After spec implementation receives `VERDICT: APPROVE` from all required reviewers:

1. Update relevant documentation, examples, changelogs, or usage notes required by the spec/plan.
2. Run fresh verification using `superpowers:verification-before-completion`; include tests, lint, typecheck, build, or targeted smoke checks appropriate for the repo.
3. Review `git status` and `git diff` to ensure only intended files changed.
4. Create a git commit using the repo's required commit format. If the repo has the Lore commit protocol, use it.
5. Run `git push` to the current branch/upstream. If no upstream exists, set the upstream for the current branch when safe and unambiguous.
6. Report the commit SHA, push result, verification evidence, docs updated, and any remaining risks.

## Reviewer Prompt Templates

Use these as compact prompts for independent reviewers. For opencode review, pass the same prompt through `opencode-agent`; use opencode's default model unless the user specified an opencode model for the workflow.

### Plan reviewer

```text
Review this implementation plan against the spec/design. Do not implement anything.
Return exactly the verdict format requested. APPROVE only if the plan is complete, ordered safely, testable, docs-aware, and suitable for subagent-driven implementation.

Spec/design: <path + content>
Plan: <path + content>
Repo constraints: <constraints>
```

### Spec/design reviewer

```text
Review this spec/design for clarity, completeness, acceptance criteria, safety, docs impact, and whether it is concrete enough to plan from. Do not implement anything.
Return exactly the verdict format requested. APPROVE only if the spec/design is actionable without explicit user approval.

Spec/design: <path + content>
Repo constraints: <constraints>
```

### Spec implementation reviewer

```text
Review the final implementation against the reviewed spec. Do not focus on subjective style unless it blocks correctness, maintainability, or verification.
Return exactly the verdict format requested. APPROVE only if every spec requirement is implemented and verified or explicitly out of scope in the reviewed spec.

Spec: <path + content>
Plan: <path + content>
Diff or base/head SHAs: <diff or SHAs>
Verification output: <commands + results>
```
