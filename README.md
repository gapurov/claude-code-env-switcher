# Claude Code Environment Switcher

## Installation

```bash
# Put the script somewhere (example):
mkdir -p ~/.claude
cp claude-code-env-switcher.sh ~/.claude/

# Source it from your shell rc (zsh shown; bash uses ~/.bashrc):
echo '[[ -r ~/.claude/claude-code-env-switcher.sh ]] && source ~/.claude/claude-code-env-switcher.sh' >> ~/.zshrc

# Create your env config (recommended global path; project-local ./claude-code-env-sets.sh also works):
cp claude-code-env-sets.sh ~/.claude/claude-code-env-sets.sh
# Edit ~/.claude/claude-code-env-sets.sh and replace placeholder tokens/URLs

# Optional: customize (set in your shell rc before sourcing)
# export CLAUDE_ENV_DEFAULT=default       # name of the default environment
# export CLAUDE_ENV_FILE=~/.claude/claude-code-env-sets.sh  # single path override
```

## Use it

```bash
ccenv list # show environments (from claude-code-env-sets.sh)
ccenv       # with fzf installed: interactive menu to pick a command
ccenv use   # with fzf installed: interactive env picker (includes --local)
ccenv -e ./project/claude-code-env-sets.sh list # use a custom config path just for this shell
ccenv use anthropic # switch current shell
ccenv --local use anthropic # switch only this shell (do not persist)
ccenv show # print managed vars (masked)
ccenv reload # re-exec Zsh and re-read rc files
ccenv clear # return to empty default
```

### Options

```text
ccenv [--env-file <path>] [--local] <command> [args]

Commands:
  list                 Show available env names
  use <name>           Switch current shell to this env (persistent by default)
  reload [<name>]      (Optionally switch) then restart the shell (login)
  show                 Print managed vars (masked for secrets)
  current              Print active env name
  clear|default        Switch to the empty default env

Flags:
  -e, --env-file <path>  Use a specific claude-code-env-sets.sh for this shell
  -l, --local            Do not persist the change; only affect current shell
```

### fzf-powered interactive mode (optional)

- if `fzf` is installed and running in a TTY, `ccenv` will open an interactive menu.
- `ccenv` with no args opens an interactive menu of commands (simplified; local toggles live inside `use`).
- `ccenv use` with no args opens an interactive picker of environments. For each non-default env you'll see both the normal and `--local` (do not persist) options. After selection, it prints the chosen environment.
- Selecting `list` from the interactive menu prints the environments (no fzf selection).

### Local vs. persistent switches

- Persistent (default): `ccenv use <name>` writes the chosen env to a state file next to the script, so new shells start with that env.
- Local only: `ccenv --local use <name>` affects only the current shell and does not change the saved state. This also works with reload, e.g. `ccenv -l reload <name>`.
