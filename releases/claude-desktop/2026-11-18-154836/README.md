# Claude Desktop on Amazon Bedrock: release 2026-11-18-154836

> **Supersedes `2026-11-18-121641`**, which shipped without usage telemetry (OTLP) and before the Windows install/uninstall recovery fixes from review. Do not deploy the older folder.

Built from `3.0.0-beta.3-92-g5d33970-dirty` (the `-dirty` suffix means uncommitted changes were present). Organization plugin
`theiconic` v1.1.1. Everything is UNSIGNED unless it was built with `--sign`.

| Path | What it is |
|---|---|
| `macos/ClaudeCodeSetup-2026-11-18-154836.pkg` | root-owned install of the credential helper under `/usr/local/libexec/ccwb` and of the `theiconic` plugin under `/Library/Application Support/Claude/org-plugins/` |
| `macos/ClaudeCowork-2026-11-18-154836.mobileconfig` | Claude Desktop policy (Bedrock, models, Developer Mode off). Deploy as a Configuration Profile; macOS blocks silent installs from a package |
| `windows/install-cowork.ps1` | Intune platform script (SYSTEM, 64-bit PowerShell). Downloads the zip below, refuses any bytes whose SHA256 differs, installs helper + plugin, writes the HKLM policy |
| `windows/ClaudeCowork-2026-11-18-154836-windows.zip` | helper + config + plugin, pinned by hash inside the install script |
| `windows/uninstall-cowork.ps1` | removes exactly what the installer recorded (policy values, plugin folders it installed, helper) |
| `windows/ClaudeCowork-2026-11-18-154836.reg` | the same HKLM policy for Group Policy / reference |
| `org-plugins/theiconic/` | the plugin as plain files (also inside both packages) |
| `SHA256SUMS` | checksums of every file here: `shasum -a 256 -c SHA256SUMS` |

## What users get
Connectors **Datadog**, **Atlassian** and **n8n** (n8n needs the corporate network or VPN) via the `theiconic` plugin.
Each person signs in with their own account; the plugin and these packages contain no keys or secrets.
Usage telemetry (OTLP) goes to: `http://otel-collector-alb-1417639215.ap-southeast-2.elb.amazonaws.com`.
The plugin shows under Customize, Plugins, Organization. Developer Mode is off, which hides Claude Desktop's
Developer menu and its config viewer. Google Workspace connectors are not part of this release.

## Status (read before deploying)
- **macOS package:** integration-tested on the build machine (package expanded without installing; preinstall and
  postinstall run in a sandbox, including upgrade, withdrawal and refusal cases). Not yet deployed to a managed fleet.
- **Windows scripts:** generated from reviewed templates and covered by rendering tests, but **never executed on Windows**.
  Run install and uninstall once on a test device before any fleet rollout.
- Packages and scripts are **unsigned**.

## Install
- **macOS (Jamf):** deploy the .pkg, then the .mobileconfig as a Configuration Profile. Users quit and reopen Claude.
- **Windows (Intune):** upload `install-cowork.ps1` as a platform script. Run as SYSTEM, in the 64-bit host.

## Uninstall
- **Windows:** run `windows/uninstall-cowork.ps1` the same way.
- **macOS:** there is no uninstaller yet. Remove the profile in the MDM, then as root:
  `rm -rf /usr/local/libexec/ccwb "/Library/Application Support/Claude/org-plugins/theiconic"`

Updating the plugin: bump `version.json` and `plugin.json` together, rebuild, redeploy. Desktop re-syncs on launch.
