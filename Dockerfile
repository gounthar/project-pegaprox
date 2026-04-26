FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

# Build stage includes Rust toolchain so cryptography can compile from source
# on architectures without pre-built PyPI wheels (e.g. riscv64)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv \
    gcc cargo rustc \
    libffi-dev libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY requirements.txt .
RUN python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir -r requirements.txt

FROM ubuntu:24.04

LABEL org.label-schema.name="PegaProx"
LABEL org.label-schema.description="Modern Multi-Cluster Management for Proxmox VE"
LABEL org.label-schema.vendor="PegaProx"
LABEL org.label-schema.url="https://pegaprox.com"
LABEL org.label-schema.vcs-url="https://github.com/PegaProx/project-pegaprox"
LABEL maintainer="support@pegaprox.com"

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV PATH="/opt/venv/bin:$PATH"

# Runtime stage: no Rust, only what the app needs at run time
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    libffi8 libssl3 \
    openssh-client sshpass \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN groupadd -r pegaprox && useradd -r -g pegaprox -d /app -s /bin/false pegaprox

# Copy pre-built virtualenv from builder (no Rust carried into runtime image)
COPY --from=builder /opt/venv /opt/venv

WORKDIR /app

COPY --chown=pegaprox:pegaprox pegaprox_multi_cluster.py .
COPY --chown=pegaprox:pegaprox pegaprox/ pegaprox/
COPY --chown=pegaprox:pegaprox web/ web/
COPY --chown=pegaprox:pegaprox static/ static/
COPY --chown=pegaprox:pegaprox images/ images/
COPY --chown=pegaprox:pegaprox version.json .
COPY --chown=pegaprox:pegaprox requirements.txt .
COPY --chown=pegaprox:pegaprox update.sh .

RUN mkdir -p /app/config /app/logs /app/backups \
    && chown -R pegaprox:pegaprox /app

VOLUME ["/app/config", "/app/logs"]

USER pegaprox

EXPOSE 5000 5001 5002

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD python3 -c "import urllib.request; urllib.request.urlopen('https://localhost:5000/api/health', context=__import__('ssl')._create_unverified_context())" || exit 1

ENTRYPOINT ["/opt/venv/bin/python3", "pegaprox_multi_cluster.py"]
