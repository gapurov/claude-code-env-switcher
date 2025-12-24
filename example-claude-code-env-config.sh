#!/usr/bin/env bash

# User environment definitions for claude-code-env-switcher.
# Replace the placeholder tokens/URLs in your .env.<provider> files.

# Keep the default environment pointed at Anthropic unless you override it before sourcing.
: "${CLAUDE_ENV_DEFAULT:=anthropic}"

# Optional: override where .env.<provider> files live.
# CCENV_ENV_DIR="$HOME/.claude/envs"

# Example .env.anthropic.example (copy to .env.anthropic):
#   CCENV_DISPLAY_NAME="Anthropic"
#   ANTHROPIC_BASE_URL="https://api.anthropic.com"
#   ANTHROPIC_AUTH_TOKEN="sk-ant-REPLACE_ME"
#
# Example .env.GLM-4.7.example (copy to .env.GLM-4.7):
#   CCENV_DISPLAY_NAME="GLM-4.7"
#   ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic"
#   ANTHROPIC_AUTH_TOKEN="sk-glm-api-token"
#   ANTHROPIC_MODEL="GLM-4.7"
#   ANTHROPIC_DEFAULT_HAIKU_MODEL="GLM-4.5-Air"
#   ANTHROPIC_DEFAULT_SONNET_MODEL="GLM-4.7"
#   ANTHROPIC_DEFAULT_OPUS_MODEL="GLM-4.7"
#
# Example .env.deepseek.example (copy to .env.deepseek):
#   CCENV_DISPLAY_NAME="DeepSeek"
#   ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic"
#   ANTHROPIC_AUTH_TOKEN="sk-deepseek-REPLACE_ME"
#
# Example .env.openrouter.example (copy to .env.openrouter):
#   CCENV_DISPLAY_NAME="OpenRouter"
#   ANTHROPIC_BASE_URL="https://openrouter.ai/api/anthropic"
#   ANTHROPIC_AUTH_TOKEN="sk-or-REPLACE_ME"
#
# Example .env.minimax.example (copy to .env.minimax):
#   CCENV_DISPLAY_NAME="MiniMax"
#   ANTHROPIC_BASE_URL="https://api.minimax.io/anthropic"
#   ANTHROPIC_AUTH_TOKEN="sk-minimax-REPLACE_ME"
#   ANTHROPIC_MODEL="MiniMax-M2.1"
#   ANTHROPIC_SMALL_FAST_MODEL="MiniMax-M2.1"
#   ANTHROPIC_DEFAULT_SONNET_MODEL="MiniMax-M2.1"
#   ANTHROPIC_DEFAULT_OPUS_MODEL="MiniMax-M2.1"
#   ANTHROPIC_DEFAULT_HAIKU_MODEL="MiniMax-M2.1"
#   API_TIMEOUT_MS="3000000"
#   CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

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
