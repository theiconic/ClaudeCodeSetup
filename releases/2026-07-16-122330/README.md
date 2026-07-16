# Release 2026-07-16-122330

## Install

```bash
curl -fsSLk https://raw.githubusercontent.com/theiconic/ClaudeCodeSetup/main/install-beta.sh | bash
```

## Changelog

### 2026-07-16
- feat: statusline now shows real cost (`💰 $34.80/day  $260.56/mo`) sourced from
  CloudWatch `claude_code.cost.usage`, refreshed every 15 minutes in the background.
  Cost is ~92% accurate vs AWS Cost Explorer billing.
- feat: quota-poller `--statusline --include-cost` adds `cost.today_usd` and
  `cost.month_usd` fields to the JSON output. Queries CloudWatch for the current
  user's `claude_code.cost.usage` metric (today + month-to-date).
- fix: add `offline_access` scope to Okta/Auth0/Azure authorization requests so that
  a refresh token is issued on login — eliminates hourly browser popups.
- fix: credential-process now attempts a silent token refresh before opening the
  browser when the monitoring token expires.

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
