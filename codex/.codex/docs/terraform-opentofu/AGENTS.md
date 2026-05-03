# Terraform / OpenTofu Guidance

Read this guide before touching Terraform or OpenTofu configuration.

- Always show `terraform plan` output before any apply. Never combine or skip
  the plan step.
- Pin provider versions in `required_providers`: `version = "~> 5.0"`, not
  `>= 5.0` or omitted.
- Use remote backend with state locking, such as S3 plus DynamoDB or equivalent.
  Never use local state in shared environments.
- Add `lifecycle { prevent_destroy = true }` on stateful resources, such as
  databases, storage, and networking.
- Mark sensitive outputs with `sensitive = true` to prevent leaks in logs and
  CI output.
