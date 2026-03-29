# DevOps

## Kubernetes Manifests

Every Deployment/StatefulSet/DaemonSet must include:

### Security Context (Restricted profile)
- Pod-level: `runAsNonRoot: true`, `seccompProfile.type: RuntimeDefault`
- Container-level: `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, `capabilities.drop: ["ALL"]`
- Never use hostNetwork, hostPID, hostIPC, or hostPath volumes
- Set `automountServiceAccountToken: false` unless the pod needs Kubernetes API access

### Resource Management
- Set both `resources.requests` and `resources.limits` (cpu, memory) on every container
- Add `livenessProbe` and `readinessProbe` on every container
- Include a `PodDisruptionBudget` for production workloads

### Image and Versioning
- Pin image tags to exact versions -- never use `:latest` or bare major/minor tags
- Use current stable apiVersions: `apps/v1`, `networking.k8s.io/v1`, `policy/v1`
- Label consistently: `app.kubernetes.io/name`, `app.kubernetes.io/version`, `app.kubernetes.io/component`

## Dockerfiles

- Pin base image tags to exact versions: `python:3.13.1-slim` not `python:3` or `python:latest`
- Use multi-stage builds for compiled languages -- separate build deps from runtime
- Copy dependency manifests first (package.json, requirements.txt), then source -- maximizes layer cache hits
- Create and switch to non-root user: `RUN useradd -r appuser && USER appuser`
- Combine apt-get update and install in one RUN with cleanup: `RUN apt-get update && apt-get install -y pkg && rm -rf /var/lib/apt/lists/*`

## GitHub Actions

- Pin actions by full commit SHA, not tag: `actions/checkout@<sha>` not `@v4`
- Always declare a `permissions:` block at job level with least privilege -- omitting defaults to broad access
- Use OIDC (`id-token: write`) for cloud auth instead of long-lived credential secrets
- Guard comment-triggered workflows against self-triggers: `if: github.actor != 'claude[bot]'`

## Terraform / OpenTofu

- Always show `terraform plan` output before any apply -- never combine or skip the plan step
- Pin provider versions in required_providers: `version = "~> 5.0"` not `>= 5.0` or omitted
- Use remote backend with state locking (S3 + DynamoDB, or equivalent) -- never local state in shared environments
- Add `lifecycle { prevent_destroy = true }` on stateful resources (databases, storage, networking)
- Mark sensitive outputs with `sensitive = true` to prevent leaks in logs and CI output

## Helm Charts

- Validate before committing: `helm lint --strict` and `helm template . --validate`
- Provide complete defaults in values.yaml for all templated values
- Quote string interpolations in templates: `"{{ .Values.image.tag }}"` not bare `{{ .Values.image.tag }}`

## Shell Scripts

- ShellCheck must pass with no warnings before committing
