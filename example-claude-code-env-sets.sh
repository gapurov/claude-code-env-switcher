#!/usr/bin/env bash

# User environment definitions for claude-code-env-switcher
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

    GLM-4.5)
      export ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic"
      export ANTHROPIC_AUTH_TOKEN="sk-glm-api-token"
      export ANTHROPIC_MODEL="GLM-4.5"
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
