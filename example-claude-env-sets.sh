#!/usr/bin/env bash

# User environment definitions for claude-env-switcher
# Replace the placeholder tokens/URLs below with your real values when ready.

# List available environments (zsh array shown; bash array also works)
typeset -a CLS_ENV_NAMES
CLS_ENV_NAMES=( default anthropic deepseek openrouter )

# Vars to clear on every switch (keep it minimal)
typeset -a CLS_MANAGED_VARS
CLS_MANAGED_VARS=( ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL )

# Optional globals applied for every env before the specific env
cls_env_globals() {
  : "${API_TIMEOUT_MS:=600000}"
  export API_TIMEOUT_MS
}

# Apply an environment by name. Return non-zero for unknown.
cls_apply_env() {
  case "$1" in
    default)
      # leave everything cleared (baseline)
      return 0
      ;;

    anthropic)
      # Production Anthropic API
      export ANTHROPIC_BASE_URL="https://api.anthropic.com"
      export ANTHROPIC_AUTH_TOKEN="sk-ant-REPLACE_ME_PROD"
      ;;

    deepseek)
      # DeepSeek Anthropic-compatible proxy path
      export ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic"
      export ANTHROPIC_AUTH_TOKEN="sk-deepseek-REPLACE_ME"
      ;;

    openrouter)
      # OpenRouter Anthropic-compatible endpoint
      export ANTHROPIC_BASE_URL="https://openrouter.ai/api/anthropic"
      export ANTHROPIC_AUTH_TOKEN="sk-or-REPLACE_ME"
      ;;

    *)
      return 2
      ;;
  esac
}
