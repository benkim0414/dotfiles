# Task 1 completion report

Implemented short personal global instructions and native human-review config. Removed third-party marketplace/context-mode registrations, disabled three third-party plugins and all 29 shared skills plus custom ELI5, retained the verified local OpenAI runtime catalog and five artifact plugins. Retired the two tracked custom hook scripts and their dedicated tests. Sync script and sync tests were untouched for Task 2.

Source findings, exact provenance evidence, current live-vs-base model differences, and migration limits are recorded in [the setup audit](2026-09-30-codex-official-setup.md).

Validation: Python TOML parsing; Codex 0.159.1 strict-config app-server initialization; config/read reviewer/sandbox/approval assertions; empty hooks/list; fresh skills/list showing 29 disabled shared skills and five enabled native system skills; real legacy ELI5 symlink with controlled enabled/disabled discovery. No model requests or credentials were used. git diff --check and scoped diff inspection precede commit.

Limitations: full sync integration intentionally awaits Task 2 because the old sync requires retired hooks. Live activation and primary-checkout changes remain pending separate authorization. Interactive Codex /review is unavailable without a model request; a read-only task review by the controller is pending. Prepared absolute paths must be regenerated for another home directory, and newly added shared skills require a new disable audit.
