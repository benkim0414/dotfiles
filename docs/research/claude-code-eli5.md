# Which ELI5 skill did we install?

The Pi skill first installed in this session was **not the same** as the `eli5` plugin in Anthropic's Claude Code community marketplace. It came from [DreambigOu/ELI5](https://github.com/DreambigOu/ELI5), an independent Claude Code skill. It detects an audience (child, manager, engineer, parent, and others) and adjusts prose, analogies, and depth. Its repository says to copy `skills/eli5` into Claude Code's skills directory. That installation has since been replaced with the community plugin's skill.

The [Claude community `eli5` plugin](https://github.com/anthropics/claude-plugins-community/tree/main/eli5) is a different project, authored by Thariq Shihipar according to its [plugin manifest](https://github.com/anthropics/claude-plugins-community/blob/main/eli5/.claude-plugin/plugin.json). Its [README](https://github.com/anthropics/claude-plugins-community/blob/main/eli5/README.md) asks for `/eli5 <topic>` and says it produces an HTML artifact with large pictures and very few words. Its [skill file](https://github.com/anthropics/claude-plugins-community/blob/main/eli5/skills/eli5/SKILL.md) is a short prompt containing `Topic: $ARGUMENTS`. The manifest declares version 1.0.0 and MIT license. The [marketplace repository](https://github.com/anthropics/claude-plugins-community/blob/main/README.md) calls these community-contributed plugins; this is not an Anthropic-maintained plugin from the official marketplace.

| | First installed: DreambigOu skill | Now installed: Claude community plugin |
| --- | --- | --- |
| Source | [DreambigOu/ELI5](https://github.com/DreambigOu/ELI5) | [anthropics/claude-plugins-community/eli5](https://github.com/anthropics/claude-plugins-community/tree/main/eli5) |
| Goal | Audience-tailored prose explanation | HTML picture explainer for a beginner |
| Invocation | Natural language such as “ELI5 this” | `/eli5 <topic>` in Claude Code |
| License | [MIT](https://github.com/DreambigOu/ELI5/blob/main/LICENSE) | MIT in [plugin manifest](https://github.com/anthropics/claude-plugins-community/blob/main/eli5/.claude-plugin/plugin.json) |

## Using the community skill in Pi

[Pi's skill documentation](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/skills.md) says it discovers `SKILL.md` directories under `~/.pi/agent/skills/` and exposes them as `/skill:name`; it can also load Claude Code skill directories via settings. Therefore the community plugin's `skills/eli5/SKILL.md` can be installed as a Pi skill. The Claude plugin manifest and marketplace installation mechanism do not need to be copied into Pi.

There is one compatibility detail: Pi appends command arguments as `User: <args>` after the skill content, while the community skill uses Claude Code's `$ARGUMENTS` placeholder. The installed copy is unchanged, so `$ARGUMENTS` may remain literal; this is an inference from the two documented formats. Pi's skill command is `/skill:eli5 <topic>`, rather than Claude Code's `/eli5 <topic>`. An HTML result has not been tested in Pi.

The two skills share the name `eli5`, so Pi's documented name-collision behavior means they should not both be installed under that name. The DreambigOu copy was removed, and the Anthropic community copy is now installed at `~/.pi/agent/skills/eli5/SKILL.md`. The skills CLI lists its source as `anthropics/claude-plugins-community` for Pi.
