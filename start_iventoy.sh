#!/bin/bash
set -u

IVENTOY_HOME="${IVENTOY_HOME:-/opt/iventoy}"
AUTO_RUN="${AUTO_RUN:-0}"
PID_FILE=/var/run/iventoy.pid

cd "$IVENTOY_HOME" || exit 1

# 优雅停止
stop_iventoy() {
  echo "[iVentoy] 收到停止信号，正在停止服务..."
  bash "$IVENTOY_HOME/iventoy.sh" stop 2>/dev/null || true
  exit 0
}
trap stop_iventoy INT TERM

# 首次挂载空目录时，用镜像内置默认文件初始化
for d in data user log; do
  SRC="/opt/iventoy-default/$d"
  DST="$IVENTOY_HOME/$d"
  mkdir -p "$DST"
  if [ -d "$SRC" ] && [ -z "$(ls -A "$DST" 2>/dev/null)" ]; then
    cp -a "$SRC/." "$DST/"
  fi
done
mkdir -p "$IVENTOY_HOME/iso"

rm -f "$PID_FILE"

ARGS=()
if [ "$AUTO_RUN" = "1" ] || [ "$AUTO_RUN" = "true" ]; then
  ARGS+=("-R")
fi

echo "═══════════════════════════════════════════════════════════════"
echo "                    🐳 iVentoy PXE 服务 🐳"
echo ""
echo "  版本: $(cat "$IVENTOY_HOME/version" 2>/dev/null || echo unknown)"
echo "  ISO 目录: $IVENTOY_HOME/iso"
echo "  自动启动 PXE 服务: ${AUTO_RUN} (AUTO_RUN=1 时生效)"
echo ""
echo "  服务启动后请浏览器访问: http://<服务器IP>:26000"
echo "═══════════════════════════════════════════════════════════════"

bash "$IVENTOY_HOME/iventoy.sh" "${ARGS[@]}" -R start

# iVentoy 是先 fork 到后台、稍后才写 pid 文件，这里需要等待
get_pid() {
  local p=""
  if [ -s "$PID_FILE" ]; then
    p=$(tr -dc '0-9' < "$PID_FILE")
    if [ -n "$p" ] && [ ! -e "/proc/$p" ]; then p=""; fi
  fi
  if [ -z "$p" ]; then
    p=$(pgrep -f "$IVENTOY_HOME/lib/iventoy" | head -n1)
  fi
  echo "$p"
}

PID=""
for _ in $(seq 1 20); do
  PID=$(get_pid)
  [ -n "$PID" ] && break
  sleep 1
done

if [ -z "$PID" ]; then
  echo "[iVentoy] ❌ 启动失败，未检测到 iVentoy 进程。最近日志："
  tail -n 20 "$IVENTOY_HOME/log/log.txt" 2>/dev/null
  echo "[iVentoy] 提示：iVentoy 需要挂载 ISO 文件，容器必须带 SYS_ADMIN 权限（--cap-add SYS_ADMIN 或 --privileged）"
  exit 1
fi

echo "[iVentoy] ✅ 已启动，PID=$PID"

# 保持容器前台运行，并监控 iVentoy 进程
while true; do
  PID=$(get_pid)
  if [ -z "$PID" ]; then
    echo "[iVentoy] ❌ 进程已退出，容器即将停止"
    tail -n 20 "$IVENTOY_HOME/log/log.txt" 2>/dev/null
    exit 1
  fi
  sleep 5 &
  wait $!
done
