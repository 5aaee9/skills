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
