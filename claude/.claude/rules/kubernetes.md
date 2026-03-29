# Kubernetes and Containers

- Always set resource requests and limits on every container
- Use readiness and liveness probes on every workload
- Pin image tags -- never use `:latest` in committed manifests
- Label every resource consistently: app, component, version
- Use namespaces for isolation; avoid the default namespace for workloads
- Run containers as non-root; drop unnecessary Linux capabilities
- Prefer minimal base images (distroless, alpine) to reduce attack surface
