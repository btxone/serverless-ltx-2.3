#!/bin/bash
echo "=== Iniciando Entorno Serverless para LTX 2.3 ==="

# 1. Ejecutar el script de restore_snapshot (si es que instala nodos o hace configuraciones previas)
if [ -f "/app/restore_snapshot.sh" ]; then
    echo "Ejecutando restore_snapshot.sh..."
    bash /app/restore_snapshot.sh
fi

# 2. Iniciar ComfyUI en segundo plano (el '&' al final es obligatorio)
echo "Arrancando ComfyUI localmente..."
cd /app/ComfyUI
python main.py --listen 127.0.0.1 --port 8188 &

# 3. Hacer un "ping" constante hasta que ComfyUI responda que ya cargó
echo "Esperando a que la API de ComfyUI esté online..."
while ! curl -s http://127.0.0.1:8188/system_stats > /dev/null; do
    sleep 2
done
echo "¡ComfyUI está 100% listo y escuchando!"

# 4. Iniciar el Handler de RunPod (SIN '&', este proceso mantiene vivo el contenedor)
echo "Arrancando el RunPod Serverless Handler..."
cd /app
python handler.py