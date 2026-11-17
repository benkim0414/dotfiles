#!/usr/bin/env python3
"""PreToolUse hook for Bash: block broad git staging.

Blocks `git add` with -A, --all, --no-ignore-removal, -u, --update or a `.`
pathspec, and `git commit` with -a or --all. These stage whatever is in the
tree, which once nearly committed a token. Exit 2 blocks the call and shows
stderr to Claude; exit 0 allows it.

Input the hook cannot parse is allowed: this is a guard against a habit, not
a security boundary, and a parse error must not stop unrelated commands.
"""
import json
import shlex
import sys

SEPARATORS = {";", "&&", "||", "|", "&", "\n", "(", ")"}
# Leading words that run the next word as the command.
PREFIXES = {"rtk", "command", "env", "exec", "nohup", "time"}
# git global options that take the next token as their value.
GIT_VALUE_OPTS = {"-C", "-c", "--git-dir", "--work-tree", "--namespace"}
# git commit short options that take a value; the rest of a cluster after
# one of these is that value, not more flags.
COMMIT_VALUE_SHORT = set("mFCctS")

STAGE_HINT = "Stage explicit paths instead: git add <path>."


def tokenize(command):
    lex = shlex.shlex(command, posix=True, punctuation_chars="();<>|&\n")
    lex.whitespace = " \t\r"
    lex.whitespace_split = True
    return list(lex)


def segments(tokens):
    current = []
    for tok in tokens:
        if tok in SEPARATORS:
            if current:
                yield current
            current = []
        else:
            current.append(tok)
    if current:
        yield current


def git_args(words):
    """Return (subcommand, args) if the words run git, else None."""
    i = 0
    while i < len(words) and ("=" in words[i] and not words[i].startswith("-")
                              or words[i] in PREFIXES):
        i += 1
    if i >= len(words) or words[i] != "git":
        return None
    i += 1
    while i < len(words) and words[i].startswith("-"):
        i += 2 if words[i] in GIT_VALUE_OPTS else 1
    if i >= len(words):
        return None
    return words[i], words[i + 1:]


def check_add(args):
    after_dashdash = False
    for arg in args:
        if after_dashdash:
            if arg in (".", "./"):
                return "`git add .`"
            continue
        if arg == "--":
            after_dashdash = True
        elif arg in ("--all", "--update", "--no-ignore-removal"):
            return f"`git add {arg}`"
        elif arg.startswith("-") and not arg.startswith("--"):
            for flag in ("A", "u"):
                if flag in arg[1:]:
                    return f"`git add -{flag}`"
        elif arg in (".", "./"):
            return "`git add .`"
    return None


def check_commit(args):
    skip_next = False
    for arg in args:
        if skip_next:
            skip_next = False
            continue
        if arg == "--":
            break
        if arg == "--all":
            return "`git commit --all`"
        if arg.startswith("-") and not arg.startswith("--"):
            cluster = arg[1:]
            for pos, ch in enumerate(cluster):
                if ch == "a":
                    return "`git commit -a`"
                if ch in COMMIT_VALUE_SHORT:
                    skip_next = pos == len(cluster) - 1
                    break
    return None


def main():
    try:
        data = json.load(sys.stdin)
        command = data["tool_input"]["command"]
        tokens = tokenize(command)
    except (ValueError, KeyError, TypeError):
        return 0
    for words in segments(tokens):
        found = git_args(words)
        if not found:
            continue
        sub, args = found
        reason = None
        if sub == "add":
            reason = check_add(args)
        elif sub == "commit":
            reason = check_commit(args)
        if reason:
            print(f"Blocked {reason}: it stages everything in the tree. "
                  f"{STAGE_HINT} Then check `git diff --cached --name-only`.",
                  file=sys.stderr)
            return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
