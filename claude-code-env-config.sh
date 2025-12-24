#!/usr/bin/env bash

# User environment definitions for claude-code-env-switcher.
# Environments live in .env.<provider> files next to this config by default.
# Set CCENV_DISPLAY_NAME in a .env.<provider> file to customize menu labels.

# Optional: override where .env.<provider> files live.
# CCENV_ENV_DIR="$HOME/.claude/envs"

# Vars to clear on every switch (include vars you set in .env.* files).
typeset -a CCENV_MANAGED_VARS
CCENV_MANAGED_VARS=(
  ANTHROPIC_AUTH_TOKEN
  ANTHROPIC_BASE_URL
  ANTHROPIC_MODEL
  ANTHROPIC_DEFAULT_HAIKU_MODEL
  ANTHROPIC_DEFAULT_SONNET_MODEL
  ANTHROPIC_DEFAULT_OPUS_MODEL
  ANTHROPIC_SMALL_FAST_MODEL
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
)

# Optional globals applied for every env before the specific env.
ccenv_globals() {
  : "${API_TIMEOUT_MS:=600000}"
  export API_TIMEOUT_MS
}

# Apply an environment by name. Return non-zero for unknown.
ccenv_apply_env() {
  local name="$1"
  [ "$name" = "default" ] && return 0

  local dir file had_allexport=0
  dir="${CCENV_ENV_DIR:-$(cd -P -- "$(dirname -- "$CCENV_ENV_FILE_PICKED")" 2>/dev/null && pwd)}"
  file="$dir/.env.$name"
  [ -r "$file" ] || return 2

  case $- in *a*) had_allexport=1;; esac
  set -a
  # shellcheck disable=SC1090
  . "$file"
  [ "$had_allexport" -eq 0 ] && set +a
}
