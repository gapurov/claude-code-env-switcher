# claude-env-switcher

## Installation

Source the switcher in your shell rc and create a config file with your environments.

```bash
# Put the script somewhere (example):
mkdir -p ~/.claude
cp claude-env-switcher.sh ~/.claude/

# Source it from your shell rc (zsh shown; bash uses ~/.bashrc):
echo '[[ -r ~/.claude/claude-env-switcher.sh ]] && source ~/.claude/claude-env-switcher.sh' >> ~/.zshrc

# Create your env config (recommended global path; project-local ./claude-env-sets.sh also works):
cp claude-env-sets.sh ~/.claude/claude-env-sets.sh
# Edit ~/.claude/claude-env-sets.sh and replace placeholder tokens/URLs

# Optional: customize (set in your shell rc before sourcing)
# export CLAUDE_SHORTCUT=cls              # set empty to disable the `cls` alias
# export CLAUDE_ENV_DEFAULT=default       # name of the default environment
# export CLAUDE_ENV_FILE=~/.claude/claude-env-sets.sh  # single path override
```

## Use it

```bash
clsenv list # show environments (from claude-env-sets.sh)
clsenv -e ./project/claude-env-sets.sh list # use a custom config path just for this shell
clsenv use anthropic # switch current shell
clsenv --local use anthropic # switch only this shell (do not persist)
clsenv show # print managed vars (masked)
clsenv reload # re-exec Zsh and re-read rc files
clsenv clear # return to empty default
cls "Hello" # runs the 'claude' CLI via the 'cls' shortcut
```

### Options

```text
clsenv [--env-file <path>] [--local] <command> [args]

Commands:
  list                 Show available env names
  use <name>           Switch current shell to this env (persistent by default)
  reload [<name>]      (Optionally switch) then restart the shell (login)
  show                 Print managed vars (masked for secrets)
  current              Print active env name
  clear|default        Switch to the empty default env

Flags:
  -e, --env-file <path>  Use a specific claude-env-sets.sh for this shell
  -l, --local            Do not persist the change; only affect current shell
```

### Local vs. persistent switches

- Persistent (default): `clsenv use <name>` writes the chosen env to a state file next to the script, so new shells start with that env.
- Local only: `clsenv --local use <name>` affects only the current shell and does not change the saved state. This also works with reload, e.g. `clsenv -l reload <name>`.
