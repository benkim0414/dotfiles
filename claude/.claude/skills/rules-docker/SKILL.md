---
name: rules-docker
description: >
  Docker best practices for image pinning, multi-stage builds, and non-root users.
  Use when editing Dockerfile*, docker-compose*.yml, docker-compose*.yaml,
  or .dockerignore files.
---

# Dockerfiles

- Pin base image tags to exact versions: `python:3.13.1-slim` not `python:3` or `python:latest`
- Always verify base image digests via fetch -- never rely on training data
- Use multi-stage builds for compiled languages -- separate build deps from runtime
- Copy dependency manifests first (package.json, requirements.txt), then source -- maximizes layer cache hits
- Create and switch to non-root user: `RUN useradd -r appuser && USER appuser`
- Combine apt-get update and install in one RUN with cleanup: `RUN apt-get update && apt-get install -y pkg && rm -rf /var/lib/apt/lists/*`
