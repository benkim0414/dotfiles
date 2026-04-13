---
description: Terraform/OpenTofu conventions -- plan before apply, state locking, provider pinning
paths:
  - "**/*.tf"
  - "**/*.tfvars"
  - "**/terragrunt.hcl"
  - "**/.terraform.lock.hcl"
---

# Terraform / OpenTofu

- Always show `terraform plan` output before any apply -- never combine or skip the plan step
- Pin provider versions in required_providers: `version = "~> 5.0"` not `>= 5.0` or omitted
- Use remote backend with state locking (S3 + DynamoDB, or equivalent) -- never local state in shared environments
- Add `lifecycle { prevent_destroy = true }` on stateful resources (databases, storage, networking)
- Mark sensitive outputs with `sensitive = true` to prevent leaks in logs and CI output
