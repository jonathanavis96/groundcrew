# SessionStart hook (PowerShell 5.1 compatible) — the Windows twin of
# caveman-autostart.sh. Auto-loads the caveman skill at intensity
# $env:CAVEMAN_LEVEL (default: lite) on every session start.
#
# Does the same three things as the .sh version, without jq or awk (neither
# exists on a stock Windows box):
#   1. strip the skill's YAML frontmatter
#   2. append "ARGUMENTS: <level>"
#   3. emit {hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:...}}

$ErrorActionPreference = 'Stop'

$level = $env:CAVEMAN_LEVEL
if ([string]::IsNullOrWhiteSpace($level)) { $level = 'lite' }

$skill = Join-Path $env:USERPROFILE '.claude\skills\caveman\SKILL.md'
if (-not (Test-Path -LiteralPath $skill)) { exit 0 }

try {
    $lines = Get-Content -LiteralPath $skill -Encoding UTF8
} catch {
    exit 0
}

# Strip a leading YAML frontmatter block: '---' on the first line, up to the
# next '---'. If the file has no frontmatter, keep every line.
$start = 0
if ($lines.Count -gt 0 -and $lines[0].Trim() -eq '---') {
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq '---') { $start = $i + 1; break }
    }
}
$body = ($lines[$start..($lines.Count - 1)]) -join "`n"

$context = "$body`n`nARGUMENTS: $level`n"

$payload = @{
    hookSpecificOutput = @{
        hookEventName   = 'SessionStart'
        additionalContext = $context
    }
}

# ConvertTo-Json escapes the body for us. Write via [Console]::Out so PowerShell
# does not prepend a UTF-8 BOM, which would make the JSON unparseable.
$json = $payload | ConvertTo-Json -Depth 5 -Compress
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
[Console]::Out.Write($json)
