---
name: rules-kubernetes
description: >
  Kubernetes manifest standards: security context, resource limits, probes, image pinning.
  Use when editing k8s manifests (Deployment, StatefulSet, DaemonSet, Service, Ingress,
  CRD, kustomization) or any YAML under k8s/, manifests/, base/, or overlays/.
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
