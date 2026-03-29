# Observability

- Structured logs (JSON preferred); always include relevant context (resource, namespace, request ID)
- Metrics: expose a `/metrics` endpoint; use consistent labels for cross-service dashboards
- Alert on symptoms (error rate, latency, SLO burn), not causes (high CPU, pod restarted)
- Validate deployments by inspecting metrics and logs, not just rollout status
- Every alert rule must have a corresponding runbook or investigation guide
