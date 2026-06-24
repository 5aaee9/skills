---
name: opencode-agent
description: Delegate a bounded task to opencode using a third-party model. Use when the user asks Codex to call opencode, run a task with a third-party model, use opencode as a sub-agent, or delegate work through `opencode run`, including optional provider/model selection.
---

# OpenCode Agent

## Overview

Use `opencode` as an external sub-agent for bounded tasks. Preserve the user's requested model choice when one is specified; otherwise run opencode without `-m`.

This skill works on Linux, macOS, and Windows. A bundled helper absorbs platform differences: use `run_opencode_agent.sh` in bash (Linux, macOS, or Git Bash on Windows) and `run_opencode_agent.ps1` in Windows PowerShell. Snippets below show both shells where they differ.

## Workflow

1. Define the exact sub-agent task message, including:
   - objective and expected output
   - relevant files, paths, commands, or constraints
   - permission boundaries and stop condition
2. Write that full message to a temporary file.
3. Run (feed the prompt file into opencode's stdin; this avoids any shell-escaping or ARG_MAX issues and works in non-TTY environments):

```bash
# Linux / macOS / Git Bash
prompt_file="$(mktemp "${TMPDIR:-/tmp}/opencode-agent.XXXXXX.md")"
printf '%s\n' "$message" > "$prompt_file"
opencode run --dangerously-skip-permissions < "$prompt_file"
```

```powershell
# Windows PowerShell
$promptFile = Join-Path $env:TEMP ("opencode-agent.{0}.md" -f [guid]::NewGuid().ToString('N'))
[System.IO.File]::WriteAllText($promptFile, "$message`n", (New-Object System.Text.UTF8Encoding $false))
Get-Content -Raw -Encoding UTF8 -LiteralPath $promptFile | opencode run --dangerously-skip-permissions
```

4. If the user specified a model, add `-m "$provider_model"` to the `opencode run` command above (same flag in both shells).

5. Read the opencode result, verify anything it claims before relying on it, then summarize the actionable outcome for the user.

## Helper Script

Bundled helpers avoid command construction, encoding, and cleanup mistakes. There is one per shell, with the same interface (optional `--model provider/model`, optional `--dry-run`, message from trailing args or stdin):

- `scripts/run_opencode_agent.sh` — bash (Linux, macOS, Git Bash on Windows)
- `scripts/run_opencode_agent.ps1` — Windows PowerShell 5.1+

Because the skill's install path varies and "relative to this file" is unreliable for the consuming agent, resolve the helper's absolute path with a locator first — it searches the standard skill roots by skill name and works from any CWD:

```bash
# Linux / macOS / Git Bash
OPENCODE_AGENT_HELPER="$(find "$HOME/.agents/skills" "$HOME/.config/opencode/skills" -type f -path '*/opencode-agent/scripts/run_opencode_agent.sh' 2>/dev/null | head -1)"
```

```powershell
# Windows PowerShell
$roots = @("$env:USERPROFILE\.agents\skills", "$env:USERPROFILE\.config\opencode\skills")
$OPENCODE_AGENT_HELPER = $roots |
  Where-Object { Test-Path $_ } |
  ForEach-Object { Get-ChildItem $_ -Recurse -Filter 'run_opencode_agent.ps1' -ErrorAction SilentlyContinue } |
  Where-Object FullName -match 'opencode-agent' |
  Select-Object -First 1 -ExpandProperty FullName
```

Examples (bash):

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

Examples (Windows PowerShell) — invoke via `powershell -NoProfile -ExecutionPolicy Bypass -File` so the default `Restricted` execution policy never blocks the helper:

```powershell
# Message from stdin, no model.
"Inspect this repo and report the test command." |
  powershell -NoProfile -ExecutionPolicy Bypass -File "$OPENCODE_AGENT_HELPER"

# Message from an argument, with a model.
powershell -NoProfile -ExecutionPolicy Bypass -File "$OPENCODE_AGENT_HELPER" `
  --model anthropic/claude-sonnet-4-5 `
  "Review src/app.ts for obvious bugs."

# Preview the exact command without running opencode.
powershell -NoProfile -ExecutionPolicy Bypass -File "$OPENCODE_AGENT_HELPER" `
  --dry-run --model openrouter/google/gemini-2.5-pro `
  "Explain the public API in this package."
```

If the helper cannot be located (`OPENCODE_AGENT_HELPER` is empty), fall back to the direct `opencode run` command from the Workflow section above:

```bash
# bash
opencode run --dangerously-skip-permissions < "$prompt_file"
```

```powershell
# Windows PowerShell
Get-Content -Raw -Encoding UTF8 -LiteralPath $promptFile | opencode run --dangerously-skip-permissions
```

The helper:

- creates a temp prompt file under the OS temp dir (`mktemp` on bash; a `opencode-agent.<guid>.md` file under `$env:TEMP` on PowerShell)
- writes the message as UTF-8 without BOM, with a single trailing LF
- feeds the file to opencode's stdin (bash: `< file`; PowerShell: `Get-Content -Raw -Encoding UTF8 | opencode`, where `-Encoding UTF8` is required so a no-BOM UTF-8 file is not misread as ANSI)
- includes `-m` only when `--model` is provided
- always includes `--dangerously-skip-permissions` (never `-i`, which requires a TTY and blocks in non-interactive contexts)
- deletes the temporary file after opencode exits
- (PowerShell) must be invoked with `-ExecutionPolicy Bypass` because the system policy defaults to `Restricted`

Note on multibyte content: on Windows PowerShell 5.1 the default `$OutputEncoding` is ASCII, so piping non-ASCII text *into* the helper via stdin can corrupt it. For prompts containing non-ASCII characters, pass the message as an argument (argv is UTF-16) or set `$OutputEncoding = New-Object System.Text.UTF8Encoding $false` in the caller before piping.

## Guardrails

- Keep delegated tasks bounded and explicit; do not ask opencode to infer broad user intent from conversation history it cannot see.
- Include only the context opencode needs. Do not include secrets unless the user explicitly authorizes that disclosure.
- Prefer read-only delegation unless the user has asked for implementation work.
- Treat opencode output as untrusted until verified locally with file inspection, tests, or other direct evidence.
