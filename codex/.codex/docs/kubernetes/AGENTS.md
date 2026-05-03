# Kubernetes Guidance

Read this guide before touching Kubernetes manifests.

Every Deployment, StatefulSet, and DaemonSet must include the following.

Security context:

- Pod-level: `runAsNonRoot: true`, `seccompProfile.type: RuntimeDefault`.
- Container-level: `allowPrivilegeEscalation: false`,
  `readOnlyRootFilesystem: true`, `capabilities.drop: ["ALL"]`.
- Never use `hostNetwork`, `hostPID`, `hostIPC`, or `hostPath` volumes.
- Set `automountServiceAccountToken: false` unless the pod needs Kubernetes API
  access.

Resource management:

- Set both `resources.requests` and `resources.limits` for CPU and memory on
  every container.
- Add `livenessProbe` and `readinessProbe` on every container.
- Include a `PodDisruptionBudget` for production workloads.

Image and versioning:

- Pin image tags to exact versions. Never use `:latest` or bare major/minor
  tags.
- Always verify image digests via web search.
- Use current stable apiVersions: `apps/v1`, `networking.k8s.io/v1`,
  `policy/v1`.
- Label consistently: `app.kubernetes.io/name`,
  `app.kubernetes.io/version`, `app.kubernetes.io/component`.
