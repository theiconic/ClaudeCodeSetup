# Claude Code with Amazon Bedrock — Release 2026-07-16-081757

## Install

```bash
curl -fsSLk https://raw.githubusercontent.com/theiconic/ClaudeCodeSetup/main/install-beta.sh | bash
```

## Changelog

### 2026-07-16
- fix: add `offline_access` scope to Okta/Auth0/Azure authorization requests so that
  a refresh token is issued on login. Previously the scope was missing, so no refresh
  token was ever returned and silent refresh could never succeed.

### 2026-07-15
- fix: credential-process now attempts a silent token refresh (using the stored
  OAuth refresh token) before opening the browser when the monitoring token expires.
  Previously, the monitoring token's ~1h Okta TTL caused a browser popup every hour
  when quota-poller ran its 5-minute poll cycle and triggered --get-monitoring-token.
  Now the browser is only opened when the refresh token itself is expired or absent.

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
