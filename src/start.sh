#!/bin/bash
set -e

echo "worker-comfyui: starting environment"

if [ -f "/restore_snapshot.sh" ]; then
    bash /restore_snapshot.sh
fi

echo "worker-comfyui: launching ComfyUI"
python /comfyui/main.py \
    --listen 127.0.0.1 \
    --port 8188 \
    --extra-model-paths-config /comfyui/extra_model_paths.yaml &

echo "worker-comfyui: waiting for API readiness"
until curl -sf http://127.0.0.1:8188/system_stats > /dev/null 2>&1; do
    sleep 2
done
echo "worker-comfyui: ComfyUI ready"

echo "worker-comfyui: starting RunPod handler"
python /handler.py
