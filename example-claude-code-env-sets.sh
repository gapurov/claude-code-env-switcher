#!/usr/bin/env bash

# User environment definitions for claude-code-env-switcher
# Replace the placeholder tokens/URLs below with your real values when ready.

# List available environments (zsh array shown; bash array also works)
typeset -a CCENV_ENV_NAMES
CCENV_ENV_NAMES=( default anthropic deepseek openrouter )

# Vars to clear on every switch (keep it minimal)
typeset -a CCENV_MANAGED_VARS
CCENV_MANAGED_VARS=( ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL ANTHROPIC_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_OPUS_MODEL )

# Optional globals applied for every env before the specific env
ccenv_globals() {
  : "${API_TIMEOUT_MS:=600000}"
  export API_TIMEOUT_MS
}

# Apply an environment by name. Return non-zero for unknown.
ccenv_apply_env() {
  case "$1" in
    default)
      # leave everything cleared (baseline)
      return 0
      ;;

    GLM-4.6)
      export ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic"
      export ANTHROPIC_AUTH_TOKEN="sk-glm-api-token"
      export ANTHROPIC_MODEL="GLM-4.6"
      export ANTHROPIC_DEFAULT_HAIKU_MODEL="glm-4.5-air"
      export ANTHROPIC_DEFAULT_SONNET_MODEL="glm-4.6"
      export ANTHROPIC_DEFAULT_OPUS_MODEL="glm-4.6"
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
