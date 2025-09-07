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
clsenv show # print managed vars (masked)
clsenv reload # re-exec Zsh and re-read rc files
clsenv clear # return to empty default
cls "Hello" # runs the 'claude' CLI via the 'cls' shortcut
```
