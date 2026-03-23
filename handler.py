import base64
import json
import os
import random
import time
import urllib.request
import uuid

import runpod

COMFY_URL = os.getenv("COMFY_URL", "http://127.0.0.1:8188")
COMFY_INPUT_DIR = os.getenv("COMFY_INPUT_DIR", "/comfyui/input")
COMFY_OUTPUT_DIR = os.getenv("COMFY_OUTPUT_DIR", "/comfyui/output")
WORKFLOW_PATH = os.getenv("WORKFLOW_PATH", "/workflow_api.json")
COMFY_POLLING_INTERVAL = int(os.getenv("COMFY_POLLING_INTERVAL", "2"))
COMFY_TIMEOUT = int(os.getenv("COMFY_TIMEOUT", "600"))

OUTPUT_NODE_ID = "273"


def queue_prompt(prompt):
    data = json.dumps({"prompt": prompt}).encode("utf-8")
    req = urllib.request.Request(f"{COMFY_URL}/prompt", data=data)
    return json.loads(urllib.request.urlopen(req).read())


def get_history(prompt_id):
    req = urllib.request.Request(f"{COMFY_URL}/history/{prompt_id}")
    return json.loads(urllib.request.urlopen(req).read())


def wait_for_completion(prompt_id):
    elapsed = 0
    while elapsed < COMFY_TIMEOUT:
        history = get_history(prompt_id)
        if prompt_id in history:
            status = history[prompt_id].get("status", {})
            if status.get("completed", False):
                return history[prompt_id]
            if status.get("status_str") == "error":
                raise RuntimeError(
                    f"ComfyUI execution failed: {status.get('messages', '')}"
                )
        time.sleep(COMFY_POLLING_INTERVAL)
        elapsed += COMFY_POLLING_INTERVAL
    raise TimeoutError(f"ComfyUI did not complete within {COMFY_TIMEOUT}s")


def save_input_image(image_b64):
    filename = f"input_{uuid.uuid4().hex}.jpg"
    filepath = os.path.join(COMFY_INPUT_DIR, filename)
    with open(filepath, "wb") as f:
        f.write(base64.b64decode(image_b64))
    return filename, filepath


def build_workflow(input_filename, job_input):
    with open(WORKFLOW_PATH, "r", encoding="utf-8") as f:
        workflow = json.load(f)

    positive_prompt = job_input.get("positive_prompt", "A beautiful landscape in 4k")
    negative_prompt = job_input.get("negative_prompt", "ugly, low resolution, blurry")
    seed = job_input.get("seed", random.randint(1, 999999999999999))
    width = job_input.get("width", 1280)
    height = job_input.get("height", 720)

    workflow["269"]["inputs"]["image"] = input_filename
    workflow["267:266"]["inputs"]["value"] = positive_prompt
    workflow["267:247"]["inputs"]["text"] = negative_prompt
    workflow["267:257"]["inputs"]["value"] = width
    workflow["267:258"]["inputs"]["value"] = height
    workflow["267:216"]["inputs"]["noise_seed"] = seed
    workflow["267:237"]["inputs"]["noise_seed"] = seed

    return workflow


def extract_output(history):
    outputs = history.get("outputs", {})
    node_output = outputs.get(OUTPUT_NODE_ID, {})
    video_list = node_output.get("gifs", []) or node_output.get("images", [])

    if not video_list:
        raise RuntimeError(
            f"ComfyUI finished but no output found in node {OUTPUT_NODE_ID}"
        )

    video_info = video_list[0]
    subfolder = video_info.get("subfolder", "")
    filepath = os.path.join(COMFY_OUTPUT_DIR, subfolder, video_info["filename"])

    if not os.path.exists(filepath):
        raise FileNotFoundError(f"Output file not found: {filepath}")

    with open(filepath, "rb") as f:
        b64_data = base64.b64encode(f.read()).decode("utf-8")

    os.remove(filepath)

    return {
        "filename": video_info["filename"],
        "type": "base64",
        "data": b64_data,
    }


def handler(job):
    job_input = job.get("input", {})
    image_b64 = job_input.get("image")
    input_filepath = None

    try:
        if not image_b64:
            raise ValueError("Missing required field: 'image' (base64 encoded)")

        input_filename, input_filepath = save_input_image(image_b64)
        workflow = build_workflow(input_filename, job_input)
        prompt_res = queue_prompt(workflow)
        history = wait_for_completion(prompt_res["prompt_id"])
        output = extract_output(history)

        return {"images": [output]}

    except Exception as e:
        return {"error": str(e)}

    finally:
        if input_filepath and os.path.exists(input_filepath):
            os.remove(input_filepath)


runpod.serverless.start({"handler": handler})
