#!/usr/bin/env bash

# User environment definitions for claude-code-env-switcher.
# Replace the placeholder tokens/URLs in your .env.cc.<provider> files.

# Keep the default environment pointed at Anthropic unless you override it before sourcing.
: "${CLAUDE_ENV_DEFAULT:=anthropic}"

# Optional: override where .env.cc files live.
# CCENV_ENV_DIR="$HOME/.claude/envs"

# Optional base files: .env (only if it contains CCENV_ or ANTHROPIC_ vars),
# then .env.cc (applied for every env).
#
# Example .env.cc.anthropic.example (copy to .env.cc.anthropic):
#   CCENV_DISPLAY_NAME="Anthropic"
#   ANTHROPIC_BASE_URL="https://api.anthropic.com"
#   ANTHROPIC_AUTH_TOKEN="sk-ant-REPLACE_ME"
#
# Example .env.cc.GLM-4.7.example (copy to .env.cc.GLM-4.7):
#   CCENV_DISPLAY_NAME="GLM-4.7"
#   ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic"
#   ANTHROPIC_AUTH_TOKEN="sk-glm-api-token"
#   ANTHROPIC_MODEL="GLM-4.7"
#   ANTHROPIC_DEFAULT_HAIKU_MODEL="GLM-4.5-Air"
#   ANTHROPIC_DEFAULT_SONNET_MODEL="GLM-4.7"
#   ANTHROPIC_DEFAULT_OPUS_MODEL="GLM-4.7"
#
# Example .env.cc.deepseek.example (copy to .env.cc.deepseek):
#   CCENV_DISPLAY_NAME="DeepSeek"
#   ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic"
#   ANTHROPIC_AUTH_TOKEN="sk-deepseek-REPLACE_ME"
#
# Example .env.cc.minimax.example (copy to .env.cc.minimax):
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
