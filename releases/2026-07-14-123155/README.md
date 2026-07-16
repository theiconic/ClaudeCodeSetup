# Claude Code with Amazon Bedrock — Release 2026-07-14-123155

## Install

```bash
curl -fsSLk https://raw.githubusercontent.com/theiconic/ClaudeCodeSetup/main/install-beta.sh | bash
```

## Changelog

### 2026-07-14
- feat: quota-poller --models prints per-model token usage (today + month-to-date)
  as a table, or as JSON with --models --statusline. Queries CloudWatch's PromQL
  API live and requires local AWS credentials with metrics read (not the federated
  Bedrock role).
- feat: --models totals are scaled to the authoritative daily/monthly figures from
  the local quota cache, so the Total row matches --show-usage; the per-model split
  comes from live usage proportions (DynamoDB stores no per-model breakdown).
- fix: month-to-date is queried in <=24h chunks — CloudWatch caps the PromQL
  increase() range selector at 24h and the overall query length at 8 days.

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
