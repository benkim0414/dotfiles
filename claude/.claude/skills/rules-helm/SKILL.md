---
name: rules-helm
description: >
  Helm chart conventions: linting, template validation, version pinning.
  Use when editing Chart.yaml, Chart.lock, values.yaml, values-*.yaml,
  templates/, helmfile*.yaml, or charts/.
---

# Helm Charts

- Validate before committing: `helm lint --strict` and `helm template . --validate`
- Always verify chart versions via fetch -- never rely on training data
- Provide complete defaults in values.yaml for all templated values
- Quote string interpolations in templates: `"{{ .Values.image.tag }}"` not bare `{{ .Values.image.tag }}`
