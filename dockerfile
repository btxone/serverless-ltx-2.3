# syntax=docker/dockerfile:1

ARG BASE_IMAGE=nvidia/cuda:12.6.3-cudnn-runtime-ubuntu24.04
FROM ${BASE_IMAGE} AS base

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_PREFER_BINARY=1 \
    PYTHONUNBUFFERED=1 \
    CMAKE_BUILD_PARALLEL_LEVEL=8

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.12 \
    python3.12-venv \
    git \
    wget \
    curl \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    ffmpeg \
    && ln -sf /usr/bin/python3.12 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip \
    && apt-get autoremove -y && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN wget -qO- https://astral.sh/uv/install.sh | sh \
    && ln -s /root/.local/bin/uv /usr/local/bin/uv \
    && ln -s /root/.local/bin/uvx /usr/local/bin/uvx \
    && uv venv /opt/venv

ENV PATH="/opt/venv/bin:${PATH}"

RUN uv pip install comfy-cli pip setuptools wheel

ARG COMFYUI_VERSION=latest
RUN /usr/bin/yes | comfy --workspace /comfyui install --version "${COMFYUI_VERSION}" --nvidia \
    && rm -rf /root/.cache/pip /root/.cache/uv /comfyui/.git /tmp/* /var/tmp/*

WORKDIR /comfyui/custom_nodes
RUN git clone https://github.com/evansd/ComfyMath.git \
    && git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git \
    && find . -maxdepth 2 -name "requirements.txt" -exec uv pip install --no-cache-dir -r {} \;

RUN uv pip install runpod requests

COPY src/extra_model_paths.yaml /comfyui/extra_model_paths.yaml
COPY src/start.sh /start.sh
COPY handler.py /handler.py
COPY workflow_api.json /workflow_api.json

RUN chmod +x /start.sh

WORKDIR /
CMD ["/start.sh"]
