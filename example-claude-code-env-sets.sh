#!/usr/bin/env bash

# User environment definitions for claude-code-env-switcher
# Replace the placeholder tokens/URLs below with your real values when ready.

# Keep the default environment pointed at Anthropic unless you override it before sourcing.
: "${CLAUDE_ENV_DEFAULT:=anthropic}"

# List available environments (zsh array shown; bash array also works)
typeset -a CCENV_ENV_NAMES
CCENV_ENV_NAMES=( default anthropic GLM-4.7 deepseek openrouter )

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

    anthropic)
      export ANTHROPIC_BASE_URL="https://api.anthropic.com"
      export ANTHROPIC_AUTH_TOKEN="sk-ant-REPLACE_ME"
      ;;

    GLM-4.7)
      export ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic"
      export ANTHROPIC_AUTH_TOKEN="sk-glm-api-token"
      export ANTHROPIC_MODEL="GLM-4.7"
      export ANTHROPIC_DEFAULT_HAIKU_MODEL="GLM-4.5-Air"
      export ANTHROPIC_DEFAULT_SONNET_MODEL="GLM-4.7"
      export ANTHROPIC_DEFAULT_OPUS_MODEL="GLM-4.7"
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
