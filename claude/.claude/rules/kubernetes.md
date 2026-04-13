---
description: Kubernetes manifest conventions -- security context, resources, probes, image pinning
paths:
  - "k8s/**"
  - "**/deploy/**/*.yaml"
  - "**/manifests/**"
  - "**/base/**/*.yaml"
  - "**/overlays/**/*.yaml"
---

# Kubernetes Manifests

Every Deployment/StatefulSet/DaemonSet must include:

## Security Context (Restricted profile)
- Pod-level: `runAsNonRoot: true`, `seccompProfile.type: RuntimeDefault`
- Container-level: `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, `capabilities.drop: ["ALL"]`
- Never use hostNetwork, hostPID, hostIPC, or hostPath volumes
- Set `automountServiceAccountToken: false` unless the pod needs Kubernetes API access

## Resource Management
- Set both `resources.requests` and `resources.limits` (cpu, memory) on every container
- Add `livenessProbe` and `readinessProbe` on every container
- Include a `PodDisruptionBudget` for production workloads

## Image and Versioning
- Pin image tags to exact versions -- never use `:latest` or bare major/minor tags
- Always verify image digests via fetch -- never rely on training data
- Use current stable apiVersions: `apps/v1`, `networking.k8s.io/v1`, `policy/v1`
- Label consistently: `app.kubernetes.io/name`, `app.kubernetes.io/version`, `app.kubernetes.io/component`
