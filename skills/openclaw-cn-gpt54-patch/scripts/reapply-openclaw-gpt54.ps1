param(
    [string]$Distro,
    [string]$UserName
)

$ErrorActionPreference = "Stop"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Get-WslDistros {
    $lines = & wsl -l -q 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to list WSL distros."
    }
    return @($lines | ForEach-Object { ("$_" -replace "`0", "").Trim() } | Where-Object { $_ })
}

function Invoke-WslText {
    param(
        [string]$TargetDistro,
        [string]$Command,
        [switch]$AsRoot
    )

    $args = @()
    if ($AsRoot) {
        $args += "-u"
        $args += "root"
    }
    $args += "-d"
    $args += $TargetDistro
    $args += "--"
    $args += "bash"
    $args += "-lc"
    $args += $Command

    $output = & wsl @args
    if ($LASTEXITCODE -ne 0) {
        throw "WSL command failed in distro '$TargetDistro': $Command"
    }
    return ($output | Out-String).Trim()
}

function Try-WslText {
    param(
        [string]$TargetDistro,
        [string]$Command
    )

    try {
        return Invoke-WslText -TargetDistro $TargetDistro -Command $Command
    }
    catch {
        return ""
    }
}

function Resolve-Distro {
    param([string]$RequestedDistro)

    if ($RequestedDistro) {
        return $RequestedDistro
    }

    $candidates = Get-WslDistros
    foreach ($candidate in $candidates) {
        $hasConfig = Try-WslText -TargetDistro $candidate -Command "find /home -path '*/.openclaw/openclaw.json' -type f 2>/dev/null | head -n 1"
        $hasInstall = Try-WslText -TargetDistro $candidate -Command "find /home -path '*/lib/node_modules/openclaw-cn/dist' -type d 2>/dev/null | head -n 1"
        if ($hasConfig -and $hasInstall) {
            return $candidate
        }
    }

    if ($candidates.Count -eq 1) {
        return $candidates[0]
    }

    throw "Could not auto-detect the target WSL distro. Re-run with -Distro <name>."
}

function To-UncPath {
    param(
        [string]$TargetDistro,
        [string]$LinuxPath
    )

    if (-not $LinuxPath.StartsWith("/")) {
        throw "Expected Linux path, got: $LinuxPath"
    }
    return "\\wsl.localhost\$TargetDistro" + ($LinuxPath -replace "/", "\")
}

function Replace-Exact {
    param(
        [string]$Path,
        [string]$From,
        [string]$To
    )

    $text = Get-Content -Raw $Path
    if ($text.Contains($To)) {
        return
    }
    if (-not $text.Contains($From)) {
        throw "Pattern not found in $Path"
    }
    $text = $text.Replace($From, $To)
    [System.IO.File]::WriteAllText($Path, $text, $Utf8NoBom)
}

$Distro = Resolve-Distro -RequestedDistro $Distro

if (-not $UserName) {
    $configProbe = Invoke-WslText -TargetDistro $Distro -Command "find /home -path '*/.openclaw/openclaw.json' -type f 2>/dev/null | head -n 1"
    if (-not $configProbe) {
        throw "Could not find ~/.openclaw/openclaw.json in distro '$Distro'."
    }
    $UserName = ($configProbe -split "/")[2]
}

$distPath = Invoke-WslText -TargetDistro $Distro -Command "find /home/$UserName /usr/local /opt -path '*/lib/node_modules/openclaw-cn/dist' -type d 2>/dev/null | sort -V | tail -n 1"
if (-not $distPath) {
    throw "Could not locate openclaw-cn dist directory in distro '$Distro'."
}

$distUnc = To-UncPath -TargetDistro $Distro -LinuxPath $distPath
$configPath = "\\wsl.localhost\$Distro\home\$UserName\.openclaw\openclaw.json"

Replace-Exact `
    -Path (Join-Path $distUnc "commands\openai-codex-model-default.js") `
    -From 'export const OPENAI_CODEX_DEFAULT_MODEL = "openai-codex/gpt-5.2";' `
    -To 'export const OPENAI_CODEX_DEFAULT_MODEL = "openai-codex/gpt-5.4";'

Replace-Exact `
    -Path (Join-Path $distUnc "agents\live-model-filter.js") `
    -From "const CODEX_MODELS = [`n    `"gpt-5.2`"," `
    -To "const CODEX_MODELS = [`n    `"gpt-5.4`",`n    `"gpt-5.2`","

Replace-Exact `
    -Path (Join-Path $distUnc "auto-reply\thinking.js") `
    -From "export const XHIGH_MODEL_REFS = [`n    `"openai/gpt-5.2`"," `
    -To "export const XHIGH_MODEL_REFS = [`n    `"openai/gpt-5.2`",`n    `"openai-codex/gpt-5.4`","

Replace-Exact `
    -Path (Join-Path $distUnc "agents\model-catalog.js") `
    -From 'const OPENAI_CODEX_GPT53_MODEL_ID = "gpt-5.3-codex";
const OPENAI_CODEX_GPT53_SPARK_MODEL_ID = "gpt-5.3-codex-spark";' `
    -To 'const OPENAI_CODEX_GPT54_MODEL_ID = "gpt-5.4";
const OPENAI_CODEX_GPT53_MODEL_ID = "gpt-5.3-codex";
const OPENAI_CODEX_GPT53_SPARK_MODEL_ID = "gpt-5.3-codex-spark";'

Replace-Exact `
    -Path (Join-Path $distUnc "agents\model-catalog.js") `
    -From '    const hasSpark = models.some((entry) => entry.provider === CODEX_PROVIDER &&
        entry.id.toLowerCase() === OPENAI_CODEX_GPT53_SPARK_MODEL_ID);' `
    -To '    const has54 = models.some((entry) => entry.provider === CODEX_PROVIDER &&
        entry.id.toLowerCase() === OPENAI_CODEX_GPT54_MODEL_ID);
    if (!has54) {
        const template54 = models.find((entry) => entry.provider === CODEX_PROVIDER && (entry.id.toLowerCase() === "gpt-5.2-codex" || entry.id.toLowerCase() === OPENAI_CODEX_GPT53_MODEL_ID));
        if (template54) {
            models.push({
                ...template54,
                id: OPENAI_CODEX_GPT54_MODEL_ID,
                name: OPENAI_CODEX_GPT54_MODEL_ID,
            });
        }
    }
    const hasSpark = models.some((entry) => entry.provider === CODEX_PROVIDER &&
        entry.id.toLowerCase() === OPENAI_CODEX_GPT53_SPARK_MODEL_ID);'

Replace-Exact `
    -Path (Join-Path $distUnc "agents\pi-embedded-runner\model.js") `
    -From 'const OPENAI_CODEX_GPT_53_MODEL_ID = "gpt-5.3-codex";
const OPENAI_CODEX_GPT_53_SPARK_MODEL_ID = "gpt-5.3-codex-spark";
const OPENAI_CODEX_TEMPLATE_MODEL_IDS = ["gpt-5.2-codex"];' `
    -To 'const OPENAI_CODEX_GPT_54_MODEL_ID = "gpt-5.4";
const OPENAI_CODEX_GPT_53_MODEL_ID = "gpt-5.3-codex";
const OPENAI_CODEX_GPT_53_SPARK_MODEL_ID = "gpt-5.3-codex-spark";
const OPENAI_CODEX_TEMPLATE_MODEL_IDS = ["gpt-5.2-codex"];'

Replace-Exact `
    -Path (Join-Path $distUnc "agents\pi-embedded-runner\model.js") `
    -From '    const isGpt53 = lower === OPENAI_CODEX_GPT_53_MODEL_ID;
    const isSpark = lower === OPENAI_CODEX_GPT_53_SPARK_MODEL_ID;
    if (!isGpt53 && !isSpark) {' `
    -To '    const isGpt54 = lower === OPENAI_CODEX_GPT_54_MODEL_ID;
    const isGpt53 = lower === OPENAI_CODEX_GPT_53_MODEL_ID;
    const isSpark = lower === OPENAI_CODEX_GPT_53_SPARK_MODEL_ID;
    if (!isGpt54 && !isGpt53 && !isSpark) {'

Replace-Exact `
    -Path (Join-Path $distUnc "agents\pi-embedded-runner\model.js") `
    -From '            // Spark is a low-latency variant; keep api/baseUrl from template.
            ...(isSpark ? { reasoning: true } : {}),' `
    -To '            // Keep api/baseUrl from template for forward-compatible Codex model ids.
            ...((isSpark || isGpt54) ? { reasoning: true } : {}),'

$cfg = Get-Content -Raw $configPath
$cfg = [regex]::Replace($cfg, '("primary"\s*:\s*")openai-codex/[^"]+(")', '$1openai-codex/gpt-5.4$2', 1)
[System.IO.File]::WriteAllText($configPath, $cfg, $Utf8NoBom)

Invoke-WslText -TargetDistro $Distro -AsRoot -Command "systemctl restart openclaw-gateway.service"

$status = Invoke-WslText -TargetDistro $Distro -AsRoot -Command "systemctl is-active openclaw-gateway.service"
$http = ""
for ($i = 0; $i -lt 20 -and $http -ne "200"; $i++) {
    try {
        $http = Invoke-WslText -TargetDistro $Distro -Command 'curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:18789/'
    }
    catch {
        Start-Sleep -Seconds 1
        continue
    }
    if ($http -ne "200") {
        Start-Sleep -Seconds 1
    }
}
if ($http -ne "200") {
    throw "Gateway HTTP check failed after restart."
}
$log = Invoke-WslText -TargetDistro $Distro -Command "journalctl -u openclaw-gateway.service -n 20 --no-pager"

Write-Output "distro=$Distro"
Write-Output "user=$UserName"
Write-Output "dist=$distPath"
Write-Output "service=$status"
Write-Output "http=$http"
Write-Output $log
