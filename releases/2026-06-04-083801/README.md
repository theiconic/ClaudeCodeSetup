# Claude Code with Amazon Bedrock — Release 2026-06-04-083801

## Install

```bash
curl -fsSLk https://raw.githubusercontent.com/theiconic/ClaudeCodeSetup/main/install-beta.sh | bash
```

## Changelog

### 2026-06-02
- feat: quota-poller --show-usage prints cached daily/monthly quota to the terminal
  with a colour progress bar and your email address.
- feat: quota-poller --statusline outputs quota as JSON for status displays.
- fix: --statusline unit scaling was wrong when used < limit crossed M/k boundary.

### 2026-05-27
- fix: OAuth callback no longer falls back to a random port when port 8400 is busy.
- fix: daily quota enforcement now works.
- feat: quota-poller auto-refreshes expired monitoring tokens via credential-process.
- feat: --version now includes the build timestamp.
- feat: --changelog flag shows what changed in the installed build.

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
