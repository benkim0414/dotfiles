# Helm Guidance

Read this guide before touching Helm charts or templates.

- Validate before committing: `helm lint --strict` and
  `helm template . --validate`.
- Always verify chart versions via web search.
- Provide complete defaults in `values.yaml` for all templated values.
- Quote string interpolations in templates: `"{{ .Values.image.tag }}"`, not
  bare `{{ .Values.image.tag }}`.
