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
ARG COMFYUI_COMMIT=b53b10ea61ef7fc54fbde7c1e7b7c36565bacf82
RUN /usr/bin/yes | comfy --workspace /comfyui install --version "${COMFYUI_VERSION}" --nvidia \
    && git -C /comfyui fetch --depth 1 origin "${COMFYUI_COMMIT}" \
    && git -C /comfyui checkout --detach "${COMFYUI_COMMIT}" \
    && uv pip install --no-cache-dir -r /comfyui/requirements.txt \
    && rm -rf /root/.cache/pip /root/.cache/uv /comfyui/.git /tmp/* /var/tmp/*

WORKDIR /comfyui/custom_nodes
ARG COMFYMATH_COMMIT=c01177221c31b8e5fbc062778fc8254aeb541638
ARG VIDEO_HELPER_SUITE_COMMIT=449839959f0153fb8a57211a9364c55163935ca9
ARG KJNODES_COMMIT=7519171dd6b6ccea43091c6b73e42443bba11f5b
RUN git clone https://github.com/evanspearman/ComfyMath.git ComfyMath \
    && git -C ComfyMath checkout --detach "${COMFYMATH_COMMIT}" \
    && git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git ComfyUI-VideoHelperSuite \
    && git -C ComfyUI-VideoHelperSuite checkout --detach "${VIDEO_HELPER_SUITE_COMMIT}" \
    && git clone https://github.com/kijai/ComfyUI-KJNodes.git ComfyUI-KJNodes \
    && git -C ComfyUI-KJNodes checkout --detach "${KJNODES_COMMIT}" \
    && find . -maxdepth 2 -name "requirements.txt" -exec uv pip install --no-cache-dir -r {} \; \
    && rm -rf ComfyMath/.git ComfyUI-VideoHelperSuite/.git ComfyUI-KJNodes/.git

RUN uv pip install runpod requests

COPY src/extra_model_paths.yaml /comfyui/extra_model_paths.yaml
COPY src/start.sh /start.sh
COPY handler.py /handler.py
COPY workflow_api.json /workflow_api.json

RUN chmod +x /start.sh

WORKDIR /
CMD ["/start.sh"]
