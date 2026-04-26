FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive
ENV RUSTUP_HOME=/usr/local/rustup
ENV CARGO_HOME=/usr/local/cargo
ENV PATH=/usr/local/cargo/bin:$PATH

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv python3-dev \
    build-essential pkg-config libffi-dev libssl-dev \
    libjpeg-dev \
    curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Rustup + stable Rust (>=1.85) is required to build cryptography from source
# on riscv64; no PyPI wheel exists for this architecture yet.
#
# CARGO_BUILD_TARGET overrides maturin's faulty triple detection: Python's SOABI
# cpython-312-riscv64-linux-gnu maps to "riscv64-unknown-linux-gnu" in maturin
# but rustup only knows "riscv64gc-unknown-linux-gnu".  Without this override
# maturin prints "Target triple not supported by rustup" and aborts.
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -s -- -y --default-toolchain stable --no-modify-path \
    && rustc --version \
    && cargo --version

ENV CARGO_BUILD_TARGET=riscv64gc-unknown-linux-gnu

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

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    libffi8 libssl3 \
    openssh-client sshpass \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd -r pegaprox && useradd -r -g pegaprox -d /app -s /bin/false pegaprox

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
