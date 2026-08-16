# Atuin Ollama Loopback Connectivity Design

## Goal

Restore Atuin AI command generation while keeping both Atuin AI and Ollama local to this machine. The Atuin AI container must reach Ollama without binding Ollama to a LAN-accessible address or giving the container the host network namespace.

## Problem

The Atuin client successfully reaches `atuin-ai-server` on `127.0.0.1:8080`, and the configured `qwen3-coder:30b` model works when invoked directly through Ollama. The remaining hop fails because the container connects to `host.containers.internal:11434`, while Ollama listens only on the host loopback address `127.0.0.1:11434`. The container resolves the hostname but receives `ECONNREFUSED`.

The current configuration therefore combines two incompatible assumptions:

- Ollama remains reachable only through host loopback.
- A network-isolated container reaches Ollama through a non-loopback host gateway address.

## Recommended Approach

Use Podman's rootless pasta network with targeted container-to-host TCP forwarding for port 11434:

```text
Atuin CLI
  -> 127.0.0.1:8080 (published container port)
  -> atuin-ai-server
  -> 127.0.0.1:11434 inside the container
  -> pasta -T 11434
  -> 127.0.0.1:11434 on the host
  -> Ollama
```

The systemd user service will pass `--network=pasta:-T,11434` to `podman run`. The Atuin AI server configuration will use `http://127.0.0.1:11434/v1` as its upstream endpoint.

Podman's `-T` pasta option forwards a selected TCP port from the container to the host through loopback. This keeps the container in its own network namespace and grants access only to the required Ollama port.

## Alternatives Rejected

### Host networking

Running the container with `--network=host` would make host loopback directly reachable, but it would also expose every host-local socket to the container. This broadens privileges and violates the existing test and security boundary.

### Broad Ollama bind

Setting Ollama to listen on `0.0.0.0:11434` or another externally reachable interface would make the existing gateway endpoint work, but could expose an unauthenticated inference API to the LAN. Firewall rules would add an unnecessary second security mechanism.

### Additional proxy service

A host proxy could accept traffic on a container-reachable address and relay it to Ollama loopback. This adds another service, lifecycle, configuration, and failure mode when pasta already provides targeted forwarding.

## Repository Changes

### Atuin AI service

Update `atuin/.config/systemd/user/atuin-ai.service` to select the pasta network and forward only TCP port 11434 from the container to host loopback. Keep the existing `127.0.0.1:8080:8080` publication so the Atuin AI API remains host-local.

Do not use host networking, privileged mode, or a broad host bind.

### Backend configuration

Update `atuin/.config/atuin-ai/config.toml` so the upstream endpoint is `http://127.0.0.1:11434/v1`. Model aliases, API-key placeholder, and request-body settings remain unchanged.

### Regression tests

Update `atuin/tests/local-ai-config/run.sh` to require:

- the loopback Ollama endpoint in the backend configuration;
- the explicit pasta TCP forwarding for port 11434;
- the existing loopback publication for port 8080;
- continued rejection of host networking and cloud endpoints.

The static test will validate the tracked security contract without requiring Podman, systemd, or Ollama to be running.

### Operator documentation

Update `docs/solutions/tooling-decisions/atuin-local-ai.md` to explain the targeted loopback forwarding and add a troubleshooting check that distinguishes the Atuin API, container-to-Ollama hop, and direct Ollama endpoint.

## Runtime and Error Handling

The Atuin AI service will remain independently startable when Ollama is stopped. A request made while Ollama is unavailable will return the upstream connection error through Atuin, preserving a useful diagnosis instead of causing the container to restart repeatedly.

No automatic retry, fallback model service, cloud fallback, or startup dependency will be added. Restarting the Atuin AI service after deployment is sufficient to recreate the container with the new network settings.

## Validation

Implementation is complete only when all of the following pass:

1. `bash atuin/tests/local-ai-config/run.sh` passes.
2. `ss` confirms Ollama still listens only on `127.0.0.1:11434`.
3. The user service is active with `--network=pasta:-T,11434` and the existing loopback-only port 8080 publication.
4. A request from inside the container reaches the Ollama OpenAI-compatible models endpoint through `127.0.0.1:11434`.
5. `atuin ai inline --verbose "echo hello"` produces an inferred response without `ECONNREFUSED`.
6. No cloud endpoint, host networking, or broad Ollama bind is introduced.

## Scope Boundaries

This change does not install or upgrade Atuin, Ollama, Podman, models, or container images. It does not enable Atuin sync, hosted AI, command execution, file tools, history output, or another model. It does not change global Podman or Ollama configuration.
