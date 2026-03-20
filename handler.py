import runpod
import json
import urllib.request
import urllib.parse
import time
import base64
import os
import random
import uuid

# URL local de ComfyUI
COMFY_URL = "http://127.0.0.1:8188"
COMFY_INPUT_DIR = "/app/ComfyUI/input"
COMFY_OUTPUT_DIR = "/app/ComfyUI/output"

def queue_prompt(prompt):
    p = {"prompt": prompt}
    data = json.dumps(p).encode('utf-8')
    req = urllib.request.Request(f"{COMFY_URL}/prompt", data=data)
    response = urllib.request.urlopen(req)
    return json.loads(response.read())

def get_history(prompt_id):
    req = urllib.request.Request(f"{COMFY_URL}/history/{prompt_id}")
    response = urllib.request.urlopen(req)
    return json.loads(response.read())

def handler(job):
    job_input = job.get("input", {})
    
    # 1. Extraer variables del payload
    image_b64 = job_input.get("image", None)
    positive_prompt = job_input.get("positive_prompt", "Un hermoso paisaje en 4k")
    negative_prompt = job_input.get("negative_prompt", "feo, baja resolucion, desenfocado")
    seed = job_input.get("seed", None)
    video_width = job_input.get("width", 1280)
    video_height = job_input.get("height", 720)
    
    # Generar un seed aleatorio si no se proporciona
    if seed is None:
        seed = random.randint(1, 999999999999999)
        
    final_result = {}
    output_data = []
    errors = []

    try:
        # 2. Procesar la imagen de entrada (Base64 a archivo físico)
        if not image_b64:
            raise ValueError("No se proporcionó la imagen inicial en base64 ('image').")
        
        # Generar nombre único para la imagen de entrada para evitar choques
        input_filename = f"input_{uuid.uuid4().hex}.jpg"
        input_path = os.path.join(COMFY_INPUT_DIR, input_filename)
        
        with open(input_path, "wb") as fh:
            fh.write(base64.b64decode(image_b64))

        # 3. Cargar y modificar el workflow JSON
        with open("workflow_api.json", "r", encoding="utf-8") as f:
            workflow = json.load(f)

        # MAPEO DE NODOS SEGÚN TU JSON:
        # Imagen de entrada
        workflow["269"]["inputs"]["image"] = input_filename
        
        # Prompts
        workflow["267:266"]["inputs"]["value"] = positive_prompt
        workflow["267:247"]["inputs"]["text"] = negative_prompt
        
        # Dimensiones
        workflow["267:257"]["inputs"]["value"] = video_width
        workflow["267:258"]["inputs"]["value"] = video_height
        
        # Semillas (hay dos nodos de ruido en tu JSON)
        workflow["267:216"]["inputs"]["noise_seed"] = seed
        workflow["267:237"]["inputs"]["noise_seed"] = seed

        # 4. Enviar a ComfyUI y esperar
        prompt_res = queue_prompt(workflow)
        prompt_id = prompt_res['prompt_id']
        
        # Polling para saber cuándo termina (Revisar history)
        history = {}
        while True:
            history_res = get_history(prompt_id)
            if prompt_id in history_res:
                history = history_res[prompt_id]
                break
            time.sleep(2) # Esperar 2 segundos antes de volver a preguntar
            
        # 5. Recuperar el archivo generado
        # El nodo 273 (SaveVideo) guarda el archivo. ComfyUI reporta esto en 'outputs'
        outputs = history.get('outputs', {})
        node_output = outputs.get("273", {})
        
        # Buscar en gifs/videos
        video_info_list = node_output.get("gifs", []) or node_output.get("images", [])
        
        if not video_info_list:
            raise Exception("ComfyUI terminó pero no se encontró la salida del video en el nodo 273.")

        # Tomar el primer video generado
        video_info = video_info_list[0]
        output_filename = video_info['filename']
        subfolder = video_info.get('subfolder', '')
        
        # Ruta física del archivo generado
        file_path = os.path.join(COMFY_OUTPUT_DIR, subfolder, output_filename)
        
        if not os.path.exists(file_path):
            raise FileNotFoundError(f"No se encontró el archivo generado en: {file_path}")

        # 6. Convertir a Base64 y armar la respuesta pedida
        with open(file_path, "rb") as f:
            item_bytes = f.read()
            
        base64_data = base64.b64encode(item_bytes).decode("utf-8")
        
        output_data.append({
            "filename": output_filename,
            "type": "base64",
            "data": base64_data,
        })
        
        # Limpieza (opcional): borrar la imagen de entrada para no llenar el disco
        if os.path.exists(input_path):
            os.remove(input_path)
            
    except Exception as e:
        errors.append(str(e))

    # 7. Lógica de retorno exacta que solicitaste
    if output_data:
        final_result["images"] = output_data # Mantenemos la key "images" como pediste, aunque sea un video mp4
    
    if errors:
        final_result["errors"] = errors

    if not output_data and errors:
        return {
            "error": "Job processing failed",
            "details": errors,
        }
    elif not output_data and not errors:
        final_result["status"] = "success_no_images"
        final_result["images"] = []
        
    print(f"worker-comfyui - Job completed. Returning {len(output_data)} file(s).")
    return final_result

# Iniciar el worker de RunPod
runpod.serverless.start({"handler": handler})