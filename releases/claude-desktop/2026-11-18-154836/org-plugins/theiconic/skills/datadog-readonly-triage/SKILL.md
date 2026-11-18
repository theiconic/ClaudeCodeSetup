---
name: datadog-readonly-triage
description: Use when asked to triage a service, alert or incident with Datadog. Read-only investigation using the Datadog connector; never changes monitors, dashboards or settings.
---

# Datadog read-only triage

Ground rules
- Use only **read** tools of the Datadog connector. If a tool would create, edit, mute or delete anything, stop and ask the user.
- State the service, environment and time range you are using before querying. If any is missing, ask.
- Quote evidence (log lines, metric values, monitor names) and say when data is missing instead of guessing.

Steps
1. Check which monitors for the service are alerting right now.
2. Pull recent error logs for the service and group them by pattern.
3. Compare the key metrics (error rate, latency, saturation) with the previous period.
4. Summarise: what is wrong, since when, likely cause, and the evidence for each claim.
5. List recommended next steps for a human to approve. Do not run remediation.
