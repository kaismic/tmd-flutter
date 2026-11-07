ARG BASE_IMAGE=python:3.12.16-slim
FROM ${BASE_IMAGE}
COPY tools/requirements.txt /tmp/detector-requirements.txt
RUN pip install --no-cache-dir -r /tmp/detector-requirements.txt
ENTRYPOINT ["python", "/workspace/apps/transport-mode-detector/tools/prepare_models.py"]
