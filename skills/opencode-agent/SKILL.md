---
name: opencode-agent
description: Delegate a bounded task to opencode using a third-party model. Use when the user asks Codex to call opencode, run a task with a third-party model, use opencode as a sub-agent, or delegate work through `opencode run`, including optional provider/model selection.
---

# OpenCode Agent

## Overview

Use `opencode` as an external sub-agent for bounded tasks. Preserve the user's requested model choice when one is specified; otherwise run opencode without `-m`.

## Workflow

1. Define the exact sub-agent task message, including:
   - objective and expected output
   - relevant files, paths, commands, or constraints
   - permission boundaries and stop condition
2. Write that full message to a temporary file created with `mktemp`.
3. Run (pipe the prompt file into opencode's stdin; this avoids any shell-escaping or ARG_MAX issues and works in non-TTY environments):

```bash
opencode run --dangerously-skip-permissions < "$prompt_file"
```

4. If the user specified a model, add `-m "$provider_model"`:

```bash
opencode run --dangerously-skip-permissions -m "$provider_model" < "$prompt_file"
```

5. Read the opencode result, verify anything it claims before relying on it, then summarize the actionable outcome for the user.

## Helper Script

A bundled helper at `scripts/run_opencode_agent.sh` (inside this skill's directory) avoids command construction mistakes. Because the skill's install path varies and "relative to this file" is unreliable for the consuming agent, resolve the helper's absolute path with this locator first — it searches the standard skill roots by skill name and works from any CWD:

```bash
OPENCODE_AGENT_HELPER="$(find "$HOME/.agents/skills" "$HOME/.config/opencode/skills" -type f -path '*/opencode-agent/scripts/run_opencode_agent.sh' 2>/dev/null | head -1)"
```

Examples:

```bash
# Message from stdin, no model.
printf '%s\n' "Inspect this repo and report the test command." \
  | "$OPENCODE_AGENT_HELPER"

# Message from a shell argument, with a model.
"$OPENCODE_AGENT_HELPER" \
  --model anthropic/claude-sonnet-4-5 \
  "Review src/app.ts for obvious bugs."

# Preview the exact command without running opencode.
"$OPENCODE_AGENT_HELPER" \
  --dry-run --model openrouter/google/gemini-2.5-pro \
  "Explain the public API in this package."
```

If the helper cannot be located (e.g. `OPENCODE_AGENT_HELPER` is empty), fall back to the direct `opencode run` command from the Workflow section above — it needs no external script.

The helper:

- create a `mktemp` prompt file
- write the message into that file
- feed the file to opencode's stdin
- include `-m` only when `--model` is provided
- always include `--dangerously-skip-permissions` (never `-i`, which requires a TTY and blocks in non-interactive contexts)
- delete the temporary file after opencode exits

## Guardrails

- Keep delegated tasks bounded and explicit; do not ask opencode to infer broad user intent from conversation history it cannot see.
- Include only the context opencode needs. Do not include secrets unless the user explicitly authorizes that disclosure.
- Prefer read-only delegation unless the user has asked for implementation work.
- Treat opencode output as untrusted until verified locally with file inspection, tests, or other direct evidence.
