# DSH (DeepSeekRuntime) 运行镜像 —— GitHub Actions 云构建版本
# 与宿主 /vol2/1000/docker/dsh/Dockerfile 等价，差别只有两点：
#   1) 版本由构建参数 DSH_VERSION 决定（默认 0.2.3-alpha.2）
#   2) 不含构建期代理（Actions runner 直连 npm / apt）
FROM node:24.22.3-bookworm-slim

ARG DSH_VERSION=0.2.3-alpha.2
ARG DSH_PROFILE=linux
ARG PNPM_VERSION=11.28.5

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    TZ=Asia/Shanghai \
    HOME=/home/dsh \
    DSH_HOME=/home/dsh/.dsh \
    DSH_VERSION=${DSH_VERSION} \
    DSH_PROFILE=${DSH_PROFILE}

# 1) 原生模块编译工具链（node-pty / koffi / sherpa-onnx 等）
# 2) LibreOffice（office 技能：docx/xlsx/pptx/PDF 转换与渲染）
# 3) git / openssh-client（dsh-github-workbench、dsh-ssh）
# 4) 进程工具 + tini
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        python3 \
        python3-pip \
        pkg-config \
        git \
        openssh-client \
        curl \
        ca-certificates \
        procps \
        tini \
        libreoffice-writer \
        libreoffice-calc \
        libreoffice-impress \
        libreoffice-core \
        fonts-noto-cjk \
    && rm -rf /var/lib/apt/lists/*

# 5) 非 root 运行用户（uid/gid 由宿主 compose 的 user: 覆盖，这里只保证目录属主）
RUN useradd -m -d /home/dsh -s /bin/bash dsh \
    && mkdir -p /home/dsh/.dsh /workspace \
    && chown -R dsh:dsh /home/dsh /workspace

# 6) pnpm（profile 用 nodeLinker=hoisted，必须 pnpm）
RUN corepack enable && corepack prepare pnpm@${PNPM_VERSION} --activate

# 7) DSH CLI（版本可替换；engine 要求 node ^24.22.3，基础镜像已对齐）
RUN npm config set fetch-retries 5 \
    && npm config set fetch-retry-mintimeout 20000 \
    && npm config set fetch-retry-maxtimeout 120000 \
    && npm install -g @deepseek-ai/dsh@${DSH_VERSION} \
    && dsh --version

# 8) profile 目录预先就位（宿主挂载会覆盖，这里只保证权限）
RUN mkdir -p /home/dsh/.dsh/profiles/${DSH_PROFILE} \
    && chown -R dsh:dsh /home/dsh/.dsh

# dsh web 拒绝通配地址（--host 0.0.0.0 直接报错退出），必须绑一个具体 IP。
# 容器 IP 每次重建都可能变，所以用入口脚本动态取当前容器 IP 再启动。
RUN printf '%s\n' \
    '#!/bin/sh' \
    'set -e' \
    'PORT="${DSH_PORT:-56870}"' \
    'PROFILE="${DSH_PROFILE:-linux}"' \
    'IP=$(hostname -i | awk "{print \$1}")' \
    'echo "dsh web: profile=${PROFILE} binding ${IP}:${PORT}"' \
    'exec dsh --profile "${PROFILE}" --host "${IP}" --port "${PORT}" --no-open' \
    > /usr/local/bin/dsh-entrypoint.sh && chmod 755 /usr/local/bin/dsh-entrypoint.sh

USER dsh
WORKDIR /workspace

HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=3 \
    CMD curl -fsS "http://127.0.0.1:${DSH_PORT:-56870}/" >/dev/null 2>&1 || exit 1

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/dsh-entrypoint.sh"]
