# Claude Code Environment Switcher

Simple environment switcher for Claude Code with fzf support.

## Installation

```bash
# Put the script somewhere (example):
mkdir -p ~/.claude
cp claude-code-env-switcher.sh ~/.claude/

# Source it from your shell rc (zsh shown; bash uses ~/.bashrc):
echo '[[ -r ~/.claude/claude-code-env-switcher.sh ]] && source ~/.claude/claude-code-env-switcher.sh' >> ~/.zshrc

# Create your env config (recommended global path; project-local ./claude-code-env-config.sh also works):
cp claude-code-env-config.sh ~/.claude/claude-code-env-config.sh
# Create one or more .env.cc.<provider> files next to it (or set CCENV_ENV_DIR).
# Optional shared defaults go into .env.cc.
# Example templates live in this repo as .env.cc.<provider>.example:
cp .env.cc.anthropic.example ~/.claude/.env.cc.anthropic
chmod 600 ~/.claude/.env.cc.anthropic

# Optional: customize (set in your shell rc before sourcing)
# export CLAUDE_ENV_DEFAULT=default       # name of the default environment
# export CLAUDE_ENV_FILE=~/.claude/claude-code-env-config.sh  # single path override
```

## Use it

```bash
ccenv list # show environments (from .env.cc.* files)
ccenv       # with fzf installed: interactive menu to pick a command
ccenv use   # with fzf installed: interactive env picker (includes --local)
ccenv -e ./project/claude-code-env-config.sh use anthropic # use a custom config path just for this shell
ccenv use anthropic # switch current shell
ccenv --local use anthropic # switch only this shell (do not persist)
ccenv reload # re-exec Zsh and re-read rc files
ccenv reset # return to empty default
ccenv version # print script version
ccenv current # print active env name
```

Env lookup uses the current directory when it has any `.env`, `.env.cc`, or `.env.cc.<provider>` files; otherwise it falls back to the directory containing `claude-code-env-config.sh` (or `CCENV_ENV_DIR` when set). Within that directory, files apply in this order: `.env` (only if it contains `ANTHROPIC_` or `CCENV_` variables), then `.env.cc`, then `.env.cc.<provider>`, so the most specific file wins.

### Included sample environments

The bundled `example-claude-code-env-config.sh` and `.env.cc.<provider>.example` files include templates for several Anthropic-compatible providers:

- `anthropic`: standard Anthropic endpoint (`https://api.anthropic.com`).
- `GLM-4.7`: Zhipu's GLM proxy (`https://api.z.ai/api/anthropic`) with GLM model defaults.
- `deepseek`: DeepSeek proxy (`https://api.deepseek.com/anthropic`).
- `minimax`: MiniMax Anthropic-compatible endpoint (`https://api.minimax.io/anthropic`) with `MiniMax-M2.1` set for all Claude model variants, a longer timeout (`API_TIMEOUT_MS=3000000`), and `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`.

### Options

```text
ccenv [--env-file <path>] [--local] <command> [args]

Commands:
  list                 Show available env names
  use <name>           Switch current shell to this env (persistent by default)
  reload [<name>]      (Optionally switch) then restart the shell (login)
  reset|clear|default  Switch to the empty default env
  version              Print ccenv script version
  current              Print active env name

Flags:
  -e, --env-file <path>  Use a specific claude-code-env-config.sh for this shell
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
