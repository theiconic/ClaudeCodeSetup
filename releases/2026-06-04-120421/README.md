# Claude Code with Amazon Bedrock — Release 2026-06-04-120421

## Install

```bash
curl -fsSLk https://raw.githubusercontent.com/theiconic/ClaudeCodeSetup/main/install-beta.sh | bash
```

## Changelog

### 2026-06-04
- feat: quota alert message now surfaced in the statusline as a bold yellow/red third
  line when daily or monthly quota is exceeded — no more silent failures.
- feat: alert_level and alert_message persisted to quota cache so statusline and
  quota-poller --show-usage both reflect the current warning/blocked state.
- fix: monthly_alert reason added to Lambda — previously monthly exceeded in alert
  mode was a silent pass and the client never received a warning.
- fix: quota-poller also persists alert state when it polls, keeping statusline
  up-to-date between credential-process calls.
- fix: install.sh and ccwb-install.ps1 no longer require or auto-install AWS CLI.
- fix: curl|bash installs now auto-confirm settings and statusline overwrite.

---

## Binaries

| File | Platform |
|------|----------|
| `credential-process-macos-arm64` | macOS Apple Silicon |
| `credential-process-macos-intel` | macOS Intel |
| `credential-process-windows.exe` | Windows |
| `quota-poller-macos-arm64` | macOS Apple Silicon |
| `quota-poller-macos-intel` | macOS Intel |
| `quota-poller-windows.exe` | Windows |
| `otel-helper-macos-arm64` | macOS Apple Silicon |
| `otel-helper-macos-intel` | macOS Intel |
| `otel-helper-windows.exe` | Windows |
