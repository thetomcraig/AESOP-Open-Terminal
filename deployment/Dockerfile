FROM ghcr.io/open-webui/open-terminal:slim

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 \
        python3-venv \
    && python3 -m venv /opt/pyjwt \
    && /opt/pyjwt/bin/pip install --no-cache-dir "PyJWT[crypto]" \
    && rm -rf /var/lib/apt/lists/*

ENV PATH="/opt/pyjwt/bin:${PATH}"

