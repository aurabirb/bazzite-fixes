#!/bin/bash
# Installs the `llm` command, which runs a local LLM (llama.cpp server in a
# CUDA podman container) with the model stored on SSD2TB instead of the
# system drive. Only the container image (~4.4 GB) lands on /var.
# Usage after install: llm start|stop|status|logs|download

set -euo pipefail

DEST="$HOME/.local/bin/llm"

mkdir -p "$(dirname "$DEST")"
cat > "$DEST" << 'EOF'
#!/bin/bash
# Local LLM via llama.cpp. Web UI + OpenAI-compatible API on http://localhost:8080
set -euo pipefail

MODELS_DIR="${LLM_MODELS_DIR:-/run/media/user/SSD2TB/llm/models}"
MODEL="${LLM_MODEL:-Qwen3.6-35B-A3B-UD-Q4_K_M.gguf}"
MODEL_URL="https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF/resolve/main/$MODEL"
IMAGE="ghcr.io/ggml-org/llama.cpp:server-cuda"
NAME="llm"
# MoE layers whose experts stay in system RAM. With 64K context and 4096-token
# batches, 20 leaves ~1.8 GB VRAM free: ~1270 tok/s prompt, ~50-60 tok/s output.
# Big batches matter for agents (Hermes sends a ~12K-token system prompt):
# the default 512 batch only manages ~300 tok/s prompt processing.
CPU_MOE="${LLM_CPU_MOE:-20}"
BATCH="${LLM_BATCH:-4096}"
CTX="${LLM_CTX:-65536}"

case "${1:-}" in
    download)
        mkdir -p "$MODELS_DIR"
        curl -L --fail -C - -o "$MODELS_DIR/$MODEL" "$MODEL_URL"
        ;;
    start)
        [[ -f "$MODELS_DIR/$MODEL" ]] || { echo "Model missing, run: llm download" >&2; exit 1; }
        podman rm -f "$NAME" >/dev/null 2>&1 || true
        podman run -d --name "$NAME" --device nvidia.com/gpu=all \
            --security-opt=label=disable -p 127.0.0.1:8080:8080 \
            -v "$MODELS_DIR":/models:ro "$IMAGE" \
            -m "/models/$MODEL" --alias qwen3.6 -ngl 99 --n-cpu-moe "$CPU_MOE" -c "$CTX" \
            -b "$BATCH" -ub "$BATCH" -fa on -ctk q8_0 -ctv q8_0 --jinja --host 0.0.0.0 --port 8080 >/dev/null
        echo -n "Loading model"
        until curl -sf localhost:8080/health >/dev/null; do
            podman ps -q -f name="^$NAME$" | grep -q . || { echo; podman logs "$NAME" 2>&1 | tail -5; exit 1; }
            echo -n .; sleep 2
        done
        echo; echo "Ready: http://localhost:8080"
        ;;
    stop) podman rm -f "$NAME" >/dev/null && echo "Stopped (VRAM freed)" ;;
    status) podman ps -f name="^$NAME$" --format '{{.Status}}'; nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader ;;
    logs) podman logs -f "$NAME" ;;
    *) echo "Usage: llm start|stop|status|logs|download" >&2; exit 1 ;;
esac
EOF
chmod +x "$DEST"
podman pull -q ghcr.io/ggml-org/llama.cpp:server-cuda >/dev/null
echo "  llm command installed to $DEST."
echo "  Run 'llm download' once, then 'llm start'."
