# Atuin Ollama Loopback Connectivity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore Atuin AI inference by forwarding only Ollama's loopback port into the rootless Atuin AI container.

**Architecture:** Keep Ollama on host loopback and keep `atuin-ai-server` in its own network namespace. Podman's pasta network forwards container TCP port 11434 to host loopback, and the backend addresses Ollama as `127.0.0.1:11434` inside the container.

**Tech Stack:** Atuin 18, Ollama, rootless Podman with pasta, systemd user services, TOML, Bash, Python 3 `tomllib`

**Spec:** `docs/superpowers/specs/2026-08-16-atuin-ollama-loopback-design.md`

## Global Constraints

- Ollama must remain bound only to `127.0.0.1:11434`; do not change global Ollama configuration.
- The Atuin AI API must remain published only as `127.0.0.1:8080:8080`.
- The container must not use host networking or privileged mode.
- The only new container-to-host forwarding is TCP port 11434.
- Do not add cloud endpoints, cloud fallback, retries, startup dependencies, new models, or new services.
- Do not change model aliases, the API-key placeholder, request-body settings, or Atuin AI capabilities.

---

## File Map

- `atuin/tests/local-ai-config/run.sh`: static executable contract for local endpoints and container isolation.
- `atuin/.config/atuin-ai/config.toml`: Atuin AI server's Ollama endpoint and existing model mappings.
- `atuin/.config/systemd/user/atuin-ai.service`: rootless Podman network, port publication, and container lifecycle.
- `docs/solutions/tooling-decisions/atuin-local-ai.md`: operator setup, security rationale, deployment, and troubleshooting.

### Task 1: Route the Isolated Container to Ollama Loopback

**Files:**
- Modify: `atuin/tests/local-ai-config/run.sh`
- Modify: `atuin/.config/atuin-ai/config.toml`
- Modify: `atuin/.config/systemd/user/atuin-ai.service`

**Interfaces:**
- Consumes: host Ollama listener `127.0.0.1:11434`; Atuin client listener `127.0.0.1:8080`; Podman pasta `-T` TCP forwarding.
- Produces: container-local OpenAI-compatible upstream `http://127.0.0.1:11434/v1`; `podman run` network argument `--network=pasta:-T,11434`.

- [ ] **Step 1: Change the static contract first**

In the Python config assertions in `atuin/tests/local-ai-config/run.sh`, replace the upstream assertion with:

```python
check(config.get("endpoint") == "http://127.0.0.1:11434/v1", "Atuin AI server must target Ollama through loopback forwarding")
```

Immediately after the existing `ExecStartPre` assertion, add:

```bash
rg -q -- '--network=pasta:-T,11434 ' "$AI_SERVICE" \
  || fail "atuin-ai service must forward only Ollama TCP through pasta"
```

Keep the existing assertion that rejects `--network host`. Extend it to reject both accepted spellings:

```bash
if rg -q -- '--network([ =])host' "$AI_SERVICE"; then
  fail "atuin-ai service must not use host networking"
fi
```

- [ ] **Step 2: Run the focused test and verify the new contract fails**

Run:

```bash
bash atuin/tests/local-ai-config/run.sh
```

Expected: FAIL with `Atuin AI server must target Ollama through loopback forwarding`. No repository file other than the test has changed yet.

- [ ] **Step 3: Change the backend upstream to container loopback**

In `atuin/.config/atuin-ai/config.toml`, replace only the endpoint value:

```toml
endpoint = "http://127.0.0.1:11434/v1"
```

Leave `port`, `api_key`, `default_model`, request settings, and both model entries unchanged.

- [ ] **Step 4: Add targeted pasta forwarding to the service**

Replace the service's `ExecStart` with this single line:

```systemd
ExecStart=/usr/sbin/podman run --rm --name atuin-ai-server --network=pasta:-T,11434 -p 127.0.0.1:8080:8080 -v %h/.config/atuin-ai/config.toml:/etc/atuin-ai/config.toml:ro,Z ghcr.io/atuinsh/atuin-ai-server:latest
```

Do not change `ExecStop`, restart behavior, or unit dependencies.

- [ ] **Step 5: Run the static contract and syntax checks**

Run:

```bash
bash atuin/tests/local-ai-config/run.sh
git diff --check
```

Expected: all six `ok` messages from the shell test, followed by no output from `git diff --check`.

- [ ] **Step 6: Prove the network path with a disposable container**

First confirm Ollama is still loopback-only:

```bash
ss -ltn 'sport = :11434'
```

Expected: a listener on `127.0.0.1:11434`, with no `0.0.0.0:11434` or LAN address.

Start a disposable backend from the worktree config on an unused host port:

```bash
podman run -d --rm --name atuin-ai-loopback-probe --network=pasta:-T,11434 -p 127.0.0.1:18080:8080 -v "$PWD/atuin/.config/atuin-ai/config.toml:/etc/atuin-ai/config.toml:ro,Z" ghcr.io/atuinsh/atuin-ai-server:latest
```

Run the real client against it:

```bash
atuin ai inline --verbose --api-endpoint http://127.0.0.1:18080 "echo hello"
```

Expected: Atuin displays a model-generated response and does not report `ECONNREFUSED`. Exit the TUI, then stop the disposable container:

```bash
podman stop atuin-ai-loopback-probe
```

The container uses `--rm`, so stopping it also removes the temporary probe.

- [ ] **Step 7: Inspect and commit the connectivity fix**

Run `git diff` and verify it contains only the test, endpoint, and service changes above. Stage explicit paths and commit:

```bash
git add atuin/tests/local-ai-config/run.sh atuin/.config/atuin-ai/config.toml atuin/.config/systemd/user/atuin-ai.service
git diff --cached
git commit -m "fix: connect Atuin AI to loopback Ollama" -- atuin/tests/local-ai-config/run.sh atuin/.config/atuin-ai/config.toml atuin/.config/systemd/user/atuin-ai.service
```

### Task 2: Document the Secure Network Path and Recovery Checks

**Files:**
- Modify: `docs/solutions/tooling-decisions/atuin-local-ai.md`

**Interfaces:**
- Consumes: backend endpoint `http://127.0.0.1:11434/v1`; service network argument `--network=pasta:-T,11434`.
- Produces: deployment and troubleshooting instructions that preserve the loopback-only runtime contract.

- [ ] **Step 1: Confirm the operator notes describe the obsolete endpoint**

Run:

```bash
rg -n 'host\.containers\.internal:11434|loopback forwarding|daemon-reload' docs/solutions/tooling-decisions/atuin-local-ai.md
```

Expected: the obsolete `host.containers.internal:11434` endpoint is present; no explanation of pasta loopback forwarding is present.

- [ ] **Step 2: Update deployment instructions**

After the existing `stow -t ~ atuin` command, state that an already-enabled service must be recreated after configuration changes. Replace the service command block with:

```bash
systemctl --user daemon-reload
systemctl --user enable atuin-ai.service
systemctl --user restart atuin-ai.service
systemctl --user status atuin-ai.service
```

Explain that restarting recreates the `--rm` container with the tracked pasta network arguments.

- [ ] **Step 3: Document the local-only backend path**

Replace the backend endpoint example with:

```toml
endpoint = "http://127.0.0.1:11434/v1"
default_model = "qwen3-coder-30b"
```

Add one paragraph stating that `--network=pasta:-T,11434` forwards only the container's TCP port 11434 to host loopback. Explicitly state that Ollama must remain on `127.0.0.1:11434`, and that neither host networking nor `OLLAMA_HOST=0.0.0.0:11434` is required.

- [ ] **Step 4: Replace troubleshooting with boundary-specific checks**

Use this command block under `## Troubleshooting`:

```bash
# Host Ollama: must succeed and remain bound to loopback.
ss -ltn 'sport = :11434'
curl --fail --silent --show-error http://127.0.0.1:11434/v1/models

# Atuin backend and its recent upstream errors.
systemctl --user status atuin-ai.service
journalctl --user-unit atuin-ai.service --no-pager -n 50
curl --fail --silent --show-error http://127.0.0.1:8080/api/cli/models

# End-to-end inference.
atuin ai inline --verbose "echo hello"
```

Explain that `ECONNREFUSED` for `127.0.0.1:11434` in the container logs means either Ollama is stopped or the service was not restarted with the pasta forwarding argument.

- [ ] **Step 5: Verify documentation and regression coverage**

Run:

```bash
rg -n 'endpoint = "http://127\.0\.0\.1:11434/v1"|network=pasta:-T,11434|OLLAMA_HOST=0\.0\.0\.0:11434' docs/solutions/tooling-decisions/atuin-local-ai.md
bash atuin/tests/local-ai-config/run.sh
git diff --check
```

Expected: all three security-relevant documentation patterns are present, the shell test passes, and `git diff --check` prints nothing.

- [ ] **Step 6: Inspect and commit the operator documentation**

Run `git diff` and verify it contains only the operator documentation changes above. Stage the explicit path and commit:

```bash
git add docs/solutions/tooling-decisions/atuin-local-ai.md
git diff --cached
git commit -m "docs: explain Atuin Ollama loopback routing" -- docs/solutions/tooling-decisions/atuin-local-ai.md
```

### Task 3: Final Verification

**Files:**
- Verify only; no repository changes expected.

**Interfaces:**
- Consumes: committed Task 1 network configuration and Task 2 operator documentation.
- Produces: evidence that the branch is internally consistent, locally secure, and ready for review.

- [ ] **Step 1: Run the repository regression test**

```bash
bash atuin/tests/local-ai-config/run.sh
```

Expected: all six `ok` messages and exit status 0.

- [ ] **Step 2: Verify the final diff and commit boundaries**

```bash
git status --short
git log --oneline -3
git diff main...HEAD --check
git diff --stat main...HEAD
```

Expected: clean status; one design commit, one connectivity-fix commit, and one documentation commit; no whitespace errors; only the spec, test, Atuin AI config, systemd service, and operator notes changed.
