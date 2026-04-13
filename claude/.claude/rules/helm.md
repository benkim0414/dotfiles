---
description: Helm chart conventions -- linting, template validation, version pinning
paths:
  - "**/Chart.yaml"
  - "**/Chart.lock"
  - "**/values*.yaml"
  - "**/templates/**"
  - "**/helmfile*.yaml"
  - "**/charts/**"
globs: true
---

# Helm Charts

- Validate before committing: `helm lint --strict` and `helm template . --validate`
- Always verify chart versions via fetch -- never rely on training data
- Provide complete defaults in values.yaml for all templated values
- Quote string interpolations in templates: `"{{ .Values.image.tag }}"` not bare `{{ .Values.image.tag }}`
