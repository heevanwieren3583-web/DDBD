#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# 紫微斗数开源排盘（Renhuai123/ziwei-doushu）一键部署 + 后台运行
# 适用：macOS / Linux（Windows 见同目录 README.md）
#
#   bash ziwei.sh          首次：克隆 → 安装依赖 → 构建 → 后台启动
#   bash ziwei.sh help     查看全部命令
# ──────────────────────────────────────────────────────────────
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/Renhuai123/ziwei-doushu.git}"
BRANCH="${BRANCH:-main}"
ZIWEI_DIR="${ZIWEI_DIR:-$HOME/ziwei-doushu}"
PORT="${PORT:-3000}"
HOST="${HOST:-127.0.0.1}"
NPM_REGISTRY="${NPM_REGISTRY:-}"

RUN_DIR="$ZIWEI_DIR/.run"
PID_FILE="$RUN_DIR/server.pid"
LOG_FILE="$RUN_DIR/server.log"
SELF="$0"

export NEXT_TELEMETRY_DISABLED=1

if [ -t 1 ]; then C1=$'\033[1;36m'; C2=$'\033[1;33m'; C3=$'\033[1;31m'; C0=$'\033[0m'; else C1=; C2=; C3=; C0=; fi
say()  { printf '%s[ziwei]%s %s\n' "$C1" "$C0" "$*"; }
warn() { printf '%s[ziwei]%s %s\n' "$C2" "$C0" "$*" >&2; }
die()  { printf '%s[ziwei] 错误：%s%s\n' "$C3" "$C0" "$*" >&2; exit 1; }
has()  { command -v "$1" >/dev/null 2>&1; }

# 浏览器打开用的地址 / 健康检查用的地址
case "$HOST" in
  0.0.0.0|::|127.0.0.1) OPEN_HOST=localhost; CHECK_HOST=127.0.0.1 ;;
  *)                    OPEN_HOST="$HOST";   CHECK_HOST="$HOST" ;;
esac
URL="http://$OPEN_HOST:$PORT"

usage() {
  cat <<EOF
紫微斗数开源排盘 · 一键部署 / 后台运行（macOS / Linux）

用法：bash $SELF [命令]

  (不填) / up   首次自动 克隆→安装依赖→构建，然后后台启动；已在运行则显示状态
  start         后台启动（需已构建）
  stop          停止
  restart       重启
  status        查看是否在运行
  logs [-f]     查看日志（-f 持续跟踪，Ctrl+C 退出）
  update        拉取最新代码 → 停止 → 重新安装构建 → 启动
  check         跑项目自带的类型检查 + 排盘回归测试
  help          显示本帮助

可选环境变量（写在命令前面，如 PORT=3001 bash $SELF）：
  ZIWEI_DIR     代码目录（默认 \$HOME/ziwei-doushu，当前：$ZIWEI_DIR）
  PORT          端口（默认 3000）
  HOST          监听地址（默认 127.0.0.1 仅本机；0.0.0.0 允许同一 Wi-Fi 的手机访问）
  NPM_REGISTRY  npm 镜像（国内慢可用 https://registry.npmmirror.com）
  REPO_URL      仓库地址（默认 GitHub 官方仓库）
  BRANCH        分支（默认 main）
EOF
}

check_env() {
  has node || die "没找到 Node.js。请先安装 Node.js 22 LTS：https://nodejs.org/zh-cn ，装好后重新打开终端再运行。"
  has npm  || die "没找到 npm（通常随 Node.js 一起安装）。"
  node -e 'const [a,b]=process.versions.node.split(".").map(Number);process.exit(a>20||(a===20&&b>=9)?0:1)' \
    || die "Node.js 版本过低（当前 $(node -v)）。Next.js 16 需要 >= 20.9，建议安装 22 LTS。"
}

read_pid() { if [ -f "$PID_FILE" ]; then tr -dc '0-9' < "$PID_FILE"; fi; }

is_running() {
  local pid; pid="$(read_pid)"
  { [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; } || return 1
  has ps || return 0
  # 防止 PID 被系统复用：确认确实是 next 进程
  ps -p "$pid" -o args= 2>/dev/null | grep -q next
}

port_busy() { (exec 3<>"/dev/tcp/$CHECK_HOST/$PORT") >/dev/null 2>&1; }

http_code() {
  if has curl; then
    # --noproxy：开着代理软件（如 Clash）时也直连本机
    curl -s --noproxy '*' -o /dev/null -m 5 -w '%{http_code}' "http://$CHECK_HOST:$PORT/" 2>/dev/null || true
  elif port_busy; then echo 200
  else echo 000
  fi
}

lan_ip() {
  local ip=""
  if has ipconfig; then ip="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"; fi
  if [ -z "$ip" ] && has hostname; then ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"; fi
  printf '%s' "$ip"
}

fetch_code() {
  if [ -d "$ZIWEI_DIR/.git" ]; then
    has git || die "没找到 git。"
    say "拉取最新代码：$ZIWEI_DIR"
    # next build 会自动改写这两个文件，先还原，避免 git pull 报冲突
    local f
    for f in tsconfig.json next-env.d.ts; do git -C "$ZIWEI_DIR" checkout -- "$f" >/dev/null 2>&1 || true; done
    git -C "$ZIWEI_DIR" pull --ff-only \
      || die "git pull 失败（网络问题，或你改过代码）。处理：cd \"$ZIWEI_DIR\" && git status"
  elif [ -f "$ZIWEI_DIR/package.json" ]; then
    say "使用现有代码（不是 git 仓库，跳过更新）：$ZIWEI_DIR"
  elif [ -d "$ZIWEI_DIR" ] && [ -n "$(ls -A "$ZIWEI_DIR" 2>/dev/null)" ]; then
    die "目录已存在且不是本项目：$ZIWEI_DIR 。换一个目录：ZIWEI_DIR=\$HOME/ziwei2 bash $SELF"
  else
    has git || die "没找到 git。请先安装 git；或在 GitHub 项目页 Code → Download ZIP，解压到 $ZIWEI_DIR 后再运行。"
    say "克隆代码：$REPO_URL → $ZIWEI_DIR"
    git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$ZIWEI_DIR" \
      || die "克隆失败（多半是访问 GitHub 的网络问题）。可在 GitHub 项目页 Code → Download ZIP，解压到 $ZIWEI_DIR 后再运行。"
  fi
  mkdir -p "$RUN_DIR"
  # 运行时文件（PID、日志）不进 git
  if [ -d "$ZIWEI_DIR/.git" ]; then
    mkdir -p "$ZIWEI_DIR/.git/info"
    grep -qxF '/.run/' "$ZIWEI_DIR/.git/info/exclude" 2>/dev/null || echo '/.run/' >> "$ZIWEI_DIR/.git/info/exclude"
  fi
}

build_app() {
  cd "$ZIWEI_DIR"
  say "安装依赖（npm ci，严格按 package-lock.json 锁定版本）……"
  npm ci --no-audit --no-fund ${NPM_REGISTRY:+--registry "$NPM_REGISTRY"} \
    || die "依赖安装失败。国内网络可换镜像重试：NPM_REGISTRY=https://registry.npmmirror.com bash $SELF update"
  say "生产构建（next build，约 1 分钟）……"
  npm run build || die "构建失败，请检查上方报错。"
}

cmd_start() {
  if is_running; then say "已经在运行（PID $(read_pid)）→ $URL"; return 0; fi
  [ -f "$ZIWEI_DIR/.next/BUILD_ID" ] || die "还没构建。先运行：bash $SELF"
  if port_busy; then die "端口 $PORT 已被占用。换个端口：PORT=3001 bash $SELF start"; fi
  mkdir -p "$RUN_DIR"
  cd "$ZIWEI_DIR"
  printf '\n===== %s  start  host=%s port=%s =====\n' "$(date '+%F %T')" "$HOST" "$PORT" >> "$LOG_FILE"
  # setsid（Linux）让服务彻底脱离当前终端；macOS 没有 setsid，nohup 已足够
  local launcher=""
  if has setsid; then launcher="setsid"; fi
  $launcher nohup node node_modules/next/dist/bin/next start -H "$HOST" -p "$PORT" >> "$LOG_FILE" 2>&1 < /dev/null &
  echo $! > "$PID_FILE"
  say "后台启动中（PID $(read_pid)），等待就绪……"
  local i ip
  for i in $(seq 1 60); do
    if ! is_running; then tail -n 30 "$LOG_FILE" >&2; die "启动失败，完整日志：$LOG_FILE"; fi
    if [ "$(http_code)" = "200" ]; then
      say "启动成功 → $URL"
      if [ "$HOST" = "0.0.0.0" ]; then
        ip="$(lan_ip)"
        if [ -n "$ip" ]; then say "同一 Wi-Fi 下的手机可访问：http://$ip:$PORT"; fi
      fi
      say "停止：bash $SELF stop    日志：bash $SELF logs"
      return 0
    fi
    sleep 1
  done
  warn "60 秒内首页没返回 200，但进程还在。查看日志：bash $SELF logs"
}

cmd_stop() {
  if ! is_running; then rm -f "$PID_FILE"; say "服务没有在运行。"; return 0; fi
  local pid pgid i
  pid="$(read_pid)"
  pgid="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
  say "停止服务（PID $pid）……"
  # 用 setsid 启动时 PID 就是进程组号：整组结束，不留子进程
  if [ "$pgid" = "$pid" ]; then kill -TERM -- "-$pid" 2>/dev/null || true; else kill -TERM "$pid" 2>/dev/null || true; fi
  for i in $(seq 1 15); do
    if ! kill -0 "$pid" 2>/dev/null; then break; fi
    sleep 1
  done
  if kill -0 "$pid" 2>/dev/null; then warn "15 秒未退出，强制结束"; kill -KILL "$pid" 2>/dev/null || true; fi
  rm -f "$PID_FILE"
  say "已停止。"
}

cmd_status() {
  if is_running; then
    say "运行中（PID $(read_pid)），首页 HTTP $(http_code) → $URL"
  else
    say "未运行。启动：bash $SELF"
  fi
}

cmd_logs() {
  [ -f "$LOG_FILE" ] || die "还没有日志文件：$LOG_FILE"
  if [ "${1:-}" = "-f" ]; then tail -n 50 -f "$LOG_FILE"; else tail -n 100 "$LOG_FILE"; fi
}

cmd_check() {
  [ -d "$ZIWEI_DIR/node_modules" ] || die "还没安装依赖。先运行：bash $SELF"
  cd "$ZIWEI_DIR"
  say "类型检查……";                 npm run typecheck
  say "排盘引擎回归测试（约 1 分钟）……"; npm test
  say "类型检查 + 回归测试全部通过。"
}

cmd_up() {
  check_env
  if is_running; then cmd_status; return 0; fi
  if [ ! -f "$ZIWEI_DIR/.next/BUILD_ID" ] || [ ! -d "$ZIWEI_DIR/node_modules" ]; then
    fetch_code
    build_app
  fi
  cmd_start
}

cmd_update() {
  check_env
  fetch_code   # 先拉代码：网络失败时服务不受影响
  cmd_stop     # npm ci 会删掉 node_modules，必须先停
  build_app
  cmd_start
}

cmd="${1:-up}"
if [ $# -gt 0 ]; then shift; fi
case "$cmd" in
  up)             cmd_up ;;
  start)          check_env; cmd_start ;;
  stop)           cmd_stop ;;
  restart)        check_env; cmd_stop; cmd_start ;;
  status)         cmd_status ;;
  logs)           cmd_logs "${1:-}" ;;
  update)         cmd_update ;;
  check)          check_env; cmd_check ;;
  help|-h|--help) usage ;;
  *)              usage; exit 1 ;;
esac
