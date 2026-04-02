FROM alpine:latest

RUN apk add --no-cache \
    # ── Core shell ──────────────────────────────
    bash curl wget \
    # ── Docker ──────────────────────────────────
    docker-cli docker-cli-compose \
    # ── Text editors ────────────────────────────
    vim nano \
    # ── File & text processing ──────────────────
    jq less grep sed gawk tar zip unzip \
    # ── Process / system ────────────────────────
    htop procps shadow \
    # ── Network debug ───────────────────────────
    iputils-ping \
    bind-tools \
    netcat-openbsd \
    openssh-client \
    # ── Dev runtimes ────────────────────────────
    nodejs npm \
    python3 py3-pip \
    git \
    # ── Timezone ────────────────────────────────
    tzdata

ENV TZ=Asia/Ho_Chi_Minh
