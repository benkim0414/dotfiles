# Atuin Local AI Design

## Goal

Configure a strictly local terminal AI workflow for this dotfiles setup, after comparing Warp and Atuin as LLM-enabled terminal tools. The result should keep all AI inference on the machine, fit the existing zsh and Ghostty workflow, and avoid cloud fallback paths.

## Current Context

This repo already manages zsh, Ghostty, Starship, mise, Neovim, and related developer tooling. There is no existing Atuin, Warp, Ollama, or local LLM configuration in the tracked dotfiles.

The current machine is a Fedora Linux system with an AMD Ryzen AI Max+ 395, 32 CPU threads, 62 GiB RAM, and Radeon 8060S-class graphics. During inspection, `ollama`, `rocminfo`, `nvidia-smi`, `/dev/kfd`, and `/dev/dri` were not available from the current shell. The design therefore treats CPU local inference as the reliable baseline, with AMD GPU or NPU acceleration left out of scope until the host exposes a supported runtime.

## Product Comparison

Atuin is the better fit for strict local AI. Atuin AI can use a self-hosted `atuin-ai-server`, and that server supports OpenAI-compatible chat completion endpoints such as Ollama, LM Studio, vLLM, llama.cpp, and LiteLLM. Atuin also works inside the existing shell and terminal, so it can extend the current zsh and Ghostty workflow instead of replacing it.

Warp has a stronger polished AI terminal experience, including agent conversations, model selection, context attachment, task lists, code review, full terminal use, and active recommendations. However, Warp's documented AI path sends input data to LLM providers, and its Bring Your Own LLM documentation is Enterprise-only and AWS Bedrock-oriented. Warp maintainers have discussed local and arbitrary model support, but it is not a documented local-only user path today.

For this repo, the comparison resolves to:

- Use Atuin when strict local AI is a requirement.
- Treat Warp as a possible terminal UX experiment only if Warp AI is disabled.
- Do not design around Warp for local LLM integration until Warp ships a supported local endpoint or fully local harness.

## Recommended Approach

Keep Ghostty and zsh as the terminal foundation. Add Atuin for shell history, command search, and AI entry points. Run Ollama locally as the model runtime. Run `atuin-ai-server` locally as the Atuin-compatible AI backend. Configure Atuin to use the local backend endpoint and disable cloud-oriented assumptions.

The target data flow is:

1. zsh loads Atuin shell integration.
2. Atuin stores command history in its local SQLite database.
3. Pressing `?` on an empty prompt opens Atuin AI.
4. Atuin sends AI requests to `http://localhost:8080`.
5. `atuin-ai-server` forwards requests to Ollama's OpenAI-compatible endpoint at `http://localhost:11434/v1`.
6. Ollama runs the selected local model on this machine.

No request should intentionally route to Atuin Hub, Warp AI, OpenAI, OpenRouter, Bedrock, or any other cloud inference service.

## Model Selection

Use `qwen3-coder:30b` as the first model to test. It is coding-oriented, agent-oriented, and should fit within the available system RAM for CPU-first inference. Use it for command generation, shell workflow help, and local development questions.

Keep `gpt-oss:20b` as the fallback model if `qwen3-coder:30b` is too slow or too narrowly coding-focused. It is a better fallback for general reasoning with lower memory pressure.

Do not start with larger models that require substantially more memory or specialized GPU setup. In particular, models requiring around 120B parameters or hundreds of GiB of unified memory are out of scope for this machine's reliable baseline.

## Configuration Boundaries

The implementation should be small and reversible:

- Add Atuin CLI installation through the repo's existing tool-management pattern if practical.
- Add tracked Atuin config under the appropriate XDG path.
- Add zsh initialization for Atuin using the repo's existing zsh structure.
- Add local-only AI settings that point at `http://localhost:8080`.
- Add documentation for starting Ollama and `atuin-ai-server`.
- Avoid installing or configuring Warp as part of the local AI path.
- Avoid enabling Atuin cloud sync or Atuin Hub login as part of this setup.
- Avoid enabling YOLO-style automatic permission bypass.

If Atuin's AI capabilities expose file tools, command execution, history search, or history output, they should be configured conservatively. Command suggestions are useful, but local AI should not silently execute destructive commands or get broad filesystem write privileges without explicit user action.

## Error Handling

If Ollama is not installed, Atuin should still provide non-AI history/search features once installed. AI use should fail with a clear local dependency message rather than falling back to cloud.

If `atuin-ai-server` is not running, the `?` AI entry point should fail against the configured local endpoint. This is acceptable because strict local-only behavior is more important than seamless fallback.

If `qwen3-coder:30b` is too slow, switch the configured default model to `gpt-oss:20b` rather than changing providers.

If AMD acceleration becomes available later, treat it as a separate optimization pass with its own verification. The initial implementation should not depend on ROCm, NPU support, or device nodes being present.

## Validation

Verification should confirm:

- `atuin` is installed and available in zsh.
- zsh initializes Atuin without breaking existing history behavior.
- Atuin history/search works locally.
- Ollama serves a local OpenAI-compatible endpoint.
- `atuin-ai-server` serves `http://localhost:8080`.
- Atuin AI is configured for the local endpoint and does not require Hub login.
- A simple command-generation prompt works with `qwen3-coder:30b`.
- Network/cloud fallback is not configured in the tracked Atuin AI settings.

Because this is a dotfiles repo, implementation verification can include shell startup checks, config syntax checks, and manual command probes rather than a conventional test suite.

## Out Of Scope

- Installing or configuring Warp for AI.
- Using Atuin Hub, hosted Atuin AI, OpenAI, OpenRouter, AWS Bedrock, or any cloud fallback.
- Solving AMD GPU, ROCm, or Ryzen AI NPU acceleration.
- Replacing Ghostty.
- Migrating all historical shell history across machines.
- Building a custom model router beyond the local Atuin AI backend and Ollama endpoint.

## Source Notes

- Atuin AI documents self-hosting and local model support through OpenAI-compatible endpoints, including Ollama, LM Studio, vLLM, llama.cpp, and LiteLLM.
- Atuin AI settings support custom endpoints and an OSS server mode.
- Warp's agent documentation describes a richer agent UX, but also states AI features send input data to LLM providers.
- Warp's Bring Your Own LLM documentation is Enterprise-only and currently AWS Bedrock-oriented.
- Warp maintainers have discussed local model support, but as of the reviewed documentation it is not a supported local-only path.
