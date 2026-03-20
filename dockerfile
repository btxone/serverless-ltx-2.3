# syntax=docker/dockerfile:1

# Build argument for base image selection
ARG BASE_IMAGE=nvidia/cuda:12.6.3-cudnn-runtime-ubuntu24.04

# Stage 1: Base image with common dependencies
FROM ${BASE_IMAGE} AS base

# Prevents prompts from packages asking for user input during installation
ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_PREFER_BINARY=1
ENV PYTHONUNBUFFERED=1
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

# Instalar dependencias del sistema (ffmpeg es crucial para LTX y SaveVideo)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.12 \
    python3.12-venv \
    git \
    wget \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    ffmpeg \
    && ln -sf /usr/bin/python3.12 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip \
    && apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*



# Install uv
RUN wget -qO- https://astral.sh/uv/install.sh | sh \
    && ln -s /root/.local/bin/uv /usr/local/bin/uv \
    && ln -s /root/.local/bin/uvx /usr/local/bin/uvx \
    && uv venv /opt/venv

# Use the virtual environment
ENV PATH="/opt/venv/bin:${PATH}"

# Install comfy-cli
RUN uv pip install comfy-cli pip setuptools wheel



ARG COMFYUI_VERSION=latest
RUN /usr/bin/yes | comfy --workspace /comfyui install --version "${COMFYUI_VERSION}" --nvidia && \
    rm -rf /root/.cache/pip /root/.cache/uv /comfyui/.git /tmp/* /var/tmp/*

# Crear directorio de trabajo
WORKDIR /comfyui

# Clonar ComfyUI
RUN git clone https://github.com/comfyanonymous/ComfyUI.git

# Instalar dependencias de ComfyUI
RUN pip install --no-cache-dir -r ComfyUI/requirements.txt

# Clonar Custom Nodes necesarios (Ajusta estos según los que tengas instalados en tu local)
WORKDIR /app/ComfyUI/custom_nodes
# Nodo de matemáticas para las dimensiones
RUN git clone https://github.com/evansd/ComfyMath.git
# Nodos de video (SaveVideo)
RUN git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git
# Nodos específicos de LTX Video (si usas uno comunitario, asegúrate de poner la URL correcta aquí)
# RUN git clone https://github.com/.../ComfyUI-LTXVideo.git 

# Instalar dependencias de los custom nodes si existen
RUN find . -maxdepth 2 -name "requirements.txt" -exec pip install --no-cache-dir -r {} \;

# Instalar la librería de RunPod serverless y requests
RUN pip install runpod requests

# Volver al directorio de la app

# Copiar nuestros scripts
COPY src/start.sh /start.sh
COPY handler.py /handler.py
RUN chmod +x /start.sh

# Dar permisos de ejecución
COPY src/extra_model_paths.yaml /comfyui/extra_model_paths.yaml

WORKDIR /
CMD ["/start.sh"]