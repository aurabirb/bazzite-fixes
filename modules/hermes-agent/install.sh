#!/bin/bash
# Installs Nous Research's Hermes Agent into ~/.hermes, preconfigured for:
#   - DeepSeek V4.1-Flash (default) and V4-Pro, key read from ~/.deepseek
#   - local Qwen3.6 via the local-llm module (http://localhost:8080, `llm start`)
# Switch inside a session with /model, e.g. /model custom:local:qwen3.6
# The official installer keeps an existing ~/.hermes/.env and config.yaml.

set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
KEY_FILE="$HOME/.deepseek"

mkdir -p "$HERMES_HOME"

if ! grep -qs '^DEEPSEEK_API_KEY=' "$HERMES_HOME/.env"; then
    [[ -f "$KEY_FILE" ]] || { echo "  $KEY_FILE missing (put your DeepSeek API key there)" >&2; exit 1; }
    ( umask 077; echo "DEEPSEEK_API_KEY=$(tr -d '[:space:]' < "$KEY_FILE")" >> "$HERMES_HOME/.env" )
    echo "  DeepSeek key added to $HERMES_HOME/.env"
fi

if [[ ! -f "$HERMES_HOME/config.yaml" ]]; then
    cat > "$HERMES_HOME/config.yaml" << 'EOF'
model:
  provider: deepseek
  default: deepseek-flash

providers:
  local:
    api: http://localhost:8080/v1
    transport: chat_completions

fallback_providers:
  - provider: deepseek
    model: deepseek-v4-pro
  - provider: custom:local
    model: qwen3.6
EOF
    echo "  Wrote $HERMES_HOME/config.yaml"
fi

if ! command -v hermes >/dev/null 2>&1 && [[ ! -x "$HERMES_HOME/hermes-agent/hermes" ]]; then
    curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-setup
fi
echo "  Run 'hermes' to start. Models: deepseek-flash (default), deepseek-v4-pro,"
echo "  custom:local:qwen3.6 (needs 'llm start')."
