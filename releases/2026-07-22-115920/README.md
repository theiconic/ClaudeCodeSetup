# Release 2026-07-16-160359

## Install

```bash
curl -fsSLk https://raw.githubusercontent.com/theiconic/ClaudeCodeSetup/main/install-beta.sh | bash
```

## Changelog

### 2026-07-16
- fix: --include-cost now uses CloudWatch GetMetricData (Sum) instead of PromQL
  increase() — fixes ~40% undercount caused by UTC vs local timezone midnight mismatch
  and PromQL interpolation gaps. Cost now matches ccusage within ~8%.
- feat: statusline shows real cost (today + month) refreshed every 15 min.
- feat: quota-poller --statusline --include-cost flag for real cost from CloudWatch.
- fix: add offline_access scope — eliminates hourly browser re-auth popups.
- fix: silent monitoring token refresh via stored refresh token.

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
