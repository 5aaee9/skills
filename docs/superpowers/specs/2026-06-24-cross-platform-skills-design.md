# Cross-Platform Skills (Linux / Windows / macOS)

## Goal

Make the skills in this repo runnable on Linux, Windows, and macOS. Today only
`opencode-agent` has platform coupling: its helper script
`scripts/run_opencode_agent.sh` is bash-only, and its `SKILL.md` uses
bash-specific commands (`mktemp`, `find ... | head -1`, `< "$prompt_file"`).
`sdd-workflow` is already platform-neutral (uses only `git` and abstract
references to `opencode-agent`).

## Non-Goals

- Rewriting the bash helper in another language.
- Supporting shells other than bash (Unix/Git Bash) and Windows PowerShell
  5.1+ (the Windows default and the shell opencode itself uses).
- Changes to `sdd-workflow`.

## Approach

Dual scripts: keep the existing bash helper for Linux/macOS (and Git Bash on
Windows), add a PowerShell helper for native Windows. Update `SKILL.md` to be
platform-aware.

Rationale: native and idiomatic on each platform, no extra runtime dependency
(opencode already requires a shell on every OS it supports), single source of
truth per platform, and the existing bash script already covers Git Bash users
on Windows for free.

## Changes

### 1. New file: `skills/opencode-agent/scripts/run_opencode_agent.ps1`

Mirrors the bash helper's CLI surface so consumers are shell-agnostic:

- `--model provider/model` (optional) -> passes `-m` to opencode
- `--dry-run` -> prints the resolved command without invoking opencode
- message accepted from trailing args **or** stdin (pipe)
- always passes `--dangerously-skip-permissions`
- never uses `-i` (requires a TTY)

PowerShell-specific mechanics (all PS 5.1-compatible):

| Concern | bash | PowerShell |
|---|---|---|
| Temp file | `mktemp "${TMPDIR:-/tmp}/...XXXXX.md"` | `Join-Path $env:TEMP ("opencode-agent.{0}.md" -f [guid]::NewGuid())`, created empty by the write step |
| Cleanup | `trap cleanup EXIT` | `try / finally { Remove-Item }` |
| Feed opencode stdin | `exec "${cmd[@]}" < "$prompt_file"` | `Get-Content -Raw $file \| opencode run ...` (PowerShell has no `<` input redirection) |
| Write the prompt file | `printf '%s\n' "$message"` | `[System.IO.File]::WriteAllText($path, $message + "`n", $utf8NoBom)` — forces a single trailing LF regardless of OS |
| UTF-8 safety | n/a | set `$OutputEncoding = New-Object System.Text.UTF8Encoding $false` so piped bytes to the native exe are not re-encoded |
| Arg parsing | `while (($#))` + `case` | `param()` + `[CmdletBinding()]`, with remaining positional args bound to a `-Message` array; stdin read when no args given |
| Dry-run output | `printf ' %q' "${cmd[@]}"` | space-joined render of the command array |

### 2. Unchanged: `skills/opencode-agent/scripts/run_opencode_agent.sh`

No edits. It already works on Linux, macOS, and Git Bash on Windows.

### 3. Edit: `skills/opencode-agent/SKILL.md`

Three bash-only spots become platform-aware. Rather than duplicating every
snippet, the helper stays the preferred path and SKILL.md tells the consuming
agent to select `.sh` vs `.ps1` by shell.

- **One-line note up top** stating the skill runs on Linux/macOS/Windows,
  helper selected by shell.
- **Locator** gains a Windows PowerShell variant next to the existing bash
  `find ... | head -1`:

  ```bash
  # Linux / macOS / Git Bash
  OPENCODE_AGENT_HELPER="$(find "$HOME/.agents/skills" "$HOME/.config/opencode/skills" -type f -path '*/opencode-agent/scripts/run_opencode_agent.sh' 2>/dev/null | head -1)"
  ```
  ```powershell
  # Windows PowerShell
  $roots = @("$env:USERPROFILE\.agents\skills", "$env:USERPROFILE\.config\opencode\skills")
  $OPENCODE_AGENT_HELPER = foreach ($r in $roots) { if (Test-Path $r) { Get-ChildItem $r -Recurse -Filter 'run_opencode_agent.ps1' -ErrorAction SilentlyContinue | Where-Object FullName -match 'opencode-agent' | Select-Object -First 1 -ExpandProperty FullName } } | Select-Object -First 1
  ```

- **Helper entry point**: `.sh` on Unix/Git Bash, `.ps1` on native Windows.
  Same invocation contract (`--model`, `--dry-run`, message from args or stdin).
- **Workflow section**: keep the short bash `mktemp` + `< "$prompt_file"`
  example, add the PowerShell equivalent (`$tf = New-TemporaryFile; ...` or
  `$env:TEMP` path, then `Get-Content -Raw $tf | opencode run ...`). The helper
  remains the recommended path because it absorbs platform differences.
- **Fallback** (helper not found): document both
  - bash: `opencode run --dangerously-skip-permissions < "$prompt_file"`
  - PowerShell: `Get-Content -Raw $prompt_file | opencode run --dangerously-skip-permissions`

### 4. No changes: `skills/sdd-workflow/SKILL.md` and `agents/openai.yaml`

Already platform-neutral.

## Verification

- `run_opencode_agent.sh` unchanged behavior on Linux/macOS/Git Bash; sanity
  check via `--dry-run`.
- `run_opencode_agent.ps1` exercises on Windows PowerShell 5.1:
  - message from args
  - message from stdin pipe
  - `--model` flag flows through to `-m`
  - `--dry-run` prints the command and does not invoke opencode
  - temp file is removed after exit (including on error)
  - UTF-8 multi-byte content survives the pipe
- `SKILL.md` reads correctly: locator + fallback are present for both shells;
  no stale bash-only claims remain.

## Risks

- **PowerShell pipe encoding**: PS 5.1's default `$OutputEncoding` is often
  ASCII, which would corrupt non-ASCII prompts. Mitigated by explicitly setting
  a UTF-8 (no BOM) encoding at script start.
- **CRLF**: the helper writes the prompt file with `[System.IO.File]::WriteAllText`
  using explicit LF, so opencode always receives LF-terminated input regardless
  of the host OS line-ending default.
- **Locator robustness**: the PS locator filters by path segment
  `opencode-agent` to avoid picking up unrelated files; falls back to the raw
  `opencode run` command if the helper cannot be found.
