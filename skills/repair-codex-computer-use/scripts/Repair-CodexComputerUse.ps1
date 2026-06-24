[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$CodexHome = (Join-Path $env:USERPROFILE ".codex"),
    [string]$MarketplaceName = "openai-bundled",
    [switch]$RefreshExisting
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Convert-ExtendedPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ($Path.StartsWith("\\?\")) {
        return $Path.Substring(4)
    }

    return $Path
}

function Get-ConfiguredMarketplacePath {
    param(
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$FallbackPath
    )

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        return $FallbackPath
    }

    $content = Get-Content -LiteralPath $ConfigPath -Raw
    $sectionPattern = "(?ms)^\[marketplaces\.$([regex]::Escape($Name))\]\s*(?<body>.*?)(?=^\[|\z)"
    $section = [regex]::Match($content, $sectionPattern)
    if (-not $section.Success) {
        return $FallbackPath
    }

    $source = [regex]::Match($section.Groups["body"].Value, '(?m)^\s*source\s*=\s*[''"](?<path>.+?)[''"]\s*$')
    if (-not $source.Success) {
        return $FallbackPath
    }

    return Convert-ExtendedPath $source.Groups["path"].Value
}

function Copy-DirectoryContents {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [switch]$Refresh
    )

    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    }

    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        $target = Join-Path $Destination $item.Name
        $targetExists = Test-Path -LiteralPath $target

        if ($item.PSIsContainer -and $targetExists -and -not $Refresh) {
            Copy-DirectoryContents -Source $item.FullName -Destination $target
            continue
        }

        if ($targetExists -and -not $Refresh) {
            continue
        }

        if ($PSCmdlet.ShouldProcess($target, "Copy from $($item.FullName)")) {
            Copy-Item -LiteralPath $item.FullName -Destination $target -Recurse -Force
        }
    }
}

$package = Get-AppxPackage -Name OpenAI.Codex | Sort-Object Version -Descending | Select-Object -First 1
if (-not $package) {
    throw "OpenAI.Codex AppX package was not found."
}

$sourceMarketplace = Join-Path $package.InstallLocation "app\resources\plugins\$MarketplaceName"
$sourcePlugins = Join-Path $sourceMarketplace "plugins"
if (-not (Test-Path -LiteralPath $sourcePlugins)) {
    throw "Bundled plugin source was not found: $sourcePlugins"
}

$configPath = Join-Path $CodexHome "config.toml"
$fallbackMarketplace = Join-Path $CodexHome ".tmp\bundled-marketplaces\$MarketplaceName"
$activeMarketplace = Get-ConfiguredMarketplacePath -ConfigPath $configPath -Name $MarketplaceName -FallbackPath $fallbackMarketplace
$activePlugins = Join-Path $activeMarketplace "plugins"

Write-Host "Codex package: $($package.Name) $($package.Version)"
Write-Host "App bundle:    $sourceMarketplace"
Write-Host "Active bundle: $activeMarketplace"

if ($PSCmdlet.ShouldProcess($activePlugins, "Ensure active plugin directory exists")) {
    New-Item -ItemType Directory -Force -Path $activePlugins | Out-Null
}

$sourcePluginDirs = Get-ChildItem -LiteralPath $sourcePlugins -Directory -Force
foreach ($plugin in $sourcePluginDirs) {
    $destination = Join-Path $activePlugins $plugin.Name
    if (-not (Test-Path -LiteralPath $destination)) {
        if ($PSCmdlet.ShouldProcess($destination, "Copy missing plugin directory")) {
            Copy-Item -LiteralPath $plugin.FullName -Destination $destination -Recurse -Force
        }
        continue
    }

    Copy-DirectoryContents -Source $plugin.FullName -Destination $destination -Refresh:$RefreshExisting
}

$required = @(
    "plugins\computer-use\.codex-plugin\plugin.json",
    "plugins\computer-use\scripts\computer-use-client.mjs"
)

$missing = @()
foreach ($relativePath in $required) {
    $path = Join-Path $activeMarketplace $relativePath
    if (-not (Test-Path -LiteralPath $path)) {
        $missing += $path
    }
}

if ($missing.Count -gt 0) {
    if ($WhatIfPreference) {
        Write-Warning "Dry run did not copy files. These required files are currently missing:`n$($missing -join ([Environment]::NewLine))"
    } else {
        throw "Repair completed but required files are still missing:`n$($missing -join ([Environment]::NewLine))"
    }
}

Write-Host ""
Write-Host "Active bundled plugins:"
Get-ChildItem -LiteralPath $activePlugins -Directory -Force |
    Sort-Object Name |
    ForEach-Object {
        $pluginJson = Join-Path $_.FullName ".codex-plugin\plugin.json"
        $version = ""
        if (Test-Path -LiteralPath $pluginJson) {
            try {
                $version = ((Get-Content -LiteralPath $pluginJson -Raw) | ConvertFrom-Json).version
            } catch {
                $version = "unreadable-version"
            }
        }
        "{0}`t{1}" -f $_.Name, $version
    } |
    Write-Host

Write-Host ""
Write-Host "Computer Use files are present. Fully quit and restart Codex Desktop before checking Settings again."
