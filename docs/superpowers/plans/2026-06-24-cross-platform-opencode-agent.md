# Cross-Platform opencode-agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the `opencode-agent` skill runnable on Linux, Windows, and macOS by adding a Windows PowerShell helper alongside the existing bash helper and making `SKILL.md` platform-aware.

**Architecture:** Dual per-shell helper scripts with an identical CLI surface. `run_opencode_agent.sh` (unchanged) covers Linux, macOS, and Git Bash on Windows. A new `run_opencode_agent.ps1` covers native Windows PowerShell 5.1+. `SKILL.md` shows both shells wherever they differ and tells the consuming agent to pick the helper by shell.

**Tech Stack:** Bash (unchanged), Windows PowerShell 5.1+ (new helper), Markdown. No new runtime dependencies.

## Global Constraints

- Windows target shell is Windows PowerShell 5.1 (the OS default and the shell opencode itself uses). Do not use PowerShell 7-only syntax (no `??`, no ternary `? :`, no null-coalescing-assignment).
- The PowerShell helper MUST be invokable under the default `Restricted` execution policy — achieved by invoking it via `powershell -NoProfile -ExecutionPolicy Bypass -File`.
- GNU-style flags (`--model`, `--dry-run`, `--help`) MUST keep working on PowerShell with the same names as bash (so consumers are shell-agnostic). This requires parsing the raw `$args` automatic variable instead of a `param()` block, because PowerShell's parameter binder mangles `--flag` style names.
- Non-ASCII prompts MUST survive end-to-end. PS 5.1 defaults decode no-BOM UTF-8 as ANSI, so the helper writes the prompt file as UTF-8-no-BOM and reads it back with `Get-Content -Encoding UTF8`.
- The bash helper (`run_opencode_agent.sh`) is NOT modified.
- `sdd-workflow` and `agents/openai.yaml` are NOT modified.

---

## Task 1: Create `run_opencode_agent.ps1`

**Files:**
- Create: `skills/opencode-agent/scripts/run_opencode_agent.ps1`

**Interfaces:**
- Consumes: `opencode` on PATH (native command).
- Produces: a CLI tool invoked as `powershell -NoProfile -ExecutionPolicy Bypass -File <path> [--model provider/model] [--dry-run] [message...]` that exits with opencode's exit code and writes nothing extra to stdout except opencode's own output (plus dry-run lines when `--dry-run`).

**Validated design notes (already prototyped — implement verbatim):**
- No `param()` block; use the `$args` automatic variable so `--model`/`--dry-run`/`--` are not mangled by PowerShell's named-parameter binder.
- Collect pipeline stdin via `foreach ($__line in $input)`; fall back to `[Console]::In.ReadToEnd()` when stdin is redirected (e.g. invoked as a child `powershell -File`). Trim trailing CR/LF to match bash's `"$(cat)"`.
- Write the prompt file with `[System.IO.File]::WriteAllText($path, $msg + "\`n", $utf8NoBom)` (forces a single trailing LF).
- Feed opencode with `Get-Content -Raw -Encoding UTF8 $file | & opencode @args` (the `-Encoding UTF8` is mandatory — verified that without it, `é` is misread as ANSI mojibake `Ã`).
- Restore `[Console]::OutputEncoding`, `[Console]::InputEncoding`, and `$OutputEncoding` in `finally`.

- [ ] **Step 1: Confirm the helper does not exist yet (failing baseline)**

Run from repo root:
```powershell
Test-Path -LiteralPath "skills\opencode-agent\scripts\run_opencode_agent.ps1"
```
Expected: `False`.

- [ ] **Step 2: Create the script with this exact content**

Create `skills/opencode-agent/scripts/run_opencode_agent.ps1`:

```powershell
#requires -Version 5.1
$ErrorActionPreference = 'Stop'

function Write-Usage {
    @'
Usage:
  run_opencode_agent.ps1 [--model provider/model] [--dry-run] [message...]
  "message" | run_opencode_agent.ps1 [--model provider/model]

Writes the delegated task message to a temp file and runs:
  opencode run --dangerously-skip-permissions [-m provider/model]
'@ | Write-Output
}

# Collect pipeline input (when used inside a PowerShell pipeline). When invoked
# as a child `powershell -File`, stdin arrives as redirected external input and
# is read via [Console]::In below instead.
$script:__piped = [System.Collections.Generic.List[string]]::new()
foreach ($__line in $input) { if ($null -ne $__line) { $script:__piped.Add("$__line") } }

$model = ''
$dryRun = $false
$msg = [System.Collections.Generic.List[string]]::new()
$allArgs = @($args)
$i = 0
while ($i -lt $allArgs.Count) {
    $tok = $allArgs[$i]
    if ($tok -eq '-h' -or $tok -eq '--help') {
        Write-Usage; exit 0
    } elseif ($tok -eq '-m' -or $tok -eq '--model') {
        if (($i + 1) -ge $allArgs.Count -or [string]::IsNullOrWhiteSpace($allArgs[$i + 1])) {
            [Console]::Error.WriteLine('error: --model requires a provider/model value'); exit 2
        }
        $model = $allArgs[$i + 1]; $i += 2; continue
    } elseif ($tok -eq '--dry-run') {
        $dryRun = $true; $i += 1; continue
    } elseif ($tok -eq '--') {
        for ($j = $i + 1; $j -lt $allArgs.Count; $j++) { $msg.Add($allArgs[$j]) }
        $i = $allArgs.Count; continue
    } elseif ($tok.StartsWith('-')) {
        [Console]::Error.WriteLine("error: unknown option: $tok"); exit 2
    } else {
        for ($j = $i; $j -lt $allArgs.Count; $j++) { $msg.Add($allArgs[$j]) }
        $i = $allArgs.Count; continue
    }
}

if ($msg.Count -gt 0) {
    $messageText = $msg -join ' '
} elseif ($script:__piped.Count -gt 0) {
    $messageText = $script:__piped -join "`n"
} elseif ([Console]::IsInputRedirected) {
    $messageText = [Console]::In.ReadToEnd()
} else {
    $messageText = ''
}
$messageText = $messageText.TrimEnd("`r", "`n")

if ([string]::IsNullOrWhiteSpace($messageText)) {
    [Console]::Error.WriteLine('error: message is required via arguments or stdin'); exit 2
}

# UTF-8 without BOM for both the prompt file and the pipe to the native exe.
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
$prevOutEnc = [Console]::OutputEncoding
$prevInEnc = [Console]::InputEncoding
$prevOutputEnc = $OutputEncoding
[Console]::OutputEncoding = $utf8NoBom
[Console]::InputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom

$tempPath = Join-Path $env:TEMP ("opencode-agent.{0}.md" -f [guid]::NewGuid().ToString('N'))
try {
    [System.IO.File]::WriteAllText($tempPath, $messageText + "`n", $utf8NoBom)

    $opencodeArgs = @('run', '--dangerously-skip-permissions')
    if ($model -ne '') { $opencodeArgs += @('-m', $model) }

    if ($dryRun) {
        Write-Output ("Prompt file: {0}" -f $tempPath)
        Write-Output ("Command: opencode {0}" -f ($opencodeArgs -join ' '))
        $bytes = (Get-Item -LiteralPath $tempPath).Length
        Write-Output ("Message bytes: {0}" -f $bytes)
    } else {
        Get-Content -Raw -Encoding UTF8 -LiteralPath $tempPath | & opencode @opencodeArgs
        exit $LASTEXITCODE
    }
} finally {
    if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force }
    [Console]::OutputEncoding = $prevOutEnc
    [Console]::InputEncoding = $prevInEnc
    $OutputEncoding = $prevOutputEnc
}
```

- [ ] **Step 3: Verify `--help`**

Run:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "skills\opencode-agent\scripts\run_opencode_agent.ps1" --help
```
Expected: prints the Usage block; `$LASTEXITCODE` is `0`.

- [ ] **Step 4: Verify dry-run with `--model` renders the correct command**

Run:
```powershell
$out = powershell -NoProfile -ExecutionPolicy Bypass -File "skills\opencode-agent\scripts\run_opencode_agent.ps1" --dry-run --model anthropic/claude-sonnet-4-5 "Review src/app.ts"
$out
if (($out -join '|') -notmatch 'opencode run --dangerously-skip-permissions -m anthropic/claude-sonnet-4-5') { throw 'dry-run/model command mismatch' }
```
Expected: a `Prompt file:` line, a `Command: opencode run --dangerously-skip-permissions -m anthropic/claude-sonnet-4-5` line, and a `Message bytes: 18` line (`Review src/app.ts` = 17 ASCII bytes + LF). No throw.

- [ ] **Step 5: Verify dry-run WITHOUT `--model`**

Run:
```powershell
$out = powershell -NoProfile -ExecutionPolicy Bypass -File "skills\opencode-agent\scripts\run_opencode_agent.ps1" --dry-run "hello"
if (($out -join '|') -notmatch 'Command: opencode run --dangerously-skip-permissions') { throw 'no-model command mismatch' }
if (($out -join '|') -match '-m ') { throw 'unexpected -m in no-model output' }
```
Expected: `Command: opencode run --dangerously-skip-permissions`. No throw.

- [ ] **Step 6: Verify message from stdin (pipe)**

Run:
```powershell
$out = "Inspect this repo" | powershell -NoProfile -ExecutionPolicy Bypass -File "skills\opencode-agent\scripts\run_opencode_agent.ps1" --dry-run
if (($out -join '|') -notmatch 'Message bytes: 18') { throw 'stdin message not captured (expected 18 = 17 + LF)' }
```
Expected: `Message bytes: 18` (`Inspect this repo` = 17 bytes + LF). No throw.

- [ ] **Step 7: Verify temp file is cleaned up after exit**

Run:
```powershell
$out = powershell -NoProfile -ExecutionPolicy Bypass -File "skills\opencode-agent\scripts\run_opencode_agent.ps1" --dry-run "cleanup check"
$path = ($out | Where-Object { $_ -like 'Prompt file: *' }) -replace '^Prompt file: ', ''
if (Test-Path -LiteralPath $path) { throw 'temp file was not removed' }
```
Expected: no throw (file gone after the script exits).

- [ ] **Step 8: Verify error exits (exit code 2)**

Run:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "skills\opencode-agent\scripts\run_opencode_agent.ps1" --model 2>$null; "model_empty_exit=$LASTEXITCODE"
powershell -NoProfile -ExecutionPolicy Bypass -File "skills\opencode-agent\scripts\run_opencode_agent.ps1" --bogus x 2>$null; "unknown_opt_exit=$LASTEXITCODE"
powershell -NoProfile -ExecutionPolicy Bypass -File "skills\opencode-agent\scripts\run_opencode_agent.ps1" 2>$null; "empty_msg_exit=$LASTEXITCODE"
```
Expected: all three exit codes are `2`.

- [ ] **Step 9: Verify `--` separator passes a literal message that starts with a dash**

Run:
```powershell
$out = powershell -NoProfile -ExecutionPolicy Bypass -File "skills\opencode-agent\scripts\run_opencode_agent.ps1" --dry-run -- "--weird-message"
if (($out -join '|') -notmatch 'Message bytes: 16') { throw 'dash-separator message wrong (expected --weird-message = 15 + LF = 16)' }
```
Expected: `Message bytes: 16` (`--weird-message` = 15 bytes + LF). No throw. (This is the case that broke under a `param()`-based parser.)

- [ ] **Step 10: Verify multibyte (UTF-8) round-trip via the args path**

Run (all in one UTF-8-configured process so the arg reaches the child intact):
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command {
    $OutputEncoding = New-Object System.Text.UTF8Encoding $false
    [Console]::OutputEncoding = $OutputEncoding
    $e = [char]0x00E9
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File "skills\opencode-agent\scripts\run_opencode_agent.ps1" --dry-run "caf$e review"
    if (($out -join '|') -notmatch 'Message bytes: 13') { throw ('multibyte args path wrong: ' + ($out -join '|')) }
    'multibyte args OK (13 bytes)'
}
```
Expected: prints `multibyte args OK (13 bytes)`. (`café review` = c,a,f,é(2),space,r,e,v,i,e,w = 12 UTF-8 bytes + LF = 13.) Confirms the args path preserves non-ASCII into the UTF-8 prompt file.

- [ ] **Step 11: Confirm the bash helper is unchanged**

Run:
```powershell
(Get-FileHash -LiteralPath "skills\opencode-agent\scripts\run_opencode_agent.sh" -Algorithm SHA256).Hash
```
Expected: `82883EDE104813F4C264CBB8A5262B3BDB6747B3E54DBC3B2674CD0FCC0B3858` (the pre-task SHA; if it differs, the bash file was accidentally edited — revert it).

- [ ] **Step 12: Commit**

```powershell
git add skills/opencode-agent/scripts/run_opencode_agent.ps1
git commit -m "feat(opencode-agent): add cross-platform PowerShell helper"
```

---

## Task 2: Make `SKILL.md` platform-aware

**Files:**
- Modify: `skills/opencode-agent/SKILL.md`

**Interfaces:**
- Consumes: the helper from Task 1 (`.ps1`) and the existing `.sh`.
- Produces: documentation that a consuming agent can follow on Linux, macOS, or Windows without hitting bash-only commands.

The edits below are exact old→new replacements. Apply each with the Edit tool using the surrounding context shown.

- [ ] **Step 1: Add a cross-platform note to the Overview**

Old:
```
Use `opencode` as an external sub-agent for bounded tasks. Preserve the user's requested model choice when one is specified; otherwise run opencode without `-m`.
```
New:
```
Use `opencode` as an external sub-agent for bounded tasks. Preserve the user's requested model choice when one is specified; otherwise run opencode without `-m`.

This skill works on Linux, macOS, and Windows. A bundled helper absorbs platform differences: use `run_opencode_agent.sh` in bash (Linux, macOS, or Git Bash on Windows) and `run_opencode_agent.ps1` in Windows PowerShell. Snippets below show both shells where they differ.
```

- [ ] **Step 2: Replace the bash-only Workflow steps 2–4 with dual-shell versions**

Old:
```
2. Write that full message to a temporary file created with `mktemp`.
3. Run (pipe the prompt file into opencode's stdin; this avoids any shell-escaping or ARG_MAX issues and works in non-TTY environments):

```bash
opencode run --dangerously-skip-permissions < "$prompt_file"
```

4. If the user specified a model, add `-m "$provider_model"`:

```bash
opencode run --dangerously-skip-permissions -m "$provider_model" < "$prompt_file"
```
```
New:
```
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
```

- [ ] **Step 3: Replace the entire `## Helper Script` section with the platform-aware version**

Old (the whole section from `## Helper Script` through the `If the helper cannot be located ...` paragraph and the `The helper:` bullet list — i.e. everything between `## Workflow`'s end and `## Guardrails`):

```
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
```

New:

```
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
```

- [ ] **Step 4: Verify the SKILL.md edits**

Run:
```powershell
$c = Get-Content -Raw -LiteralPath "skills\opencode-agent\SKILL.md"
foreach ($needle in 'run_opencode_agent.sh','run_opencode_agent.ps1','find "$HOME/.agents/skills"','$env:USERPROFILE\.agents\skills','-ExecutionPolicy Bypass','Get-Content -Raw -Encoding UTF8','This skill works on Linux, macOS, and Windows') {
    if ($c -notlike "*$needle*") { throw "SKILL.md missing expected content: $needle" }
}
'SKILL.md content OK'
```
Expected: prints `SKILL.md content OK`; no throw. Confirms both shells' locator, entry point, fallback, and the cross-platform note are all present.

- [ ] **Step 5: Sanity-check the rendered locator would find the helper**

Run (Windows):
```powershell
$roots = @("$env:USERPROFILE\.agents\skills", "$env:USERPROFILE\.config\opencode\skills")
$found = $roots | Where-Object { Test-Path $_ } | ForEach-Object { Get-ChildItem $_ -Recurse -Filter 'run_opencode_agent.ps1' -ErrorAction SilentlyContinue } | Where-Object FullName -match 'opencode-agent' | Select-Object -First 1 -ExpandProperty FullName
"locator ran without error; found=$found"
```
Expected: prints `locator ran without error; found=<path or empty>` with no exception. (`found` may be empty if the skill isn't installed under those roots in this dev checkout — that's fine; the locator must simply not throw.)

- [ ] **Step 6: Commit**

```powershell
git add skills/opencode-agent/SKILL.md
git commit -m "docs(opencode-agent): cross-platform helper guidance for bash and PowerShell"
```

---

## Self-Review (completed by plan author)

**Spec coverage:**
- "New file `run_opencode_agent.ps1` mirroring CLI surface" → Task 1 (model/dry-run/args/stdin, temp file, cleanup, UTF-8/LF). ✓
- "PS 5.1-compatible mechanics (temp via `$env:TEMP`+guid, try/finally, `Get-Content -Raw | opencode`, UTF-8-no-BOM, raw `$args` parsing)" → Task 1 code, validated by Steps 3–10. ✓
- "bash helper unchanged" → Task 1 Step 11 asserts SHA. ✓
- "SKILL.md: platform note, dual locator, dual entry points, dual workflow snippets, dual fallback, helper bullets incl. PS specifics" → Task 2 Steps 1–3. ✓
- "sdd-workflow / openai.yaml unchanged" → Global Constraints. ✓
- Spec "Verification" exercises → Task 1 Steps 3–10 cover args, stdin, model, dry-run, cleanup, UTF-8. ✓

**Placeholder scan:** No TBD/TODO/vague. All code blocks contain final content. ✓

**Type/name consistency:** Helper filename `run_opencode_agent.ps1`, temp-file pattern `opencode-agent.<guid>.md`, flag names `--model`/`--dry-run`/`--help`, opencode args `run --dangerously-skip-permissions [-m model]` — identical between Task 1 code, Task 1 verification, and Task 2 docs. ✓

**One scope note surfaced during validation (not a spec gap):** PS 5.1's default `$OutputEncoding` is ASCII, so multibyte prompts are safest via the args path. This is documented in Task 2's `Note on multibyte content` rather than handled in code, matching the bash helper's equivalent reliance on upstream locale. Acceptable per spec Risk section.
