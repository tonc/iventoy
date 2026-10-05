# ---------- 第 1 阶段：下载并解压 iVentoy（此阶段不进入最终镜像） ----------
FROM ubuntu:22.04 AS downloader

# 构建参数
# VERSION: iVentoy 版本号（不含 v 前缀），默认 latest 表示自动获取最新版
# GH_PROXY: GitHub 下载加速前缀，例如 https://ghfast.top/
ARG VERSION=latest
ARG GH_PROXY=""
ARG TARGETARCH

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl jq tzdata && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /src

RUN set -eux; \
    ARCH="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "$ARCH" in \
      amd64) ASSET_ARCH='linux-x86_64' ;; \
      arm64) ASSET_ARCH='linux-arm64' ;; \
      *) echo "unsupported arch: $ARCH"; exit 1 ;; \
    esac; \
    if [ "$VERSION" = "latest" ]; then \
      API_URL="https://api.github.com/repos/ventoy/PXE/releases/latest"; \
    else \
      API_URL="https://api.github.com/repos/ventoy/PXE/releases/tags/v${VERSION}"; \
    fi; \
    RESP=$(curl -fsSL --retry 3 --connect-timeout 15 -H "Accept: application/vnd.github+json" "$API_URL"); \
    VER=$(printf '%s' "$RESP" | jq -r '.tag_name' | sed 's/^v//'); \
    if [ -z "$VER" ] || [ "$VER" = "null" ]; then echo "cannot get version"; exit 1; fi; \
    URL=$(printf '%s' "$RESP" | jq -r --arg a "$ASSET_ARCH" \
      '.assets[] | select(.name | test($a)) | select(.name | endswith(".tar.gz")) | .browser_download_url' | head -n1); \
    if [ -z "$URL" ] || [ "$URL" = "null" ]; then echo "no asset found for $ASSET_ARCH"; exit 1; fi; \
    DL_URL="$URL"; \
    if [ -n "$GH_PROXY" ]; then DL_URL="${GH_PROXY}${URL}"; fi; \
    echo "download iVentoy $VER ($ASSET_ARCH): $DL_URL"; \
    curl -fsSL --retry 3 --connect-timeout 15 "$DL_URL" -o /tmp/iventoy.tar.gz; \
    mkdir -p /src/iventoy /src/default; \
    tar -xzf /tmp/iventoy.tar.gz -C /src/iventoy --strip-components=1; \
    rm -f /tmp/iventoy.tar.gz; \
    echo "$VER" > /src/iventoy/version; \
    chmod +x /src/iventoy/iventoy.sh /src/iventoy/lib/iventoy; \
    mkdir -p /src/out; \
    cp -a /src/iventoy /src/out/iventoy; \
    mkdir -p /src/out/iventoy-default; \
    cp -a /src/iventoy/data /src/iventoy/user /src/iventoy/log /src/out/iventoy-default/; \
    echo "iVentoy $VER ready"

# ---------- 第 2 阶段：运行镜像 ----------
FROM ubuntu:22.04

# 镜像标签信息
LABEL maintainer="xkand <tonc@163.com>" \
      org.opencontainers.image.authors="xkand" \
      org.opencontainers.image.title="iVentoy" \
      org.opencontainers.image.description="iVentoy PXE/HTTPBoot server in Docker (auto build from ventoy/PXE releases)" \
      org.opencontainers.image.source="https://github.com/xkand/dind" \
      org.opencontainers.image.url="https://www.iventoy.com" \
      org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Shanghai \
    IVENTOY_HOME=/opt/iventoy \
    AUTO_RUN=0

# 运行镜像不再执行 apt 安装：基础镜像已自带 bash / coreutils / grep(-P) / procps(pgrep)
# 时区文件从下载阶段拷贝，避免为此多装一整层 apt 包
COPY --from=downloader /usr/share/zoneinfo/Asia/Shanghai /usr/share/zoneinfo/Asia/Shanghai
RUN ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone

# 从下载阶段拷贝 iVentoy 及默认数据（不携带 curl / jq / 压缩包等中间产物）
# 使用同一个 COPY，让默认数据与 /opt/iventoy 中的同名文件保持硬链接，避免多存一份
COPY --from=downloader /src/out /opt

COPY start_iventoy.sh /usr/local/bin/start_iventoy.sh
RUN chmod +x /usr/local/bin/start_iventoy.sh && \
    mkdir -p /opt/iventoy/iso

WORKDIR /opt/iventoy

# ISO 目录 / 数据目录 / 日志目录 / 用户文件目录
VOLUME ["/opt/iventoy/iso", "/opt/iventoy/data", "/opt/iventoy/log", "/opt/iventoy/user"]

# 端口说明：
# 26000 TCP  Web 管理界面
# 16000 TCP  PXE 服务 HTTP
# 67/68/69/4011 UDP  DHCP / DHCP Proxy / TFTP
# 10809 TCP  NBD
# 3260  TCP  iSCSI
# 12049 TCP  NFS
# 10445 TCP  SMB
EXPOSE 26000/tcp 16000/tcp 10809/tcp 3260/tcp 12049/tcp 10445/tcp 67/udp 68/udp 69/udp 4011/udp

ENTRYPOINT ["/usr/local/bin/start_iventoy.sh"]
