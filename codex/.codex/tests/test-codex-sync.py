#!/usr/bin/env python3
"""Integration tests run the real sync command against isolated user homes."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import tomllib
import unittest

ROOT = Path(__file__).resolve().parents[3]


class SyncTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name) / 'home'
        self.root = Path(self.temp.name) / 'checkout'
        self.directory = self.root / 'codex/.codex'
        self.directory.mkdir(parents=True)
        self.script = self.root / 'bin/.local/bin/codex-sync'
        self.script.parent.mkdir(parents=True)
        shutil.copy2(ROOT / 'bin/.local/bin/codex-sync', self.script)
        for filename in ['config.base.toml', 'sync_config.py']:
            shutil.copy2(ROOT / 'codex/.codex' / filename, self.directory / filename)
        self.home.mkdir()
        self.codex = self.home / '.codex'
        self.codex.mkdir()
        self.generated = self.directory / 'config.toml'
        self.live = self.codex / 'config.toml'

    def run_sync(self, activate=False, success=True, **extra):
        env = {key: value for key, value in os.environ.items() if key not in ['CODEX_HOME', 'CODEX_SYNC_LIVE', 'DOTFILES']}
        env.update(HOME=str(self.home), DOTFILES=str(self.root))
        if activate:
            env['CODEX_HOME'] = str(self.codex)
        env.update(extra)
        result = subprocess.run([str(self.script)], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, success, result.stderr)
        return result

    def config(self):
        return tomllib.loads(self.generated.read_text())

    def stale(self):
        return '''model = "gpt-6.1-sol"
model_reasoning_effort = "low"
review_model = "custom-review"
approvals_reviewer = "auto_review"
sandbox_mode = "danger-full-access"
approval_policy = "never"
[features]
hooks = true
goals = false
[auto_review]
instructions = "old"
[hooks]
PreToolUse = [{command="retired"}]
[mcp_servers.context-mode]
command = "context-mode"
[mcp_servers.other]
command = "local-tool"
[marketplaces.agentmemory]
source = "old"
[marketplaces.other]
source_type = "local"
source = "/example/local"
[plugins."agentmemory@agentmemory"]
enabled = true
[plugins."pdf@openai-primary-runtime"]
enabled = false
[projects."/work project"]
trust_level = "trusted"
[unrelated]
date = 2026-09-30
time = 10:11:12
datetime = 2026-09-30T10:11:12Z
array = [{name = "one", nested = {flag=true}}, {name = "two"}]
text = "line\\nquote\\\"unicode 한글"
'''

    def assert_decisions(self):
        config = self.config()
        self.assertEqual((config['approval_policy'], config['approvals_reviewer'], config['sandbox_mode']), ('on-request', 'user', 'workspace-write'))
        self.assertFalse(config['features']['hooks'])
        self.assertNotIn('auto_review', config)
        self.assertNotIn('hooks', config)
        self.assertNotIn('context-mode', config.get('mcp_servers', {}))
        self.assertNotIn('agentmemory', config['marketplaces'])
        self.assertFalse(config['plugins']['agentmemory@agentmemory']['enabled'])
        self.assertEqual(len([entry for entry in config['skills']['config'] if not entry['enabled']]), 30)
        self.assertTrue(all(entry['path'].startswith(str(self.home)) for entry in config['skills']['config']))

    def test_merge_and_repeat_generation_does_not_activate(self):
        original = self.stale()
        self.live.write_text(original)
        self.run_sync()
        config = self.config()
        old = tomllib.loads(original)
        for key in ['model', 'model_reasoning_effort', 'review_model', 'projects', 'unrelated']:
            self.assertEqual(config[key], old[key])
        self.assertFalse(config['plugins']['pdf@openai-primary-runtime']['enabled'])
        self.assertEqual(config['mcp_servers']['other'], old['mcp_servers']['other'])
        self.assertEqual(config['marketplaces']['other'], old['marketplaces']['other'])
        self.assertFalse(config['features']['goals'])
        self.assertEqual(self.live.read_text(), original)
        self.assert_decisions()
        before = self.generated.read_bytes()
        self.run_sync()
        self.assertEqual(before, self.generated.read_bytes())

    def test_activation_managed_links_and_repeat(self):
        self.generated.write_text(self.stale())
        self.live.symlink_to(self.generated)
        for relative in ['hooks.json', 'hooks/atomic-commits.sh', 'hooks/worktree-guard.sh']:
            path = self.codex / relative
            path.parent.mkdir(exist_ok=True)
            path.symlink_to(self.directory / relative)  # Dangling retired sources are expected.
        unrelated = self.codex / 'user-notes'
        unrelated.write_text('keep')
        self.run_sync(activate=True)
        self.assert_decisions()
        self.assertEqual(self.config()['model'], 'gpt-6.1-sol')
        self.assertTrue(self.live.is_symlink())
        self.assertEqual(unrelated.read_text(), 'keep')
        self.assertFalse((self.codex / 'hooks.json').is_symlink())
        self.assertEqual(list((self.codex / 'hooks').iterdir()), [])
        before = self.generated.read_bytes()
        self.run_sync(activate=True)
        self.assertEqual(before, self.generated.read_bytes())

    def test_home_symlink_same_regular_target(self):
        self.codex.rmdir()
        self.codex.symlink_to(self.directory, target_is_directory=True)
        self.generated.write_text(self.stale())
        self.run_sync(activate=True)
        self.assertFalse(self.generated.is_symlink())
        self.assertEqual(self.config()['model_reasoning_effort'], 'low')
        self.run_sync(activate=True)

    def test_preflight_refusals_do_not_mutate(self):
        for scenario in ['regular-live', 'unrelated-link', 'unmanaged-json', 'unmanaged-hook', 'malformed', 'generated-link']:
            with self.subTest(scenario=scenario):
                if self.live.exists() or self.live.is_symlink():
                    self.live.unlink()
                if self.generated.exists() or self.generated.is_symlink():
                    self.generated.unlink()
                hooks = self.codex / 'hooks'
                if hooks.exists():
                    shutil.rmtree(hooks)
                json_path = self.codex / 'hooks.json'
                if json_path.exists():
                    json_path.unlink()
                self.generated.write_text(self.stale())
                self.live.symlink_to(self.generated)
                if scenario == 'regular-live':
                    self.live.unlink()
                    self.live.write_text(self.stale())
                elif scenario == 'unrelated-link':
                    self.live.unlink()
                    self.live.symlink_to('/unrelated/config.toml')
                elif scenario == 'unmanaged-json':
                    json_path.write_text('{}')
                elif scenario == 'unmanaged-hook':
                    hooks.mkdir()
                    (hooks / 'user.sh').write_text('keep')
                elif scenario == 'malformed':
                    self.generated.write_text('model = "secret-do-not-print')
                elif scenario == 'generated-link':
                    self.generated.unlink()
                    self.generated.symlink_to('/unrelated/generated')
                before = self.generated.read_bytes() if self.generated.is_file() else os.readlink(self.generated)
                live_before = os.readlink(self.live) if self.live.is_symlink() else self.live.read_bytes()
                result = self.run_sync(activate=True, success=False)
                self.assertNotIn('secret-do-not-print', result.stderr)
                after = self.generated.read_bytes() if self.generated.is_file() else os.readlink(self.generated)
                self.assertEqual(before, after)
                self.assertEqual(live_before, os.readlink(self.live) if self.live.is_symlink() else self.live.read_bytes())

    def test_inferred_checkout_and_explicit_opt_in(self):
        env = {key: value for key, value in os.environ.items() if key not in ['CODEX_HOME', 'CODEX_SYNC_LIVE', 'DOTFILES']}
        env['HOME'] = str(self.home)
        subprocess.run([str(self.script)], env=env, check=True, capture_output=True)
        self.assertFalse(self.live.exists())
        self.run_sync(CODEX_SYNC_LIVE='1')
        self.assertTrue(self.live.is_symlink())
        self.assert_decisions()

    def test_generation_refuses_live_same_target_without_opt_in(self):
        self.codex.rmdir()
        self.codex.symlink_to(self.directory, target_is_directory=True)
        self.generated.write_text(self.stale())
        before = self.generated.read_bytes()
        self.run_sync(success=False)
        self.assertEqual(before, self.generated.read_bytes())

    def test_symlink_skill_alias_cannot_reenable_retired_skill(self):
        skill = self.home / '.agents/skills/archify/SKILL.md'
        skill.parent.mkdir(parents=True)
        skill.write_text('fixture')
        alias = self.home / 'alias.md'
        alias.symlink_to(skill)
        self.live.write_text('[[skills.config]]\npath = "' + str(alias) + '"\nenabled = true\n')
        self.run_sync()
        self.assertFalse(any(entry['enabled'] for entry in self.config()['skills']['config']))


if __name__ == '__main__':
    unittest.main()
