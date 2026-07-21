---
title: "Harden local Atuin AI with loopback-only Podman"
date: 2026-07-21
category: tooling-decisions
module: local-terminal-ai
problem_type: tooling_decision
component: tooling
severity: medium
applies_when:
  - "Adding a local AI helper whose HTTP server has no authentication"
  - "Running a local service in Podman on Fedora with SELinux enabled"
  - "Preserving a strict local-only AI boundary in dotfiles"
tags: [atuin, ollama, podman, local-ai, selinux, systemd]
---

# Harden local Atuin AI with loopback-only Podman

## Context

The Atuin local AI setup needed to satisfy a strict local-only requirement while still running the Atuin AI backend as a user service. The first service shape used host networking, which was too broad for an unauthenticated local AI HTTP service. Fedora also makes SELinux labeling relevant for Podman bind mounts, so a plain read-only mount can still fail at runtime.

The hardened configuration keeps the user-facing Atuin endpoint local in the client config: `atuin/.config/atuin/config.toml:21` sets `endpoint = "http://localhost:8080"`, and `atuin/.config/atuin/config.toml:22` selects the OSS endpoint protocol. The client also keeps high-risk capabilities disabled: `yolo = false` at `atuin/.config/atuin/config.toml:24`, history output disabled at `atuin/.config/atuin/config.toml:28`, file tools disabled at `atuin/.config/atuin/config.toml:29`, and command execution disabled at `atuin/.config/atuin/config.toml:30`.

## Guidance

For unauthenticated local AI helper services, publish only to loopback and keep container-to-host model access explicit.

Use the Atuin client as the only interactive entry point:

```toml
[ai]
endpoint = "http://localhost:8080"
endpoint_protocol = "oss"
model = "qwen3-coder-30b"
yolo = false
```

Use the Atuin AI backend config to point the container at host Ollama through Podman's host alias:

```toml
port = 8080
endpoint = "http://host.containers.internal:11434/v1"
api_key = "ollama"
default_model = "qwen3-coder-30b"
```

The current backend config follows that shape in `atuin/.config/atuin-ai/config.toml:1-4`, with model aliases for `qwen3-coder:30b` and `gpt-oss:20b` in `atuin/.config/atuin-ai/config.toml:9-19`.

Run the service with explicit loopback publishing instead of host networking:

```ini
ExecStart=/usr/sbin/podman run --rm --name atuin-ai-server -p 127.0.0.1:8080:8080 -v %h/.config/atuin-ai/config.toml:/etc/atuin-ai/config.toml:ro,Z ghcr.io/atuinsh/atuin-ai-server:latest
```

The tracked user service uses that exact pattern in `atuin/.config/systemd/user/atuin-ai.service:9`. The `-p 127.0.0.1:8080:8080` binding keeps the unauthenticated backend off non-loopback interfaces, and `:ro,Z` keeps the config mount read-only while allowing Podman to relabel it for SELinux.

Back the policy with a config test rather than relying on review memory. `atuin/tests/local-ai-config/run.sh:36-52` checks local-only Atuin client settings and conservative AI capabilities. `atuin/tests/local-ai-config/run.sh:84-93` checks the local Ollama backend target and model aliases. `atuin/tests/local-ai-config/run.sh:103-114` checks that the service uses a readable config, loopback publishing, SELinux relabeling, the Atuin AI server image, and no `--network host`.

## Why This Matters

Host networking makes the service simpler, but it also lets the container bind the backend to whatever interface the server chooses. For a local AI bridge with no authentication token, that is the wrong default: the service should be unreachable from other hosts unless the user deliberately opts into that exposure.

SELinux relabeling is the other practical Fedora detail. A mount can be syntactically valid and still fail when the container tries to read it if labeling does not match container access rules. Adding `:ro,Z` makes the intended read-only config mount work with Podman and SELinux instead of depending on permissive host state.

The regression test also needs to be enforcement-safe. Python `assert` statements can be removed when Python optimization is enabled, so policy checks should call an explicit helper that exits on failure. The current test uses `check(...)` helpers in `atuin/tests/local-ai-config/run.sh:24-26` and `atuin/tests/local-ai-config/run.sh:76-78`, and it was verified with both normal Python and `PYTHONOPTIMIZE=1`.

## When to Apply

- Use this pattern for local-only AI adapters that expose an HTTP API.
- Use this pattern when the service has no auth token and must not be reachable from the LAN.
- Use this pattern when Podman bind-mounts tracked config files on Fedora or another SELinux-enabled system.
- Use the `host.containers.internal` backend target when the container must call a host-local service such as Ollama.

## Examples

Before, the risky shape is host networking plus a plain read-only bind mount:

```ini
ExecStart=/usr/sbin/podman run --rm --name atuin-ai-server --network host -v %h/.config/atuin-ai/config.toml:/etc/atuin-ai/config.toml:ro ghcr.io/atuinsh/atuin-ai-server:latest
```

After, publish the backend only on loopback and relabel the config for the container:

```ini
ExecStart=/usr/sbin/podman run --rm --name atuin-ai-server -p 127.0.0.1:8080:8080 -v %h/.config/atuin-ai/config.toml:/etc/atuin-ai/config.toml:ro,Z ghcr.io/atuinsh/atuin-ai-server:latest
```

The verification command should cover both normal and optimized Python execution:

```bash
bash atuin/tests/local-ai-config/run.sh
PYTHONOPTIMIZE=1 bash atuin/tests/local-ai-config/run.sh
```

## Related

- [Use Atuin with local Ollama for terminal AI](./atuin-local-ai.md)
- [Atuin local AI implementation plan](../../superpowers/plans/2026-07-20-atuin-local-ai.md)
