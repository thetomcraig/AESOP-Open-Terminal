FROM ghcr.io/open-webui/open-terminal:slim

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 \
        python3-venv \
    && python3 -m venv /opt/pyjwt \
    && /opt/pyjwt/bin/pip install --no-cache-dir "PyJWT[crypto]" \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid 2000 workspace \
    && usermod -aG workspace user

COPY gitconfig /open-terminal/gitconfig
COPY --chmod=755 git-push-with-token.sh /open-terminal/git-push-with-token.sh

RUN mkdir -p /workspace
RUN git config --system --add safe.directory '/workspace/*'

ENV PATH="/opt/pyjwt/bin:${PATH}"
