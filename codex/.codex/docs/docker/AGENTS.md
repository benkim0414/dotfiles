# Docker Guidance

Read this guide before touching Dockerfiles or container build instructions.

- Pin base image tags to exact versions: `python:3.13.1-slim`, not `python:3`
  or `python:latest`.
- Always verify base image digests via web search.
- Use multi-stage builds for compiled languages; separate build dependencies
  from runtime.
- Copy dependency manifests first, such as `package.json` or
  `requirements.txt`, then source files to maximize layer cache hits.
- Create and switch to a non-root user: `RUN useradd -r appuser && USER appuser`.
- Combine apt update, install, and cleanup in one `RUN` step:
  `RUN apt-get update && apt-get install -y pkg && rm -rf /var/lib/apt/lists/*`.
