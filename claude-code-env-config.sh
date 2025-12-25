#!/usr/bin/env bash

# User environment definitions for claude-code-env-switcher.
# Environments live in .env.cc.<provider> files next to this config by default.
# Optional shared defaults go into .env.cc, with .env as a fallback when it
# contains CCENV_ or ANTHROPIC_ variables.
# Set CCENV_DISPLAY_NAME in a .env.cc.<provider> file to customize menu labels.

# Optional: override where .env.cc files live.
# CCENV_ENV_DIR="$HOME/.claude/envs"

# Vars to clear on every switch (include vars you set in .env.cc* files).
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
  local env_name="$1"
  [ "$env_name" = "default" ] && return 0

  local env_file=""
  env_file="$(ccenv__env_file_for "$env_name" 2>/dev/null || true)"
  [ -r "$env_file" ] || return 2
  ccenv__source_env_file "$env_file" || return 2
}
