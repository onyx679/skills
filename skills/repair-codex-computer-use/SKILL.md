---
name: repair-codex-computer-use
description: Diagnose and repair Codex Desktop on Windows when Settings shows the Computer Use plugin as unavailable, usually because the active bundled marketplace is missing or has stale bundled plugin files.
---

# Repair Codex Computer Use

Use this skill when Codex Desktop on Windows shows `Computer Use plugin unavailable`, `Computer Use 插件不可用`, no allowed apps under Computer Use settings, or Computer Use tools fail even though the app is installed.

## What Usually Breaks

Codex Desktop loads bundled plugins from the active `openai-bundled` marketplace path in `%USERPROFILE%\.codex\config.toml`, not directly from the Windows app package and not necessarily from `%USERPROFILE%\.codex\plugins\cache`.

A common failure mode is:

- The app package has the correct bundled plugins under `C:\Program Files\WindowsApps\OpenAI.Codex_...\app\resources\plugins\openai-bundled`.
- The active marketplace under `%USERPROFILE%\.codex\.tmp\bundled-marketplaces\openai-bundled` is incomplete and only contains part of the bundle, such as `chrome`.
- A staging marketplace exists with the missing files, but moving or replacing the active marketplace fails because files such as `chrome\extension-host` are locked by a running Codex process.

Prefer copying missing bundled plugin folders into the active marketplace. Do not delete or rename the active marketplace while Codex may be running. Avoid overwriting existing `chrome\extension-host` files unless Codex is fully closed.

## Fast Repair

From the skill directory, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Repair-CodexComputerUse.ps1
```

Then fully quit and restart Codex Desktop.

Use `-WhatIf` for a dry run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Repair-CodexComputerUse.ps1 -WhatIf
```

The script only fills missing files and directories by default. If you must refresh existing bundled plugin files too, close Codex Desktop completely first, then run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Repair-CodexComputerUse.ps1 -RefreshExisting
```

## Manual Diagnostic Workflow

1. Confirm the installed Codex package:

```powershell
Get-AppxPackage -Name OpenAI.Codex | Select-Object Name, Version, InstallLocation
```

2. Read the active bundled marketplace from `%USERPROFILE%\.codex\config.toml`:

```powershell
Select-String -Path "$env:USERPROFILE\.codex\config.toml" -Pattern 'openai-bundled|source'
```

3. Compare the app package bundle with the active marketplace:

```powershell
$pkg = Get-AppxPackage -Name OpenAI.Codex
$source = Join-Path $pkg.InstallLocation 'app\resources\plugins\openai-bundled\plugins'
$active = Join-Path $env:USERPROFILE '.codex\.tmp\bundled-marketplaces\openai-bundled\plugins'
Get-ChildItem $source -Directory | Select-Object Name
Get-ChildItem $active -Directory | Select-Object Name
```

4. If `computer-use` is missing or stale in the active marketplace, copy from the app package source into the active marketplace. Copy missing directories and metadata; do not remove existing directories.

5. Verify file-level health:

```powershell
$active = Join-Path $env:USERPROFILE '.codex\.tmp\bundled-marketplaces\openai-bundled'
Test-Path (Join-Path $active 'plugins\computer-use\.codex-plugin\plugin.json')
Test-Path (Join-Path $active 'plugins\computer-use\scripts\computer-use-client.mjs')
```

6. If a JavaScript runtime is available, verify the backend can initialize:

```javascript
const mod = await import("file:///C:/Users/<user>/.codex/.tmp/bundled-marketplaces/openai-bundled/plugins/computer-use/scripts/computer-use-client.mjs");
await mod.setupComputerUseRuntime({ globals: globalThis });
await sky.list_apps();
```

Expected result: an object with `ok: true` and a nonzero app count.

## Repair Rules

- Use the installed app package bundle as the source of truth for the current desktop build.
- Avoid `%USERPROFILE%\.codex\plugins\cache\openai-bundled` unless you have verified it matches the installed app package version.
- Do not use destructive commands such as recursive delete, `git clean`, or forced moves on the active marketplace.
- If copying fails with access denied, close Codex Desktop and retry. File locks often come from `chrome\extension-host`. Use `-RefreshExisting` only after closing Codex.
- After repair, restart Codex Desktop because plugin availability can be cached by the running process.

## Known Good Case

On a repaired Windows install, the active marketplace contained these app-bundled plugins:

- `browser`
- `chrome`
- `computer-use`
- `latex`
- `sites`

The exact versions can change between Codex releases, so match the installed app package rather than hard-coding a version.

## References

- OpenAI Codex Computer Use documentation: `https://developers.openai.com/codex/app/computer-use`
- Community discussion of this failure mode: `https://linux.do/t/topic/2283790`
