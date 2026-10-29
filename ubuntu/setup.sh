#!/usr/bin/env bash
# 可重复执行的 Ubuntu 安装脚本。
# 状态：${XDG_STATE_HOME:-$HOME/.local/state}/ubuntu-setup/state.tsv
# 已成功的步骤会跳过，失败的步骤下次重试。
# 软失败继续后面的步骤；只有声明了依赖的步骤会被挡住。
# 非交互时可用 SETUP_GITHUB_MIRROR=1|0、SETUP_APT_MIRROR=1|0、SETUP_APT_SOURCE=域名、SETUP_SSH_KEY=1|0。
# 单命令安装：
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/mogeku/script/master/ubuntu/setup.sh)"
# 仓库固定在 ~/script。脚本里用到仓库文件时直接写这个路径。
# 直接执行：~/script/ubuntu/setup.sh  开头会 sudo 问一次密码。
# 安装结束后把登录 shell 改成 zsh，并在当前终端进入 zsh 加载 ~/.zshrc。
# SETUP_FORCE=1 忽略已成功记录，全部重跑（步骤本身仍然幂等）。
# setup.sh uninstall  卸掉本脚本装上的组件，恢复软件源和 shell 链接。
# setup.sh clear      清空已保存的选择，下次安装重新询问。
# setup.sh -h         查看支持的命令。

set -o pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/ubuntu-setup"
STATE_FILE="$STATE_DIR/state.tsv"
LOG_FILE="$STATE_DIR/setup.log"
CHOICE_FILE="$STATE_DIR/choices.env"
APT_BACKUP="$STATE_DIR/apt-backup"
CONFIG_BACKUP="$STATE_DIR/config-backup"
CONFIG_MANIFEST="$CONFIG_BACKUP/manifest.tsv"

export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
export NEEDRESTART_MODE=l
export GIT_TERMINAL_PROMPT=0
export APT_LISTCHANGES_FRONTEND=none

APT_OPTS=(
  -o Dpkg::Options::=--force-confdef
  -o Dpkg::Options::=--force-confold
  -o Dpkg::Use-Pty=0
)

USE_GITHUB_MIRROR=0
USE_APT_MIRROR=0
ACTION=install
github_repo="github.com"
github_raw="raw.githubusercontent.com"
step_note=""
STEP_TAG=""

declare -a STEP_IDS=()
declare -a OK_IDS=() FAIL_IDS=() SKIP_IDS=()
declare -A STEP_TITLE=() STEP_DEPS=() STEP_FN=()
declare -A STEP_STATUS=() STEP_SHOWN=()
declare -A SAVED_STATUS=() SAVED_NOTE=()

# 颜色只在交互终端启用。NO_COLOR=1 或重定向到文件时退回纯文本。
RESET="" BOLD="" DIM=""
GREEN="" RED="" YELLOW="" CYAN="" BLUE="" PURPLE=""
BOLD_GREEN="" BOLD_RED="" BOLD_YELLOW="" BOLD_CYAN="" BOLD_BLUE="" BOLD_PURPLE=""
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RESET=$'\033[0m'
  BOLD=$'\033[1m'
  DIM=$'\033[2m'
  GREEN=$'\033[32m'
  RED=$'\033[31m'
  YELLOW=$'\033[33m'
  CYAN=$'\033[36m'
  BLUE=$'\033[34m'
  PURPLE=$'\033[35m'
  BOLD_GREEN=$'\033[1;32m'
  BOLD_RED=$'\033[1;31m'
  BOLD_YELLOW=$'\033[1;33m'
  BOLD_CYAN=$'\033[1;36m'
  BOLD_BLUE=$'\033[1;34m'
  BOLD_PURPLE=$'\033[1;35m'
fi
# 旧名字。步骤前缀和命令回显还在用。
C_OFF=$RESET
C_BOLD=$BOLD
C_DIM=$DIM
C_OK=$GREEN
C_FAIL=$RED
C_SKIP=$YELLOW
C_TAG=$CYAN

# 只用 East Asian Width = Wide 的字符，和下面的列宽计算一致。
EMOJI_ROCKET="🚀"
EMOJI_PKG="📦"
EMOJI_GEAR="🔧"
EMOJI_SUCCESS="✅"
EMOJI_ERROR="❌"
EMOJI_CHECK="🔍"
EMOJI_WARN="❗"
EMOJI_LOCK="🔒"
EMOJI_SKIP="➖"
EMOJI_WAIT="⏳"
EMOJI_CLEAN="🧹"
EMOJI_NOTE="📝"
EMOJI_LIST="📋"
EMOJI_DIR="📁"
EMOJI_WEB="🌐"
EMOJI_SPARK="✨"
EMOJI_PARTY="🎉"

log() {
  printf '%s  %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE"
}

# fd=1 给正常流程，fd=2 给锁冲突和参数错误。
_ui() {
  local fd=$1 color=$2 icon=$3
  shift 3
  printf '%s%s%s %s\n' "$color" "$icon" "$RESET" "$*" >&"$fd"
}

log_info() { _ui 1 "$BOLD_CYAN" "$EMOJI_CHECK" "$@"; }
log_success() { _ui 1 "$BOLD_GREEN" "$EMOJI_SUCCESS" "$@"; }
log_warn() { _ui 1 "$BOLD_YELLOW" "$EMOJI_WARN" "$@"; }
log_error() { _ui 1 "$BOLD_RED" "$EMOJI_ERROR" "$@"; }
log_warn_err() { _ui 2 "$BOLD_YELLOW" "$EMOJI_WARN" "$@"; }
log_error_err() { _ui 2 "$BOLD_RED" "$EMOJI_ERROR" "$@"; }

step_say() {
  if [[ -n $STEP_TAG ]]; then
    printf '  %s%s%s%s %s\n' "$DIM" "$CYAN" "$STEP_TAG" "$RESET" "$*"
  else
    printf '  %s\n' "$*"
  fi
}

rule() {
  local width=${1:-62} line
  printf -v line '%*s' "$width" ''
  line=${line// /─}
  printf '%s%s%s\n' "$PURPLE" "$line" "$RESET"
}

print_banner() {
  local title=$1 sub=${2:-}
  printf '\n'
  rule
  printf '  %s%s%s  %s%s%s\n' "$BOLD_PURPLE" "$EMOJI_ROCKET" "$RESET" "$BOLD" "$title" "$RESET"
  if [[ -n $sub ]]; then
    printf '  %s%s%s\n' "$DIM" "$sub" "$RESET"
  fi
  rule
}

# 终端列宽。中文和上面列出的符号按 2 列计，变体选择符不计宽度。
disp_width() {
  local s=$1 i ch w=0
  s=${s//$'\uFE0E'/}
  s=${s//$'\uFE0F'/}
  s=${s//$'\u200D'/}
  for ((i = 0; i < ${#s}; i++)); do
    ch=${s:i:1}
    if [[ $ch == [[:ascii:]] ]]; then
      w=$((w + 1))
    else
      w=$((w + 2))
    fi
  done
  printf '%s' "$w"
}

pad_col() {
  local s=$1 width=$2 w pad
  w=$(disp_width "$s")
  if ((w >= width)); then
    printf '%s' "$s"
    return
  fi
  pad=$((width - w))
  printf '%s%*s' "$s" "$pad" ""
}

sgr_reset() {
  [[ -t 1 ]] && printf '\033[0m'
}

# 工具输出按行（以及 \r 进度）加上当前步骤名。结束时强制换行并复位颜色。日志里仍是原文。
step_prefix() {
  if [[ -z $STEP_TAG ]]; then
    cat
    return
  fi
  local prefix="  ${C_DIM}${C_TAG}${STEP_TAG}${C_OFF} "
  if command -v perl >/dev/null 2>&1; then
    STEP_PREFIX=$prefix perl -e '
      use strict;
      binmode STDIN;
      binmode STDOUT;
      my $prefix = $ENV{STEP_PREFIX};
      my $pending = 1;
      my $last_nl = 1;
      while (1) {
        my $n = sysread STDIN, my $chunk, 8192;
        last if !$n;
        my $out = "";
        for my $b (split //, $chunk) {
          if ($b eq "\n") {
            $out .= "\033[0m\n";
            $pending = 1;
            $last_nl = 1;
            next;
          }
          if ($b eq "\r") {
            $out .= "\r\033[K";
            $pending = 1;
            $last_nl = 0;
            next;
          }
          if ($pending) { $out .= $prefix; $pending = 0; }
          $out .= $b;
          $last_nl = 0;
        }
        syswrite STDOUT, $out;
      }
      syswrite STDOUT, "\033[0m\n" if !$last_nl;
    '
    return
  fi
  awk -v p="$prefix" '{
    n = split($0, a, "\r")
    for (i = 1; i <= n; i++) {
      if (i > 1) printf "\r\033[K"
      printf "%s%s", p, a[i]
    }
    printf "\033[0m\n"
    fflush()
  }'
}

sanitize() {
  printf '%s' "$1" | tr '\t\r\n' '   '
}

add_step() {
  local id=$1 title=$2 deps=$3 fn=$4
  STEP_IDS+=("$id")
  STEP_TITLE["$id"]=$title
  STEP_DEPS["$id"]=$deps
  STEP_FN["$id"]=$fn
}

state_load() {
  [[ -f $STATE_FILE ]] || return 0
  local id status note ts
  while IFS=$'\t' read -r id status note ts; do
    [[ -z $id || $id == \#* ]] && continue
    SAVED_STATUS["$id"]=$status
    SAVED_NOTE["$id"]=$note
  done <"$STATE_FILE"
}

state_flush() {
  local tmp id
  tmp=$(mktemp "$STATE_DIR/state.tsv.XXXXXX")
  {
    printf '# id\tstatus\tnote\ttime\n'
    for id in "${!SAVED_STATUS[@]}"; do
      [[ ${SAVED_STATUS[$id]} == ok || ${SAVED_STATUS[$id]} == fail ]] || continue
      printf '%s\t%s\t%s\t%s\n' \
        "$id" \
        "${SAVED_STATUS[$id]}" \
        "$(sanitize "${SAVED_NOTE[$id]}")" \
        "$(date -Iseconds)"
    done
  } >"$tmp"
  mv "$tmp" "$STATE_FILE"
}

state_set() {
  SAVED_STATUS["$1"]=$2
  SAVED_NOTE["$1"]=$(sanitize "$3")
  state_flush
}

root_ok() {
  [[ $(id -u) -eq 0 ]] && return 0
  sudo -n true 2>/dev/null
}

as_root() {
  if [[ $1 == apt-get ]]; then
    wait_apt_lock || return 1
  fi
  if [[ $(id -u) -eq 0 ]]; then
    "$@"
    return
  fi
  if ! sudo -n true 2>/dev/null; then
    step_note="sudo 未通过"
    return 1
  fi
  sudo "$@" </dev/null &
  ROOT_PID=$!
  wait "$ROOT_PID"
  local rc=$?
  ROOT_PID=""
  return "$rc"
}

# 锁文件是 root:640，普通用户的 fuser 看不到占用者。/proc/locks 对所有人可读。
apt_lock_pids() {
  local inodes
  inodes=$(stat -c '%i' /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock 2>/dev/null | paste -sd '|' -)
  [[ -n $inodes ]] || return 0
  awk -v re="^(${inodes})$" '
    {
      split($6, a, ":")
      if (a[3] ~ re && $5 ~ /^[0-9]+$/) print $5
    }
  ' /proc/locks | awk '!seen[$0]++'
}

proc_state() {
  awk '/^State:/ { print $2; exit }' "/proc/$1/status" 2>/dev/null || true
}

sig_cont() {
  local pid=$1
  [[ -v CONT_FAIL ]] || declare -gA CONT_FAIL
  if [[ $(id -u) -eq 0 ]]; then
    kill -CONT "$pid" 2>/dev/null && return 0
  elif sudo -n kill -CONT "$pid" 2>/dev/null; then
    return 0
  fi
  if [[ -z ${CONT_FAIL[$pid]:-} ]]; then
    CONT_FAIL[$pid]=1
    step_say "无法继续进程 ${pid}，sudo 未通过"
  fi
  return 1
}

stopped_tree_pids() {
  local pid=$1 child state
  state=$(proc_state "$pid")
  if [[ $state == T || $state == t ]]; then
    printf '%s\n' "$pid"
  fi
  for child in $(ps -o pid= --ppid "$pid" 2>/dev/null); do
    stopped_tree_pids "$child"
  done
}

sig_kill_group() {
  local pid=$1 pgid
  pgid=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')
  [[ -n $pgid ]] || return 1
  step_say "挂起的 apt 无法恢复，结束进程组 ${pgid}"
  if [[ $(id -u) -eq 0 ]]; then
    kill -TERM -- "-$pgid" 2>/dev/null || true
  else
    sudo -n kill -TERM -- "-$pgid" 2>/dev/null || true
  fi
}

wait_apt_lock() {
  local waited=0 pid cmd stopped
  local -a pids=() stopped_pids=()
  local -A seen=()
  while true; do
    mapfile -t pids < <(apt_lock_pids)
    ((${#pids[@]})) || return 0
    stopped_pids=()
    for pid in "${pids[@]}"; do
      while read -r stopped; do
        [[ -n $stopped ]] && stopped_pids+=("$stopped")
      done < <(stopped_tree_pids "$pid")
    done
    for pid in "${stopped_pids[@]}"; do
      if [[ -n ${seen[$pid]:-} ]]; then
        sig_kill_group "$pid"
      else
        step_say "apt 进程 ${pid} 已挂起，继续它"
        sig_cont "$pid" || true
        seen[$pid]=1
      fi
    done
    pid=${pids[0]}
    cmd=$(proc_cmd "$pid")
    step_say "等待 apt 锁 ${waited}s  进程 ${pid}  ${cmd}"
    if ((waited >= 900)); then
      step_note="等待 apt 锁超时，占用进程 ${pid}"
      return 1
    fi
    sleep 5
    waited=$((waited + 5))
  done
}

SAVED_STTY=""

# zsh 里常见 inlcr+icrnl：回车 CR→NL→CR，bash read 等不到换行，屏幕上只剩 ^M。
tty_fix() {
  [[ -r /dev/tty && -w /dev/tty ]] || return 0
  if [[ -z $SAVED_STTY ]]; then
    SAVED_STTY=$(stty -g </dev/tty 2>/dev/null || true)
  fi
  stty -inlcr -igncr icrnl icanon echo isig iexten </dev/tty 2>/dev/null || true
}

ROOT_PID=""
ISIG_KEEPER_PID=""

# sudo-rs 会把终端设成 -isig，Ctrl+C 不再产生 SIGINT。安装期间把 isig 拉回来。
start_isig_keeper() {
  [[ -n $ISIG_KEEPER_PID ]] && return 0
  [[ -r /dev/tty && -w /dev/tty ]] || return 0
  (
    trap '' INT TERM
    parent=$PPID
    while [[ -d /proc/$parent ]]; do
      stty isig </dev/tty 2>/dev/null || exit 0
      sleep 0.2
    done
  ) &
  ISIG_KEEPER_PID=$!
}

descendants() {
  local pid=$1 child
  printf '%s\n' "$pid"
  for child in $(ps -o pid= --ppid "$pid" 2>/dev/null); do
    descendants "$child"
  done
}

# Ctrl+C 杀不掉 root。先把整棵子进程记下来，再用 sudo 结束，避免子进程被 init 收养后继续跑。
kill_root_tree() {
  local pid=$1 p
  local -a all=()
  [[ -n $pid ]] || return 0
  mapfile -t all < <(descendants "$pid")
  ((${#all[@]})) || return 0
  for ((p = ${#all[@]} - 1; p >= 0; p--)); do
    sudo -n kill -TERM "${all[p]}" 2>/dev/null || kill -TERM "${all[p]}" 2>/dev/null || true
  done
  sleep 0.3
  for ((p = ${#all[@]} - 1; p >= 0; p--)); do
    [[ -d /proc/${all[p]} ]] || continue
    sudo -n kill -KILL "${all[p]}" 2>/dev/null || kill -KILL "${all[p]}" 2>/dev/null || true
  done
}

on_exit() {
  [[ -n $ISIG_KEEPER_PID ]] && kill "$ISIG_KEEPER_PID" 2>/dev/null || true
  [[ -n ${SUDO_KEEPALIVE_PID:-} ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
  [[ -n $SAVED_STTY ]] && stty "$SAVED_STTY" </dev/tty 2>/dev/null || true
}

on_interrupt() {
  trap - INT TERM
  printf '\n%s%s%s 已中断\n' "$BOLD_YELLOW" "$EMOJI_WARN" "$RESET" >/dev/tty
  local pid=$ROOT_PID
  ROOT_PID=""
  kill_root_tree "$pid"
  on_exit
  exit 130
}

arm_traps() {
  trap on_exit EXIT
  trap on_interrupt INT TERM
}

ensure_sudo() {
  [[ $(id -u) -eq 0 ]] && return 0
  tty_fix
  if ! sudo -n true 2>/dev/null; then
    printf '%s%s%s 需要 sudo 权限，请输入密码\n' "$BOLD_YELLOW" "$EMOJI_LOCK" "$RESET" >/dev/tty
    sudo -v </dev/tty >/dev/tty || return 1
  fi
  local parent=$PPID
  while [[ -d /proc/$parent ]]; do
    sleep 60
    [[ -d /proc/$parent ]] || exit 0
    sudo -n true 2>/dev/null || exit 0
  done &
  SUDO_KEEPALIVE_PID=$!
  arm_traps
}

# 后台跑 sudo 再 wait，Ctrl+C 才能进 trap。sudo 的标准输入输出不要占着终端，否则 sudo-rs 会另开会话，信号打不进去。
run_root() {
  local ttydev rc=0 fd prefix_pid
  start_isig_keeper
  ttydev=$(tty 2>/dev/null || true)
  [[ -n $ttydev && -w $ttydev ]] || ttydev=/dev/tty
  exec {fd}> >(step_prefix >"$ttydev")
  prefix_pid=$!
  sudo bash -c 'set -o pipefail; stdbuf -oL -eL "$@" </dev/null 2>&1 | tee -a "$0"' \
    "$LOG_FILE" "$@" </dev/null >&"$fd" 2>>"$LOG_FILE" &
  ROOT_PID=$!
  wait "$ROOT_PID"
  rc=$?
  ROOT_PID=""
  exec {fd}>&-
  wait "$prefix_pid" 2>/dev/null || true
  return "$rc"
}

install_bin() {
  local dest
  if root_ok; then
    dest=/usr/local/bin
    as_root mkdir -p "$dest"
    as_root install -m 755 "$@" "$dest/"
    return
  fi
  dest="$HOME/.local/bin"
  mkdir -p "$dest"
  install -m 755 "$@" "$dest/"
}

install_from_deb() {
  local deb=$1
  shift
  local tmp name bin
  local -a files=()
  tmp=$(mktemp -d)
  if ! dpkg-deb -x "$deb" "$tmp" >>"$LOG_FILE" 2>&1; then
    rm -rf "$tmp"
    return 1
  fi
  for name in "$@"; do
    bin=$(find "$tmp" -type f -name "$name" | head -1)
    if [[ -z $bin ]]; then
      log "deb 里没有 $name"
      rm -rf "$tmp"
      return 1
    fi
    files+=("$bin")
  done
  install_bin "${files[@]}"
  local rc=$?
  rm -rf "$tmp"
  return "$rc"
}

run_logged() {
  local rc=0 apt=0 tries=0 mark
  local -a cmd=("$@")
  if [[ ${cmd[0]} == apt-get || ( ${cmd[0]} == as_root && ${cmd[1]:-} == apt-get ) ]]; then
    apt=1
  fi
  while true; do
    if [[ $apt == 1 ]]; then
      wait_apt_lock || return 1
    fi
    log "+ ${cmd[*]}"
    step_say "${C_DIM}${cmd[*]}${C_OFF}"
    mark="## apt-try $$ $RANDOM"
    printf '%s\n' "$mark" >>"$LOG_FILE"
    if [[ ${cmd[0]} == as_root && $(id -u) -ne 0 ]]; then
      run_root "${cmd[@]:1}"
      rc=$?
    else
      "${cmd[@]}" 2>&1 | tee -a "$LOG_FILE" | step_prefix
      rc=${PIPESTATUS[0]}
    fi
    if [[ $rc -eq 0 ]]; then
      return 0
    fi
    if [[ $apt == 1 && $tries -lt 5 ]] && awk -v m="$mark" '$0 == m { f = 1; next } f' "$LOG_FILE" | grep -q 'Could not get lock'; then
      tries=$((tries + 1))
      step_say "apt 锁仍被占用，继续等待"
      continue
    fi
    return "$rc"
  done
}

pkg_installed() {
  local status
  status=$(dpkg-query -W -f '${Status}' "$1" 2>/dev/null || true)
  [[ $status == "install ok installed" ]]
}

apt_available() {
  local candidate
  candidate=$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ { print $2; exit }')
  [[ -n $candidate && $candidate != "(none)" ]]
}

install_pkgs() {
  local failed=() pkg
  step_note=""
  root_ok || { step_note="需要 root 或免密 sudo"; return 1; }
  for pkg in "$@"; do
    if pkg_installed "$pkg"; then
      log "already installed: $pkg"
      continue
    fi
    if ! apt_available "$pkg"; then
      log "no candidate: $pkg"
      failed+=("${pkg}(无候选)")
      continue
    fi
    if ! run_logged as_root apt-get install -y "${APT_OPTS[@]}" "$pkg"; then
      [[ $step_note == 等待\ apt\ 锁超时* ]] && return 1
      failed+=("$pkg")
    fi
  done
  if ((${#failed[@]})); then
    step_note="安装失败: ${failed[*]}"
    return 1
  fi
}

# curl_to DEST URL [extra curl args...]
curl_to() {
  local dest=$1 url=$2
  shift 2
  local tmp="${dest}.partial"
  local -a urls=()
  if [[ $USE_GITHUB_MIRROR == 1 ]]; then
    case $url in
    https://github.com/*)
      urls+=("https://${github_repo}/${url#https://github.com/}")
      ;;
    https://raw.githubusercontent.com/*)
      urls+=("https://${github_raw}/${url#https://raw.githubusercontent.com/}")
      ;;
    esac
  fi
  urls+=("$url")
  local try
  for try in "${urls[@]}"; do
    if [[ ! $try =~ ^https?://[^[:space:]]+$ ]]; then
      log "refuse url: $(sanitize "$try")"
      continue
    fi
    log "curl $try"
    if run_logged curl --globoff -fL --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 300 \
      --progress-bar "$@" -o "$tmp" "$try"; then
      mv "$tmp" "$dest"
      return 0
    fi
    log "curl failed: $try"
    rm -f "$tmp"
  done
  return 1
}

git_clone() {
  local path=$1 dest=$2 recurse=${3:-}
  local -a clone_args=()
  [[ $recurse == --recurse ]] && clone_args+=(--recurse-submodules)
  if [[ -d $dest/.git ]]; then
    log "repo exists: $dest"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  if [[ -e $dest ]]; then
    mv "$dest" "${dest}.bak.$(date +%s)"
  fi
  local -a urls=()
  if [[ $USE_GITHUB_MIRROR == 1 ]]; then
    urls+=("https://${github_repo}/${path}")
  fi
  urls+=("https://github.com/${path}")
  local url
  for url in "${urls[@]}"; do
    if run_logged git clone "${clone_args[@]}" "$url" "$dest"; then
      return 0
    fi
    rm -rf "$dest"
  done
  return 1
}

git_clone_urls() {
  local dest=$1
  shift
  if [[ -d $dest/.git ]]; then
    return 0
  fi
  if [[ -e $dest ]]; then
    mv "$dest" "${dest}.bak.$(date +%s)"
  fi
  local url
  for url in "$@"; do
    if run_logged git clone --depth 1 "$url" "$dest"; then
      return 0
    fi
    rm -rf "$dest"
  done
  return 1
}

machine_arch() {
  case $(uname -m) in
  x86_64) printf 'amd64 x86_64\n' ;;
  aarch64 | arm64) printf 'arm64 aarch64\n' ;;
  *) printf 'amd64 %s\n' "$(uname -m)" ;;
  esac
}

github_release_asset() {
  local repo=$1 pattern=$2
  local json url
  json=$(mktemp)
  url="https://api.github.com/repos/${repo}/releases/latest"
  # 调用方用 $(...) 取最后一行 URL。进度走 stderr，避免把 ANSI 和 \r 拼进地址。
  if ! curl_to "$json" "$url" -H "Accept: application/vnd.github+json" -H "User-Agent: ubuntu-setup" >&2; then
    rm -f "$json"
    return 1
  fi
  python3 - "$json" "$pattern" <<'PY'
import json, re, sys
path, pat = sys.argv[1], sys.argv[2]
try:
    data = json.load(open(path))
except Exception:
    sys.exit(1)
rx = re.compile(pat)
for asset in data.get("assets") or []:
    name = asset.get("name") or ""
    if "musl" in name:
        continue
    if rx.search(name):
        print(asset["browser_download_url"])
        sys.exit(0)
sys.exit(1)
PY
  local rc=$?
  rm -f "$json"
  return "$rc"
}

link_home() {
  local src=$1 dest=$2
  [[ -e $src || -L $src ]] || return 0
  ln -sfn "$src" "$dest"
}

ask_apt_source() {
  local -a names=(
    清华 阿里云 腾讯云 华为云 中科大 北大 浙大 南大 上交 兰大 华科
    网易 火山引擎 天翼云 移动云 中科院 中国科技云 官方
  )
  local -a hosts=(
    mirrors.tuna.tsinghua.edu.cn
    mirrors.aliyun.com
    mirrors.tencent.com
    mirrors.huaweicloud.com
    mirrors.ustc.edu.cn
    mirrors.pku.edu.cn
    mirrors.zju.edu.cn
    mirrors.nju.edu.cn
    mirror.sjtu.edu.cn
    mirror.lzu.edu.cn
    mirrors.hust.edu.cn
    mirrors.163.com
    mirrors.volces.com
    mirrors.ctyun.cn
    mirrors.cmecloud.cn
    mirror.iscas.ac.cn
    mirrors.cstcloud.cn
    archive.ubuntu.com
  )
  local i choice custom
  if [[ ! -r /dev/tty ]]; then
    printf '%s' "${hosts[0]}"
    return 0
  fi
  {
    printf '%s%s%s  选择 APT 镜像，直接回车使用清华\n' "$BOLD_CYAN" "$EMOJI_PKG" "$RESET"
    rule 56
    for i in "${!names[@]}"; do
      printf '  %s%2d%s  %-8s %s%s%s\n' \
        "$BOLD_CYAN" "$((i + 1))" "$RESET" \
        "${names[i]}" "$DIM" "${hosts[i]}" "$RESET"
    done
    printf '  %s%2d%s  %s\n' "$BOLD_CYAN" 0 "$RESET" "自定义域名"
    rule 56
  } >/dev/tty
  while true; do
    printf '%s序号%s %s[1]%s ' "$BOLD" "$RESET" "$DIM" "$RESET" >/dev/tty
    IFS= read -r choice </dev/tty || return 1
    choice=${choice//$'\r'/}
    choice=${choice:-1}
    if [[ $choice =~ ^[0-9]+$ ]]; then
      choice=$((10#$choice))
    fi
    if [[ $choice == 0 ]]; then
      printf '域名: ' >/dev/tty
      IFS= read -r custom </dev/tty || return 1
      custom=${custom//$'\r'/}
      custom=${custom#https://}
      custom=${custom#http://}
      custom=${custom%%/*}
      if [[ ! $custom =~ ^[A-Za-z0-9._-]+$ ]]; then
        printf '%s%s%s 域名无效\n' "$BOLD_RED" "$EMOJI_ERROR" "$RESET" >/dev/tty
        continue
      fi
      printf '%s' "$custom"
      return 0
    fi
    if [[ $choice =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#hosts[@]})); then
      printf '%s' "${hosts[choice - 1]}"
      return 0
    fi
    printf '%s请输入 0-%s%s\n' "$YELLOW" "${#hosts[@]}" "$RESET" >/dev/tty
  done
}

ask_yn() {
  local prompt=$1 default=${2:-y} input hint
  if [[ ! -r /dev/tty ]]; then
    [[ $default == [yY] ]]
    return
  fi
  if [[ $default == [nN] ]]; then
    hint='[y/N]'
  else
    hint='[Y/n]'
  fi
  tty_fix
  while true; do
    printf '%s%s%s %s%s%s ' "$BOLD" "$prompt" "$RESET" "$DIM" "$hint" "$RESET" >/dev/tty
    IFS= read -r input </dev/tty || return 1
    input=${input//$'\r'/}
    input=${input:-$default}
    case $input in
    [yY]) return 0 ;;
    [nN]) return 1 ;;
    *) printf '%s请输入 y 或 n%s\n' "$YELLOW" "$RESET" >/dev/tty ;;
    esac
  done
}

on_off() {
  if [[ $1 == 1 ]]; then
    printf '%s开%s' "$BOLD_GREEN" "$RESET"
  else
    printf '%s关%s' "$DIM" "$RESET"
  fi
}

# icon key value。key 按显示列对齐，value 里可以带颜色。
kv() {
  local icon=$1 key=$2
  shift 2
  printf '  %s  %s  %s\n' "$icon" "$(pad_col "$key" 14)" "$*"
}

choice_rows() {
  local mode=${1:-short} apt
  kv "$EMOJI_LOCK" "GitHub SSH" "$(on_off "$USE_SSH_KEY")"
  if [[ $mode == full && $USE_GITHUB_MIRROR == 1 ]]; then
    kv "$EMOJI_SPARK" "Github 镜像" "$(on_off 1)  ${DIM}失败回退 github.com${RESET}"
  else
    kv "$EMOJI_SPARK" "Github 镜像" "$(on_off "$USE_GITHUB_MIRROR")"
  fi
  if [[ $USE_APT_MIRROR == 1 ]]; then
    apt=${APT_SOURCE:-mirrors.tuna.tsinghua.edu.cn}
    if [[ $mode == full ]]; then
      kv "$EMOJI_PKG" "APT 换源" "${CYAN}${apt}${RESET}  ${DIM}失败恢复原源${RESET}"
    else
      kv "$EMOJI_PKG" "APT 换源" "${CYAN}${apt}${RESET}"
    fi
  else
    kv "$EMOJI_PKG" "APT 换源" "$(on_off 0)"
  fi
  kv "$EMOJI_DIR" "yazi" "$(on_off "$USE_YAZI")"
  kv "$EMOJI_WEB" "Edge" "$(on_off "$USE_EDGE")"
}

show_choices() {
  {
    printf '\n'
    printf '  %s%s%s  %s当前配置%s\n' "$BOLD_PURPLE" "$EMOJI_GEAR" "$RESET" "$BOLD" "$RESET"
    rule 56
    choice_rows short
    rule 56
  } >/dev/tty
}

# 0 开始安装，1 重选，q 直接退出。
confirm_run() {
  local input
  [[ -r /dev/tty ]] || return 0
  show_choices
  tty_fix
  while true; do
    printf '%s确认以上配置并开始安装?%s %s[Y/n/q]%s ' "$BOLD" "$RESET" "$DIM" "$RESET" >/dev/tty
    IFS= read -r input </dev/tty || exit 1
    input=${input//$'\r'/}
    input=${input:-y}
    case $input in
    [yY]) return 0 ;;
    [nN]) return 1 ;;
    [qQ])
      printf '%s%s%s 已退出\n' "$DIM" "$EMOJI_SKIP" "$RESET" >/dev/tty
      exit 0
      ;;
    *) printf '%s请输入 y、n 或 q%s\n' "$YELLOW" "$RESET" >/dev/tty ;;
    esac
  done
}

load_choices() {
  local from_file=0 redo=0 asked
  if [[ -f $CHOICE_FILE ]]; then
    # shellcheck disable=SC1090
    source "$CHOICE_FILE"
    from_file=1
  fi
  while true; do
    asked=0
    if [[ -n ${SETUP_SSH_KEY:-} ]]; then
      USE_SSH_KEY=$SETUP_SSH_KEY
    elif [[ $redo == 1 || -z ${USE_SSH_KEY+x} ]]; then
      if [[ ! -r /dev/tty ]]; then
        USE_SSH_KEY=0
      elif ask_yn "是否生成本机 SSH key 并上传到 GitHub?" y; then
        USE_SSH_KEY=1
      else
        USE_SSH_KEY=0
      fi
      asked=1
    fi
    if [[ -n ${SETUP_GITHUB_MIRROR:-} ]]; then
      USE_GITHUB_MIRROR=$SETUP_GITHUB_MIRROR
    elif [[ $redo == 1 || $from_file == 0 ]]; then
      if ask_yn "是否启用 Github 国内加速?" n; then
        USE_GITHUB_MIRROR=1
      else
        USE_GITHUB_MIRROR=0
      fi
      asked=1
    fi
    if [[ -n ${SETUP_APT_MIRROR:-} ]]; then
      USE_APT_MIRROR=$SETUP_APT_MIRROR
    elif [[ $redo == 1 || $from_file == 0 ]]; then
      if ask_yn "是否使用 LinuxMirrors 更换国内软件源?" y; then
        USE_APT_MIRROR=1
      else
        USE_APT_MIRROR=0
      fi
      asked=1
    fi
    if [[ -n ${SETUP_YAZI:-} ]]; then
      USE_YAZI=$SETUP_YAZI
    elif [[ $redo == 1 || -z ${USE_YAZI+x} ]]; then
      if ask_yn "是否安装 yazi?" y; then
        USE_YAZI=1
      else
        USE_YAZI=0
      fi
      asked=1
    fi
    if [[ -n ${SETUP_EDGE:-} ]]; then
      USE_EDGE=$SETUP_EDGE
    elif [[ $redo == 1 || -z ${USE_EDGE+x} ]]; then
      if ask_yn "是否安装 Microsoft Edge?" n; then
        USE_EDGE=1
      else
        USE_EDGE=0
      fi
      asked=1
    fi
    case ${USE_SSH_KEY:-0} in
    1 | y | Y | true) USE_SSH_KEY=1 ;;
    *) USE_SSH_KEY=0 ;;
    esac
    case $USE_GITHUB_MIRROR in
    1 | y | Y | true) USE_GITHUB_MIRROR=1 ;;
    *) USE_GITHUB_MIRROR=0 ;;
    esac
    case $USE_APT_MIRROR in
    1 | y | Y | true) USE_APT_MIRROR=1 ;;
    *) USE_APT_MIRROR=0 ;;
    esac
    case ${USE_YAZI:-0} in
    1 | y | Y | true) USE_YAZI=1 ;;
    *) USE_YAZI=0 ;;
    esac
    case ${USE_EDGE:-0} in
    1 | y | Y | true) USE_EDGE=1 ;;
    *) USE_EDGE=0 ;;
    esac
    if [[ $USE_APT_MIRROR == 1 ]]; then
      if [[ -n ${SETUP_APT_SOURCE:-} ]]; then
        APT_SOURCE=$SETUP_APT_SOURCE
      elif [[ $redo == 1 || -z ${APT_SOURCE:-} ]]; then
        APT_SOURCE=$(ask_apt_source) || APT_SOURCE="mirrors.tuna.tsinghua.edu.cn"
        asked=1
      fi
      APT_SOURCE=${APT_SOURCE#https://}
      APT_SOURCE=${APT_SOURCE#http://}
      APT_SOURCE=${APT_SOURCE%%/*}
      if [[ ! $APT_SOURCE =~ ^[A-Za-z0-9._-]+$ ]]; then
        APT_SOURCE=$(ask_apt_source) || APT_SOURCE="mirrors.tuna.tsinghua.edu.cn"
        asked=1
      fi
    else
      APT_SOURCE=""
    fi
    if confirm_run; then
      break
    fi
    redo=1
    [[ -z ${SETUP_SSH_KEY:-} ]] && unset USE_SSH_KEY
    [[ -z ${SETUP_GITHUB_MIRROR:-} ]] && unset USE_GITHUB_MIRROR
    [[ -z ${SETUP_APT_MIRROR:-} ]] && unset USE_APT_MIRROR
    [[ -z ${SETUP_YAZI:-} ]] && unset USE_YAZI
    [[ -z ${SETUP_EDGE:-} ]] && unset USE_EDGE
    [[ -z ${SETUP_APT_SOURCE:-} ]] && unset APT_SOURCE
  done
  if [[ $USE_GITHUB_MIRROR == 1 ]]; then
    github_repo="githubfast.com"
    github_raw="raw.gitmirror.com"
  else
    github_repo="github.com"
    github_raw="raw.githubusercontent.com"
  fi
  cat >"$CHOICE_FILE" <<EOF
# 1 开，0 关。删掉 state.tsv 里对应行会在下次重跑该步。
USE_SSH_KEY=$USE_SSH_KEY
USE_GITHUB_MIRROR=$USE_GITHUB_MIRROR
USE_APT_MIRROR=$USE_APT_MIRROR
APT_SOURCE=$APT_SOURCE
USE_YAZI=$USE_YAZI
USE_EDGE=$USE_EDGE
EOF
}

config_paths() {
  printf '%s\n' \
    "$HOME/.bashrc" \
    "$HOME/.zshrc" \
    "$HOME/.profile" \
    "$HOME/.gitconfig" \
    "$HOME/.config" \
    "$HOME/script/.git/config" \
    /etc/apt/sources.list \
    /etc/apt/sources.list.d
}

is_root_path() {
  [[ $1 == /etc/* || $1 == /usr/* ]]
}

# 只在第一次安装时拍快照。之后重跑不覆盖，卸载按这份还原。
snapshot_configs() {
  local path idx=0 stored tmp
  if [[ -f $CONFIG_MANIFEST ]]; then
    return 0
  fi
  mkdir -p "$CONFIG_BACKUP/files" || return 1
  tmp=$(mktemp)
  while IFS= read -r path; do
    [[ -n $path ]] || continue
    stored="$CONFIG_BACKUP/files/$idx"
    if [[ -e $path || -L $path ]]; then
      cp -a "$path" "$stored" || { rm -rf "$CONFIG_BACKUP"; rm -f "$tmp"; return 1; }
      printf 'present\t%s\t%s\n' "$path" "$idx" >>"$tmp"
    else
      printf 'absent\t%s\t\n' "$path" >>"$tmp"
    fi
    idx=$((idx + 1))
  done < <(config_paths)
  mv "$tmp" "$CONFIG_MANIFEST" || return 1
}

restore_configs() {
  local status path idx stored i
  local -a lines=()
  [[ -f $CONFIG_MANIFEST ]] || return 2
  mapfile -t lines <"$CONFIG_MANIFEST"
  ((${#lines[@]})) || return 2
  for ((i = ${#lines[@]} - 1; i >= 0; i--)); do
    [[ -n ${lines[i]} ]] || continue
    IFS=$'\t' read -r status path idx <<<"${lines[i]}"
    [[ -n $path ]] || continue
    if [[ $status == absent ]]; then
      if is_root_path "$path"; then
        as_root rm -rf "$path" || { step_note="删除 $path 失败"; return 1; }
      elif [[ -e $path || -L $path ]]; then
        rm -rf "$path" || { step_note="删除 $path 失败"; return 1; }
      fi
      continue
    fi
    stored="$CONFIG_BACKUP/files/$idx"
    if [[ ! -e $stored && ! -L $stored ]]; then
      step_note="备份缺失: $path"
      return 1
    fi
    if is_root_path "$path"; then
      as_root rm -rf "$path" || { step_note="清理 $path 失败"; return 1; }
      as_root mkdir -p "$(dirname "$path")" || return 1
      as_root cp -a "$stored" "$path" || { step_note="恢复 $path 失败"; return 1; }
    else
      rm -rf "$path" || { step_note="清理 $path 失败"; return 1; }
      mkdir -p "$(dirname "$path")" || return 1
      cp -a "$stored" "$path" || { step_note="恢复 $path 失败"; return 1; }
    fi
  done
}

backup_apt_sources() {
  rm -rf "$APT_BACKUP"
  mkdir -p "$APT_BACKUP/sources.list.d"
  if [[ -f /etc/apt/sources.list ]]; then
    cp -a /etc/apt/sources.list "$APT_BACKUP/sources.list"
  fi
  if [[ -d /etc/apt/sources.list.d ]]; then
    cp -a /etc/apt/sources.list.d/. "$APT_BACKUP/sources.list.d/" 2>/dev/null || true
  fi
}

restore_apt_sources() {
  log "restore apt sources from $APT_BACKUP"
  if [[ -f $APT_BACKUP/sources.list ]]; then
    as_root cp -a "$APT_BACKUP/sources.list" /etc/apt/sources.list
  else
    as_root rm -f /etc/apt/sources.list
  fi
  as_root mkdir -p /etc/apt/sources.list.d
  as_root find /etc/apt/sources.list.d -mindepth 1 -delete
  if [[ -d $APT_BACKUP/sources.list.d ]]; then
    as_root cp -a "$APT_BACKUP/sources.list.d/." /etc/apt/sources.list.d/
  fi
}

# ---------- steps ----------

# GitHub 认证成功时 ssh -T 仍返回 1，只能看输出。
github_ssh_probe() {
  local identity=$1
  local -a opts=(
    -o BatchMode=yes
    -o StrictHostKeyChecking=accept-new
    -o ConnectTimeout=15
    -T
  )
  if [[ -n $identity ]]; then
    opts=(-o IdentitiesOnly=yes -o IdentityFile="$identity" "${opts[@]}")
  fi
  ssh "${opts[@]}" git@github.com 2>&1 || true
}

github_ssh_user() {
  local out=$1
  if [[ $out =~ Hi[[:space:]]([^![:space:]]+)! ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

step_ssh_key() {
  local key=$HOME/.ssh/id_ed25519 email pub out user input
  out=$(github_ssh_probe "")
  if user=$(github_ssh_user "$out"); then
    step_note="GitHub SSH 已可用：${user}"
    return 0
  fi
  if ! command -v ssh-keygen >/dev/null 2>&1 || ! command -v ssh >/dev/null 2>&1; then
    step_note="没有 ssh 或 ssh-keygen"
    return 1
  fi
  if [[ ! -r /dev/tty ]]; then
    step_note="没有终端，无法确认是否已上传到 GitHub"
    return 1
  fi

  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh" || true
  if [[ ! -f $key ]]; then
    email=$(git config --global user.email 2>/dev/null || true)
    email=${email:-haomingzidougeixle@gmail.com}
    if ! ssh-keygen -q -t ed25519 -C "$email" -f "$key" -N "" </dev/null; then
      step_note="ssh-keygen 失败"
      return 1
    fi
    chmod 600 "$key" || true
    chmod 644 "$key.pub" || true
  fi
  if [[ ! -f $key.pub ]]; then
    step_note="找不到 $key.pub"
    return 1
  fi
  pub=$(<"$key.pub")
  {
    printf '\n%s%s%s  公钥\n' "$BOLD_CYAN" "$EMOJI_LOCK" "$RESET"
    printf '%s\n\n' "$pub"
    printf '打开 %shttps://github.com/settings/ssh/new%s\n' "$CYAN" "$RESET"
    printf 'Title 随意，Key type 选 Authentication Key，把上面整行贴进去。\n'
    printf '密钥没有口令，之后本机 git push 不用再输入。\n'
  } >/dev/tty

  local retry=0
  while true; do
    if [[ $retry == 0 ]]; then
      printf '\n添加完成后回车开始验证： ' >/dev/tty
    else
      printf '回车继续等待你添加公钥，输入 s 跳过这一步： ' >/dev/tty
    fi
    IFS= read -r input </dev/tty || return 1
    input=${input//$'\r'/}
    if [[ $retry == 1 && $input == [sS] ]]; then
      step_note="已跳过 GitHub SSH 确认"
      return 2
    fi
    if [[ $retry == 1 && -n $input ]]; then
      printf '回车继续等待，或输入 s 跳过\n' >/dev/tty
      continue
    fi
    out=$(github_ssh_probe "$key")
    if user=$(github_ssh_user "$out"); then
      printf '%s%s%s 验证成功，GitHub 账号 %s%s%s\n' \
        "$BOLD_GREEN" "$EMOJI_SUCCESS" "$RESET" "$BOLD" "$user" "$RESET" >/dev/tty
      step_note="已登录 GitHub：${user}"
      return 0
    fi
    printf '\n%s%s%s 验证失败，GitHub 还没接受这把密钥\n%s\n' \
      "$BOLD_RED" "$EMOJI_ERROR" "$RESET" "$out" >/dev/tty
    retry=1
  done
}

step_os_check() {
  local id
  id=$(. /etc/os-release && printf '%s' "$ID")
  if [[ $id != ubuntu ]]; then
    step_note="当前系统不是 Ubuntu (${id:-unknown})"
    return 1
  fi
}

step_base_pkgs() {
  local pkg missing=0
  for pkg in git curl wget ca-certificates gnupg; do
    pkg_installed "$pkg" || missing=1
  done
  if [[ $missing == 0 ]]; then
    return 0
  fi
  root_ok || { step_note="需要 root 或免密 sudo"; return 1; }
  run_logged as_root apt-get update || log "base apt-get update failed"
  install_pkgs git curl wget ca-certificates gnupg
}

step_git_identity() {
  git config --global user.email "haomingzidougeixle@gmail.com"
  git config --global user.name "momo"
}

step_pull_script() {
  local dest="$HOME/script"
  local push="git@github.com:mogeku/script.git"
  local origin=""

  if [[ -d $dest/.git ]]; then
    origin=$(git -C "$dest" remote get-url origin 2>/dev/null || true)
    if [[ $origin == *mogeku/script* ]]; then
      git -C "$dest" remote set-url --push origin "$push" >>"$LOG_FILE" 2>&1 \
        || { step_note="设置 script push remote 失败"; return 1; }
      return 0
    fi
    step_note="~/script 属于其它仓库，未覆盖"
    return 2
  fi

  if [[ -d $dest ]]; then
    local tmp
    tmp=$(mktemp -d)
    if ! git_clone "mogeku/script.git" "$tmp/script"; then
      rm -rf "$tmp"
      step_note="克隆 script 失败，原目录未改动"
      return 1
    fi
    cp -a --update=none "$tmp/script"/. "$dest/" || { rm -rf "$tmp"; step_note="合并 script 失败"; return 1; }
    if [[ ! -d $dest/.git ]]; then
      mv "$tmp/script/.git" "$dest/.git"
    fi
    rm -rf "$tmp"
  else
    git_clone "mogeku/script.git" "$dest" || { step_note="克隆 script 失败"; return 1; }
  fi
  git -C "$dest" remote set-url --push origin "$push" >>"$LOG_FILE" 2>&1 \
    || { step_note="设置 script push remote 失败"; return 1; }
}

step_pull_config() {
  local dest="$HOME/.config"
  local push="git@github.com:mogeku/.config.git"
  local origin=""

  if [[ -d $dest/.git ]]; then
    origin=$(git -C "$dest" remote get-url origin 2>/dev/null || true)
    if [[ $origin == *mogeku/.config* ]]; then
      git -C "$dest" remote set-url --push origin "$push" >>"$LOG_FILE" 2>&1 \
        || { step_note="设置 .config push remote 失败"; return 1; }
      link_home "$dest/.bashrc" "$HOME/.bashrc"
      link_home "$dest/.zshrc" "$HOME/.zshrc"
      return 0
    fi
    step_note="~/.config 属于其它仓库，未覆盖"
    return 2
  fi

  if [[ -d $dest ]]; then
    local tmp
    tmp=$(mktemp -d)
    if ! git_clone "mogeku/.config.git" "$tmp/cfg" --recurse; then
      rm -rf "$tmp"
      step_note="克隆 .config 失败，原目录未改动"
      return 1
    fi
    cp -a --update=none "$tmp/cfg"/. "$dest/" || { rm -rf "$tmp"; step_note="合并 .config 失败"; return 1; }
    if [[ ! -d $dest/.git ]]; then
      mv "$tmp/cfg/.git" "$dest/.git"
    fi
    rm -rf "$tmp"
  else
    git_clone "mogeku/.config.git" "$dest" --recurse || { step_note="克隆 .config 失败"; return 1; }
  fi
  git -C "$dest" remote set-url --push origin "$push" >>"$LOG_FILE" 2>&1 || true
  link_home "$dest/.bashrc" "$HOME/.bashrc"
  link_home "$dest/.zshrc" "$HOME/.zshrc"
}

step_apt_mirror() {
  if [[ $USE_APT_MIRROR != 1 ]]; then
    step_note="未启用"
    return 2
  fi
  root_ok || { step_note="需要 root 或免密 sudo"; return 1; }
  local script codename
  mkdir -p "$STATE_DIR/cache"
  script="$STATE_DIR/cache/ChangeMirrors.sh"
  if ! curl_to "$script" "https://gitee.com/SuperManito/LinuxMirrors/raw/main/ChangeMirrors.sh"; then
    if ! curl -fL --retry 2 --connect-timeout 20 --max-time 60 \
      -o "$script" "https://raw.githubusercontent.com/SuperManito/LinuxMirrors/main/ChangeMirrors.sh" \
      >>"$LOG_FILE" 2>&1; then
      step_note="下载 LinuxMirrors 失败"
      return 1
    fi
  fi
  codename=$(. /etc/os-release && printf '%s' "${VERSION_CODENAME:-}")
  backup_apt_sources
  if [[ ! -f $APT_BACKUP/sources.list ]] && ! compgen -G "$APT_BACKUP/sources.list.d/*" >/dev/null; then
    step_note="备份软件源失败，未换源"
    return 1
  fi
  # bash 的 [[ =~ ]] 不认 [[:ascii:]]，动画模式会逐行报错并卡住
  sed -i 's/\[\[:ascii:\]\]/[[:print:]]/g' "$script"
  local source=${APT_SOURCE:-mirrors.tuna.tsinghua.edu.cn}
  local -a args=(
    --source "$source"
    --protocol https
    --use-intranet-source false
    --backup true
    --upgrade-software false
    --clean-cache false
    --clean-screen false
    --ignore-backup-tips
  )
  [[ -n $codename ]] && args+=(--codename "$codename")
  log "ChangeMirrors ${args[*]}"
  step_say "更换软件源"
  local mirror_rc=0
  if [[ $(id -u) -eq 0 ]]; then
    timeout 300 bash "$script" "${args[@]}" </dev/null 2>&1 | tee -a "$LOG_FILE" | step_prefix
    mirror_rc=${PIPESTATUS[0]}
  else
    run_root timeout 300 bash "$script" "${args[@]}" || mirror_rc=$?
  fi
  if [[ $mirror_rc -ne 0 ]] || ! run_logged as_root apt-get update; then
    restore_apt_sources || true
    if run_logged as_root apt-get update; then
      step_note="换源失败，已恢复原软件源"
    else
      step_note="换源失败，恢复原软件源后 apt update 仍失败"
    fi
    return 1
  fi
}

step_apt_update() {
  root_ok || { step_note="需要 root 或免密 sudo"; return 1; }
  run_logged as_root apt-get update || { step_note="apt update 失败"; return 1; }
}

step_apt_upgrade() {
  run_logged as_root apt-get upgrade -y "${APT_OPTS[@]}" || { step_note="apt upgrade 失败"; return 1; }
}

step_cpp() {
  install_pkgs gcc g++ gdb clang make
}

step_cli() {
  local -a pkgs=(tree fzf ripgrep xsel xclip bat eza duf httpie shellcheck apt-file fd-find figlet)
  if apt_available neofetch; then
    pkgs+=(neofetch)
  else
    log "neofetch 无候选，改用 fastfetch"
    pkgs+=(fastfetch)
  fi
  if apt_available tldr; then
    pkgs+=(tldr)
  else
    log "tldr 无候选，改用 tealdeer"
    pkgs+=(tealdeer)
  fi
  local rc=0 note
  install_pkgs "${pkgs[@]}" || rc=1
  note=$step_note
  if [[ -x /usr/bin/fdfind ]]; then
    as_root ln -sfn /usr/bin/fdfind /usr/local/bin/fd || true
  fi
  if [[ ! -x /usr/bin/bat && ! -x /usr/local/bin/bat && -x /usr/bin/batcat ]]; then
    as_root ln -sfn /usr/bin/batcat /usr/local/bin/bat || true
  fi
  if command -v apt-file >/dev/null; then
    run_logged as_root apt-file update || log "apt-file update failed"
  fi
  if command -v tldr >/dev/null; then
    run_logged tldr --update || run_logged tldr tldr || log "tldr update failed"
  fi
  step_note=$note
  return "$rc"
}

step_bottom() {
  if command -v btm >/dev/null 2>&1; then
    return 0
  fi
  local deb_arch rust_arch asset dest pattern
  read -r deb_arch rust_arch < <(machine_arch)
  pattern="^bottom_[0-9].*_${deb_arch}\\.deb$"
  asset=$(github_release_asset "ClementTsang/bottom" "$pattern") || {
    step_note="无法获取 bottom 发布信息"
    return 1
  }
  mkdir -p "$STATE_DIR/cache"
  dest="$STATE_DIR/cache/$(basename "$asset")"
  curl_to "$dest" "$asset" || { step_note="下载 bottom 失败"; return 1; }
  if root_ok && run_logged as_root apt-get install -y "${APT_OPTS[@]}" "$dest"; then
    hash -r || true
    command -v btm >/dev/null 2>&1 && return 0
  fi
  install_from_deb "$dest" btm || { step_note="安装 bottom 失败"; return 1; }
  hash -r || true
  command -v btm >/dev/null 2>&1 || { step_note="btm 不在 PATH"; return 1; }
  root_ok || step_note="装到 ~/.local/bin"
}

step_zsh() {
  local rc=0 notes=()
  if ! command -v zsh >/dev/null 2>&1 && ! install_pkgs zsh; then
    notes+=("$step_note")
    rc=1
  fi
  if ! command -v zsh >/dev/null 2>&1; then
    step_note="${notes[*]:-未安装 zsh}"
    return 1
  fi
  if [[ ! -d $HOME/.oh-my-zsh ]]; then
    local script
    script=$(mktemp)
    if ! curl_to "$script" "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"; then
      notes+=("下载 oh-my-zsh 失败")
      rc=1
    else
      RUNZSH=no CHSH=no KEEP_ZSHRC=yes run_logged sh "$script" </dev/null || log "oh-my-zsh installer returned non-zero"
      rm -f "$script"
      if [[ ! -d $HOME/.oh-my-zsh ]]; then
        notes+=("oh-my-zsh 目录不存在")
        rc=1
      fi
    fi
  fi
  if [[ -d $HOME/.oh-my-zsh ]]; then
    local custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    local -a urls=()
    mkdir -p "$custom/plugins"
    urls=("https://github.com/zsh-users/zsh-autosuggestions.git")
    [[ $USE_GITHUB_MIRROR == 1 ]] && urls=("https://${github_repo}/zsh-users/zsh-autosuggestions.git" "${urls[@]}")
    git_clone_urls "$custom/plugins/zsh-autosuggestions" "${urls[@]}" \
      || { notes+=("zsh-autosuggestions"); rc=1; }
    urls=()
    [[ $USE_GITHUB_MIRROR == 1 ]] && urls+=("https://${github_repo}/zsh-users/zsh-syntax-highlighting.git")
    urls+=("https://gitee.com/zsh-users/zsh-syntax-highlighting.git" "https://github.com/zsh-users/zsh-syntax-highlighting.git")
    git_clone_urls "$custom/plugins/zsh-syntax-highlighting" "${urls[@]}" \
      || { notes+=("zsh-syntax-highlighting"); rc=1; }
  fi
  if ((${#notes[@]})); then
    step_note="${notes[*]}"
    return 1
  fi
}

step_node() {
  install_pkgs nodejs npm || return 1
  command -v node >/dev/null 2>&1 || { step_note="node 不在 PATH"; return 1; }
}

step_golang() {
  install_pkgs golang-go || return 1
  command -v go >/dev/null 2>&1 || { step_note="go 不在 PATH"; return 1; }
}

step_python() {
  install_pkgs python3 python3-dev python3-pip gsettings-desktop-schemas || return 1
  if [[ ! -x /usr/bin/python3 ]]; then
    step_note="python3 不在 /usr/bin/python3"
    return 1
  fi
  as_root ln -sfn /usr/bin/python3 /usr/bin/python
}

step_cmake() {
  install_pkgs cmake || return 1
  command -v cmake >/dev/null 2>&1 || { step_note="cmake 不在 PATH"; return 1; }
}

step_lazygit() {
  install_pkgs lazygit || return 1
  command -v lazygit >/dev/null 2>&1 || { step_note="lazygit 不在 PATH"; return 1; }
}

step_autojump() {
  if command -v autojump >/dev/null 2>&1 || [[ -d $HOME/.autojump ]] || pkg_installed autojump; then
    return 0
  fi
  local dest="$STATE_DIR/src/autojump"
  mkdir -p "$STATE_DIR/src"
  if git_clone "wting/autojump.git" "$dest"; then
    if run_logged bash -c "cd $(printf %q "$dest") && python3 ./install.py" </dev/null; then
      return 0
    fi
    log "autojump install.py failed, fallback apt"
  fi
  install_pkgs autojump || { step_note="${step_note:-autojump 安装失败}"; return 1; }
}

step_dust() {
  if [[ -e /usr/bin/dust || -e /usr/local/bin/dust || -e $HOME/.local/bin/dust ]]; then
    return 0
  fi
  if [[ ! -x $HOME/.config/dust ]]; then
    step_note="找不到 ~/.config/dust"
    return 1
  fi
  if root_ok; then
    as_root ln -sfn "$HOME/.config/dust" /usr/local/bin/dust || { step_note="链接 dust 失败"; return 1; }
    return 0
  fi
  mkdir -p "$HOME/.local/bin"
  ln -sfn "$HOME/.config/dust" "$HOME/.local/bin/dust" || { step_note="链接 dust 失败"; return 1; }
  step_note="装到 ~/.local/bin"
}

step_addssh() {
  local src="$HOME/script/addssh.sh"
  if [[ -e /usr/bin/addssh || -e /usr/local/bin/addssh || -e $HOME/.local/bin/addssh ]]; then
    return 0
  fi
  if [[ ! -f $src ]]; then
    step_note="找不到 addssh.sh"
    return 1
  fi
  if root_ok; then
    as_root ln -sfn "$src" /usr/local/bin/addssh || { step_note="链接 addssh 失败"; return 1; }
    return 0
  fi
  mkdir -p "$HOME/.local/bin"
  ln -sfn "$src" "$HOME/.local/bin/addssh" || { step_note="链接 addssh 失败"; return 1; }
  step_note="装到 ~/.local/bin"
}

step_rustup() {
  if [[ -x $HOME/.cargo/bin/rustup ]]; then
    # shellcheck disable=SC1091
    [[ -f $HOME/.cargo/env ]] && source "$HOME/.cargo/env"
    return 0
  fi
  local script rc
  script=$(mktemp)
  rc=1
  if [[ $USE_GITHUB_MIRROR == 1 ]]; then
    if run_logged curl -fL --retry 2 --connect-timeout 20 --max-time 120 --progress-bar \
      -o "$script" "https://mirrors.tuna.tsinghua.edu.cn/rustup/rustup-init.sh"; then
      log "rustup via tuna"
      if RUSTUP_DIST_SERVER="https://mirrors.tuna.tsinghua.edu.cn/rustup" \
        RUSTUP_UPDATE_ROOT="https://mirrors.tuna.tsinghua.edu.cn/rustup/rustup" \
        run_logged sh "$script" -y --default-toolchain stable </dev/null; then
        rc=0
      fi
    fi
  fi
  if [[ $rc -ne 0 ]]; then
    if curl_to "$script" "https://sh.rustup.rs"; then
      log "rustup via sh.rustup.rs"
      if run_logged sh "$script" -y --default-toolchain stable </dev/null; then
        rc=0
      fi
    fi
  fi
  rm -f "$script"
  if [[ $rc -ne 0 || ! -x $HOME/.cargo/bin/rustup ]]; then
    step_note="rustup 安装失败"
    return 1
  fi
  # shellcheck disable=SC1091
  source "$HOME/.cargo/env"
}

step_yazi() {
  if [[ ${USE_YAZI:-0} != 1 ]]; then
    step_note="未选择安装"
    return 2
  fi
  if command -v yazi >/dev/null 2>&1; then
    return 0
  fi
  local deb_arch rust_arch asset dest
  read -r deb_arch rust_arch < <(machine_arch)
  mkdir -p "$STATE_DIR/cache"
  dest="$STATE_DIR/cache/yazi-${rust_arch}-unknown-linux-gnu.deb"
  if [[ ! -f $dest ]]; then
    asset=$(github_release_asset "sxyazi/yazi" "^yazi-${rust_arch}-unknown-linux-gnu\\.deb$") || asset=""
    if [[ -n $asset ]]; then
      dest="$STATE_DIR/cache/$(basename "$asset")"
      curl_to "$dest" "$asset" || dest=""
    fi
  fi
  if [[ -n $dest && -f $dest ]]; then
    if root_ok && run_logged as_root apt-get install -y "${APT_OPTS[@]}" "$dest"; then
      hash -r || true
      command -v yazi >/dev/null 2>&1 && return 0
    fi
    if install_from_deb "$dest" yazi ya; then
      hash -r || true
      if command -v yazi >/dev/null 2>&1; then
        root_ok || step_note="装到 ~/.local/bin"
        return 0
      fi
    fi
    log "yazi deb install failed, try cargo"
  else
    log "no yazi release asset"
  fi
  if [[ ! -x $HOME/.cargo/bin/cargo ]]; then
    step_note="发布包安装失败，且没有 cargo"
    return 1
  fi
  # shellcheck disable=SC1091
  [[ -f $HOME/.cargo/env ]] && source "$HOME/.cargo/env"
  install_pkgs build-essential pkg-config libssl-dev || log "yazi build deps failed"
  git_clone "sxyazi/yazi.git" "$HOME/yazi" || { step_note="克隆 yazi 失败"; return 1; }
  if ! (cd "$HOME/yazi" && run_logged cargo build --release --locked); then
    step_note="cargo build yazi 失败"
    return 1
  fi
  install_bin "$HOME/yazi/target/release/yazi" "$HOME/yazi/target/release/ya" \
    || { step_note="安装 yazi 二进制失败"; return 1; }
  root_ok || step_note="装到 ~/.local/bin"
}

step_nvim() {
  local rc=0 notes=()
  if ! command -v nvim >/dev/null 2>&1 && ! install_pkgs neovim; then
    notes+=("${step_note:-neovim 安装失败}")
    rc=1
  fi
  if ! git_clone "mogeku/nvim.git" "$HOME/.config/nvim" --recurse; then
    notes+=("克隆 nvim 配置失败")
    rc=1
  elif ! git -C "$HOME/.config/nvim" remote set-url --push origin git@github.com:mogeku/nvim.git >>"$LOG_FILE" 2>&1; then
    notes+=("设置 nvim push remote 失败")
    rc=1
  fi
  if ((${#notes[@]})); then
    step_note="${notes[*]}"
    return 1
  fi
  command -v nvim >/dev/null 2>&1 || { step_note="nvim 不在 PATH"; return 1; }
}

step_nerd_font() {
  local src="$HOME/.config/fonts/JetBrains Mono Bold Nerd Font Complete Mono.ttf"
  local fonts="$HOME/.local/share/fonts"
  local dest="$fonts/JetBrains Mono Bold Nerd Font Complete Mono.ttf"
  if [[ ! -f $src ]]; then
    step_note="找不到 Nerd Font 文件"
    return 1
  fi
  mkdir -p "$fonts"
  cp -f "$src" "$dest" || { step_note="复制字体失败"; return 1; }
  chmod 744 "$dest" || true
  if ! command -v fc-cache >/dev/null 2>&1; then
    install_pkgs fontconfig || true
  fi
  if command -v fc-cache >/dev/null 2>&1; then
    run_logged fc-cache -f "$fonts" || log "fc-cache failed"
  fi
}

step_edge() {
  if [[ ${USE_EDGE:-0} != 1 ]]; then
    step_note="未选择安装"
    return 2
  fi
  local bin=""
  if [[ -x /usr/bin/microsoft-edge-dev ]]; then
    bin=/usr/bin/microsoft-edge-dev
  elif [[ -x /usr/bin/microsoft-edge ]]; then
    bin=/usr/bin/microsoft-edge
  fi
  if [[ -n $bin ]]; then
    as_root ln -sfn "$bin" /usr/bin/edge
    return 0
  fi
  local key list
  key=$(mktemp)
  if ! curl -fL --retry 3 --connect-timeout 20 --max-time 60 \
    -o "$key.asc" "https://packages.microsoft.com/keys/microsoft.asc" >>"$LOG_FILE" 2>&1; then
    rm -f "$key" "$key.asc"
    step_note="下载 Microsoft 签名密钥失败"
    return 1
  fi
  gpg --dearmor <"$key.asc" >"$key" 2>>"$LOG_FILE" || { rm -f "$key" "$key.asc"; step_note="解析 Microsoft 密钥失败"; return 1; }
  rm -f "$key.asc"
  as_root install -o root -g root -m 644 "$key" /usr/share/keyrings/microsoft-edge.gpg || { rm -f "$key"; step_note="安装 Microsoft 密钥失败"; return 1; }
  rm -f "$key"
  list=/etc/apt/sources.list.d/microsoft-edge.list
  printf 'deb [arch=%s signed-by=/usr/share/keyrings/microsoft-edge.gpg] https://packages.microsoft.com/repos/edge stable main\n' \
    "$(dpkg --print-architecture)" \
    | as_root tee "$list" >>"$LOG_FILE"
  if ! run_logged as_root apt-get update || ! run_logged as_root apt-get install -y "${APT_OPTS[@]}" microsoft-edge-dev; then
    as_root rm -f "$list"
    run_logged as_root apt-get update || true
    step_note="安装 microsoft-edge-dev 失败，已移除其软件源"
    return 1
  fi
  if [[ -x /usr/bin/microsoft-edge-dev ]]; then
    as_root ln -sfn /usr/bin/microsoft-edge-dev /usr/bin/edge
  elif [[ -x /usr/bin/microsoft-edge ]]; then
    as_root ln -sfn /usr/bin/microsoft-edge /usr/bin/edge
  else
    step_note="Edge 已安装但找不到可执行文件"
    return 1
  fi
}

step_apt_clean() {
  run_logged as_root apt-get clean || { step_note="apt clean 失败"; return 1; }
  run_logged as_root apt-get autoremove -y || { step_note="apt autoremove 失败"; return 1; }
}

# ---------- uninstall ----------

usage_row() {
  local key=$1
  shift
  printf '  %s%s%s %s\n' "$CYAN" "$(pad_col "$key" 26)" "$RESET" "$*"
}

usage() {
  rule
  printf '  %s%s%s  %ssetup.sh%s\n' "$BOLD_PURPLE" "$EMOJI_ROCKET" "$RESET" "$BOLD" "$RESET"
  printf '  %s可重复执行的 Ubuntu 安装脚本%s\n' "$DIM" "$RESET"
  rule
  printf '\n%s命令%s\n' "$BOLD" "$RESET"
  usage_row "install, --install" "安装（默认）。结束后切到 zsh 并加载 ~/.zshrc"
  usage_row "uninstall, --uninstall" "卸掉本脚本添加的组件，回到安装前"
  usage_row "clear, --clear" "清空已保存的选择，下次安装重新询问"
  usage_row "-h, --help" "显示此帮助"
  printf '\n%s环境变量%s\n' "$BOLD" "$RESET"
  usage_row "SETUP_FORCE=1" "忽略已成功记录，重跑安装步骤"
  usage_row "SETUP_GITHUB_MIRROR=1|0" "Github 国内加速"
  usage_row "SETUP_APT_MIRROR=1|0" "是否更换 APT 软件源"
  usage_row "SETUP_APT_SOURCE=域名" "指定 APT 镜像，跳过选择菜单"
  usage_row "SETUP_YAZI=1|0" "是否安装 yazi"
  usage_row "SETUP_EDGE=1|0" "是否安装 Microsoft Edge"
  usage_row "SETUP_SSH_KEY=1|0" "是否生成本机 SSH key 并上传到 GitHub"
  printf '\n'
}

parse_args() {
  local arg
  ACTION=install
  for arg in "$@"; do
    case $arg in
    uninstall | --uninstall) ACTION=uninstall ;;
    install | --install) ACTION=install ;;
    clear | --clear) ACTION=clear ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      log_error_err "未知参数: $arg"
      usage >&2
      exit 2
      ;;
    esac
  done
}

purge_installed() {
  local -a present=() pkg
  step_note=""
  for pkg in "$@"; do
    pkg_installed "$pkg" && present+=("$pkg")
  done
  if ((${#present[@]} == 0)); then
    step_note="未安装"
    return 2
  fi
  root_ok || { step_note="需要 root"; return 1; }
  run_logged as_root apt-get purge -y "${APT_OPTS[@]}" "${present[@]}" || {
    step_note="卸载失败: ${present[*]}"
    return 1
  }
}

undo_edge() {
  local did=0
  if [[ -e /usr/bin/edge || -L /usr/bin/edge ]]; then
    as_root rm -f /usr/bin/edge || { step_note="删除 /usr/bin/edge 失败"; return 1; }
    did=1
  fi
  if [[ -e /etc/apt/sources.list.d/microsoft-edge.list ]]; then
    as_root rm -f /etc/apt/sources.list.d/microsoft-edge.list || { step_note="删除 Edge 软件源失败"; return 1; }
    did=1
  fi
  if [[ -e /usr/share/keyrings/microsoft-edge.gpg ]]; then
    as_root rm -f /usr/share/keyrings/microsoft-edge.gpg || { step_note="删除 Edge 密钥失败"; return 1; }
    did=1
  fi
  if pkg_installed microsoft-edge-dev || pkg_installed microsoft-edge; then
    purge_installed microsoft-edge-dev microsoft-edge || return 1
    did=1
  fi
  [[ $did == 1 ]] || { step_note="未安装"; return 2; }
}

undo_font() {
  local dest="$HOME/.local/share/fonts/JetBrains Mono Bold Nerd Font Complete Mono.ttf"
  if [[ ! -f $dest ]]; then
    step_note="未安装"
    return 2
  fi
  rm -f "$dest" || { step_note="删除字体失败"; return 1; }
  if command -v fc-cache >/dev/null 2>&1; then
    run_logged fc-cache -f "$HOME/.local/share/fonts" || true
  fi
}

undo_nvim() {
  local did=0 origin=""
  if [[ -d $HOME/.config/nvim/.git ]]; then
    origin=$(git -C "$HOME/.config/nvim" remote get-url origin 2>/dev/null || true)
    if [[ $origin == *mogeku/nvim* ]]; then
      rm -rf "$HOME/.config/nvim" || { step_note="删除 nvim 配置失败"; return 1; }
      did=1
    fi
  fi
  if pkg_installed neovim; then
    purge_installed neovim || return 1
    did=1
  fi
  [[ $did == 1 ]] || { step_note="未安装"; return 2; }
}

undo_yazi() {
  local did=0 f
  for f in "$HOME/.local/bin/yazi" "$HOME/.local/bin/ya" /usr/local/bin/yazi /usr/local/bin/ya; do
    if [[ -e $f || -L $f ]]; then
      if [[ $f == "$HOME"/* ]]; then
        rm -f "$f" || { step_note="删除 $f 失败"; return 1; }
      else
        as_root rm -f "$f" || { step_note="删除 $f 失败"; return 1; }
      fi
      did=1
    fi
  done
  if [[ -d $HOME/yazi/.git ]]; then
    rm -rf "$HOME/yazi" || { step_note="删除 ~/yazi 失败"; return 1; }
    did=1
  fi
  [[ $did == 1 ]] || { step_note="未安装"; return 2; }
}

undo_rust() {
  if [[ ! -x $HOME/.cargo/bin/rustup && ! -d $HOME/.cargo && ! -d $HOME/.rustup ]]; then
    step_note="未安装"
    return 2
  fi
  if [[ -x $HOME/.cargo/bin/rustup ]]; then
    run_logged "$HOME/.cargo/bin/rustup" self uninstall -y || true
  fi
  rm -rf "$HOME/.cargo" "$HOME/.rustup" || { step_note="删除 ~/.cargo 失败"; return 1; }
}

undo_user_links() {
  local did=0 f
  for f in "$HOME/.local/bin/dust" "$HOME/.local/bin/addssh" "$HOME/.local/bin/btm"; do
    if [[ -e $f || -L $f ]]; then
      rm -f "$f" || { step_note="删除 $f 失败"; return 1; }
      did=1
    fi
  done
  for f in /usr/local/bin/dust /usr/local/bin/addssh /usr/local/bin/btm; do
    if [[ -e $f || -L $f ]]; then
      as_root rm -f "$f" || { step_note="删除 $f 失败"; return 1; }
      did=1
    fi
  done
  if [[ -L /usr/local/bin/fd ]]; then
    as_root rm -f /usr/local/bin/fd || { step_note="删除 fd 链接失败"; return 1; }
    did=1
  fi
  if [[ -L /usr/local/bin/bat ]]; then
    as_root rm -f /usr/local/bin/bat || { step_note="删除 bat 链接失败"; return 1; }
    did=1
  fi
  if [[ -L /usr/bin/python ]] && ! dpkg -S /usr/bin/python >/dev/null 2>&1; then
    as_root rm -f /usr/bin/python || { step_note="删除 /usr/bin/python 失败"; return 1; }
    did=1
  fi
  [[ $did == 1 ]] || { step_note="没有链接"; return 2; }
}

undo_autojump() {
  if [[ ! -d $HOME/.autojump ]] && ! pkg_installed autojump; then
    step_note="未安装"
    return 2
  fi
  if [[ -f $HOME/.autojump/uninstall.py ]]; then
    run_logged python3 "$HOME/.autojump/uninstall.py" || true
  fi
  rm -rf "$HOME/.autojump" || { step_note="删除 ~/.autojump 失败"; return 1; }
  if pkg_installed autojump; then
    purge_installed autojump || return 1
  fi
}

undo_zsh() {
  local did=0 shell
  shell=$(getent passwd "${USER:-momo}" | awk -F: '{ print $NF }')
  if [[ $shell == *zsh ]]; then
    if [[ ! -x /bin/bash ]]; then
      step_note="登录 shell 是 zsh，且没有 /bin/bash，保留 zsh"
      return 1
    fi
    as_root chsh -s /bin/bash "${USER:-momo}" || {
      step_note="无法把登录 shell 改成 /bin/bash，保留 zsh"
      return 1
    }
    did=1
  fi
  if [[ -d $HOME/.oh-my-zsh ]]; then
    rm -rf "$HOME/.oh-my-zsh" || { step_note="删除 oh-my-zsh 失败"; return 1; }
    did=1
  fi
  if pkg_installed zsh; then
    purge_installed zsh || return 1
    did=1
  fi
  [[ $did == 1 ]] || { step_note="未安装"; return 2; }
}

undo_toolchain() {
  purge_installed \
    gcc g++ gdb clang make \
    tree fzf ripgrep xsel xclip bat eza duf httpie shellcheck apt-file fd-find figlet \
    fastfetch tealdeer neofetch tldr \
    nodejs npm \
    golang-go \
    python3-dev python3-pip \
    cmake lazygit
}

undo_shell_config() {
  local dest bak origin did=0
  for dest in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [[ -L $dest ]]; then
      rm -f "$dest" || { step_note="删除 $dest 失败"; return 1; }
      did=1
    fi
    bak=$(compgen -G "${dest}.bak.*" | sort -r | head -1 || true)
    if [[ -n $bak ]]; then
      mv "$bak" "$dest" || { step_note="恢复 $dest 失败"; return 1; }
      did=1
    fi
  done
  dest="$HOME/.config"
  bak=$(compgen -G "${dest}.bak.*" | sort -r | head -1 || true)
  if [[ -n $bak ]]; then
    rm -rf "$dest"
    mv "$bak" "$dest" || { step_note="恢复 ~/.config 失败"; return 1; }
    did=1
  elif [[ -d $dest/.git ]]; then
    origin=$(git -C "$dest" remote get-url origin 2>/dev/null || true)
    if [[ $origin == *mogeku/.config* ]]; then
      rm -rf "$dest" || { step_note="删除 ~/.config 失败"; return 1; }
      did=1
    fi
  fi
  [[ $did == 1 ]] || { step_note="没有改动"; return 2; }
}

undo_git_identity() {
  local email name did=0
  email=$(git config --global --get user.email 2>/dev/null || true)
  name=$(git config --global --get user.name 2>/dev/null || true)
  if [[ $email == "haomingzidougeixle@gmail.com" ]]; then
    git config --global --unset user.email || { step_note="清除 git email 失败"; return 1; }
    did=1
  fi
  if [[ $name == momo ]]; then
    git config --global --unset user.name || { step_note="清除 git name 失败"; return 1; }
    did=1
  fi
  [[ $did == 1 ]] || { step_note="不是本脚本写的"; return 2; }
}

undo_configs() {
  if [[ -f $CONFIG_MANIFEST ]]; then
    restore_configs || return 1
    if root_ok; then
      run_logged as_root apt-get update || { step_note="配置已恢复，apt update 失败"; return 1; }
    fi
    step_note="$CONFIG_BACKUP"
    return 0
  fi
  local rc=0 did=0 sub
  undo_shell_config
  sub=$?
  [[ $sub -eq 0 ]] && did=1
  [[ $sub -ne 0 && $sub -ne 2 ]] && rc=1
  undo_git_identity
  sub=$?
  [[ $sub -eq 0 ]] && did=1
  [[ $sub -ne 0 && $sub -ne 2 ]] && rc=1
  undo_apt_mirror
  sub=$?
  [[ $sub -eq 0 ]] && did=1
  [[ $sub -ne 0 && $sub -ne 2 ]] && rc=1
  if [[ $rc -ne 0 ]]; then
    step_note="没有安装前快照，按旧备份恢复失败"
    return 1
  fi
  if [[ $did -eq 0 ]]; then
    step_note="没有可恢复的备份"
    return 2
  fi
  step_note="没有安装前快照，已按旧备份恢复"
}

undo_apt_mirror() {
  if [[ ! -f $APT_BACKUP/sources.list ]] && ! compgen -G "$APT_BACKUP/sources.list.d/*" >/dev/null; then
    step_note="没有软件源备份"
    return 2
  fi
  restore_apt_sources || { step_note="恢复软件源失败"; return 1; }
  as_root rm -f /etc/apt/sources.list.d/microsoft-edge.list /usr/share/keyrings/microsoft-edge.gpg || true
  run_logged as_root apt-get update || { step_note="apt update 失败"; return 1; }
}

undo_autoremove() {
  root_ok || { step_note="需要 root"; return 1; }
  run_logged as_root apt-get autoremove -y "${APT_OPTS[@]}" || { step_note="autoremove 失败"; return 1; }
}

run_uninstall() {
  add_step uEdge "Microsoft Edge" "" undo_edge
  add_step uFont "Nerd Font" "" undo_font
  add_step uNvim "Neovim" "" undo_nvim
  add_step uYazi "yazi" "" undo_yazi
  add_step uRust "Rust" "" undo_rust
  add_step uLinks "dust / addssh / bottom 链接" "" undo_user_links
  add_step uJump "autojump" "" undo_autojump
  add_step uZsh "zsh 与 oh-my-zsh" "" undo_zsh
  add_step uPkgs "工具链与语言包" "" undo_toolchain
  add_step uCfg "恢复配置文件" "" undo_configs
  add_step uAuto "清理不再需要的依赖" "" undo_autoremove

  local total=${#STEP_IDS[@]} i=0 id title fn rc note
  for id in "${STEP_IDS[@]}"; do
    i=$((i + 1))
    title=${STEP_TITLE[$id]}
    fn=${STEP_FN[$id]}
    step_note=""
    log "===== undo ${id} ${title} ====="
    print_running "$i" "$total" "$title"
    STEP_TAG="${EMOJI_CLEAN} ${title}"
    "$fn"
    rc=$?
    STEP_TAG=""
    note=$(sanitize "$step_note")
    if [[ $rc -eq 0 ]]; then
      OK_IDS+=("$id")
      print_result "$i" "$total" ok "$title" "$note"
    elif [[ $rc -eq 2 ]]; then
      SKIP_IDS+=("$id")
      print_result "$i" "$total" skip "$title" "${note:-未安装}"
    else
      FAIL_IDS+=("$id")
      print_result "$i" "$total" fail "$title" "${note:-失败}"
    fi
  done
}

# ---------- runner ----------

first_blocker() {
  local deps=$1 dep
  [[ -z $deps ]] && return 1
  IFS=',' read -ra _deps <<<"$deps"
  for dep in "${_deps[@]}"; do
    [[ -z $dep ]] && continue
    if [[ ${STEP_STATUS[$dep]:-} != ok ]]; then
      printf '%s' "$dep"
      return 0
    fi
  done
  return 1
}

print_running() {
  local idx=$1 total=$2 title=$3
  sgr_reset
  printf '  %s%02d%s/%02d  %s  %s\n' \
    "$DIM" "$idx" "$RESET" "$total" \
    "$EMOJI_WAIT" \
    "$(pad_col "$title" 28)"
}

print_result() {
  local idx=$1 total=$2 status=$3 title=$4 note=$5
  local icon color
  case $status in
  ok)
    icon=$EMOJI_SUCCESS
    color=$BOLD_GREEN
    ;;
  fail)
    icon=$EMOJI_ERROR
    color=$BOLD_RED
    ;;
  skip)
    case $note in
    已完成)
      icon=$EMOJI_SUCCESS
      color=$DIM
      ;;
    未选择|未选择安装|未启用)
      icon=$EMOJI_SKIP
      color=$DIM
      ;;
    *)
      icon=$EMOJI_WARN
      color=$BOLD_YELLOW
      ;;
    esac
    ;;
  *)
    icon=$EMOJI_WARN
    color=$BOLD_YELLOW
    ;;
  esac
  sgr_reset
  printf '  %s%02d%s/%02d  %s%s%s  %s' \
    "$DIM" "$idx" "$RESET" "$total" \
    "$color" "$icon" "$RESET" \
    "$(pad_col "$title" 28)"
  if [[ -n $note ]]; then
    printf '  %s%s%s' "$DIM" "$note" "$RESET"
  fi
  printf '\n'
}

run_steps() {
  local total=${#STEP_IDS[@]} i=0 id title deps fn blocker note rc
  for id in "${STEP_IDS[@]}"; do
    i=$((i + 1))
    title=${STEP_TITLE[$id]}
    deps=${STEP_DEPS[$id]}
    fn=${STEP_FN[$id]}
    hash -r || true

    if [[ $id == sshKey && ${USE_SSH_KEY:-0} != 1 ]]; then
      STEP_STATUS[$id]=ok
      STEP_SHOWN[$id]="未选择"
      SKIP_IDS+=("$id")
      print_result "$i" "$total" skip "$title" "未选择"
      continue
    fi
    if [[ $id == yazi && ${USE_YAZI:-0} != 1 ]]; then
      STEP_STATUS[$id]=ok
      STEP_SHOWN[$id]="未选择安装"
      SKIP_IDS+=("$id")
      print_result "$i" "$total" skip "$title" "未选择安装"
      continue
    fi
    if [[ $id == edge && ${USE_EDGE:-0} != 1 ]]; then
      STEP_STATUS[$id]=ok
      STEP_SHOWN[$id]="未选择安装"
      SKIP_IDS+=("$id")
      print_result "$i" "$total" skip "$title" "未选择安装"
      continue
    fi

    local skip_done=1
    if [[ $id == sshKey || $id == osCheck ]]; then
      skip_done=0
    fi
    if [[ $id == aptMirror && ${USE_APT_MIRROR:-0} == 1 && -n ${APT_SOURCE:-} ]]; then
      if ! grep -RqsF -- "$APT_SOURCE" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
        skip_done=0
      fi
    fi
    if [[ $skip_done == 1 && ${SETUP_FORCE:-0} != 1 && ${SAVED_STATUS[$id]:-} == ok ]]; then
      STEP_STATUS[$id]=ok
      STEP_SHOWN[$id]="已完成"
      SKIP_IDS+=("$id")
      print_result "$i" "$total" skip "$title" "已完成"
      continue
    fi

    blocker=$(first_blocker "$deps" || true)
    if [[ -n $blocker ]]; then
      STEP_STATUS[$id]=blocked
      note="依赖「${STEP_TITLE[$blocker]}」未完成"
      STEP_SHOWN[$id]=$note
      SKIP_IDS+=("$id")
      print_result "$i" "$total" skip "$title" "$note"
      continue
    fi

    step_note=""
    log "===== ${id} ${title} ====="
    print_running "$i" "$total" "$title"
    STEP_TAG="${EMOJI_PKG} ${title}"
    "$fn"
    rc=$?
    STEP_TAG=""
    note=$(sanitize "$step_note")
    STEP_SHOWN[$id]=$note
    if [[ $rc -eq 0 ]]; then
      STEP_STATUS[$id]=ok
      state_set "$id" ok "$note"
      OK_IDS+=("$id")
      print_result "$i" "$total" ok "$title" "$note"
    elif [[ $rc -eq 2 ]]; then
      STEP_STATUS[$id]=ok
      SKIP_IDS+=("$id")
      print_result "$i" "$total" skip "$title" "${note:-跳过}"
    else
      STEP_STATUS[$id]=fail
      state_set "$id" fail "${note:-失败}"
      FAIL_IDS+=("$id")
      print_result "$i" "$total" fail "$title" "${note:-失败}"
    fi
  done
}

print_group() {
  local heading=$1 color=$2 icon=$3
  shift 3
  local -a ids=("$@")
  local id
  printf '  %s%s %s %d%s\n' "$color" "$icon" "$heading" "${#ids[@]}" "$RESET"
  for id in "${ids[@]}"; do
    if [[ -n ${STEP_SHOWN[$id]:-} ]]; then
      printf '    %s  %s%s%s\n' "$(pad_col "${STEP_TITLE[$id]}" 28)" "$DIM" "${STEP_SHOWN[$id]}" "$RESET"
    else
      printf '    %s\n' "${STEP_TITLE[$id]}"
    fi
  done
}

summary() {
  printf '\n'
  rule
  printf '  %s%s%s  %s结果%s\n' "$BOLD_PURPLE" "$EMOJI_PARTY" "$RESET" "$BOLD" "$RESET"
  rule
  printf '\n'
  print_group "成功" "$BOLD_GREEN" "$EMOJI_SUCCESS" "${OK_IDS[@]}"
  printf '\n'
  print_group "失败" "$BOLD_RED" "$EMOJI_ERROR" "${FAIL_IDS[@]}"
  printf '\n'
  print_group "跳过" "$BOLD_YELLOW" "$EMOJI_SKIP" "${SKIP_IDS[@]}"
  printf '\n'
  kv "$EMOJI_NOTE" "日志" "$LOG_FILE"
  printf '\n'
}

lock_pids() {
  fuser "$STATE_DIR/lock" 2>/dev/null | tr -cs '0-9' '\n'
}

proc_ppid() {
  awk '/^PPid:/ { print $2; exit }' "/proc/$1/status" 2>/dev/null || echo 1
}

proc_cmd() {
  tr '\0' ' ' <"/proc/$1/cmdline" 2>/dev/null || true
}

lock_held_by_live_setup() {
  local pid ppid cmd state
  while read -r pid; do
    [[ $pid =~ ^[0-9]+$ ]] || continue
    [[ $pid == $$ ]] && continue
    state=$(proc_state "$pid")
    # T：写终端时被 SIGTTOU 停住，或 Ctrl+Z。已经不在安装。
    [[ $state == T || $state == t ]] && continue
    ppid=$(proc_ppid "$pid")
    cmd=$(proc_cmd "$pid")
    if [[ $ppid != 1 && ( $cmd == *setup.sh* || $cmd == *flock* ) ]]; then
      return 0
    fi
  done < <(lock_pids)
  return 1
}

# flock -o：锁 fd 不传给子进程。否则 sleep 60 / sleep 0.2 会把锁一直拿着。
# 强制杀掉脚本后，残留进程的父进程会变成 1，下次启动直接清掉。
# 有时锁还留在 inode 上，但已经没有任何进程打开它，这时删掉锁文件重建。
recover_stale_lock() {
  local pid
  local -a stale=()
  if lock_held_by_live_setup; then
    return 0
  fi
  while read -r pid; do
    [[ $pid =~ ^[0-9]+$ ]] || continue
    [[ $pid == $$ ]] && continue
    stale+=("$pid")
  done < <(lock_pids)
  if ((${#stale[@]})); then
    log_warn_err "清理上次强制退出留下的进程：${stale[*]}"
    kill "${stale[@]}" 2>/dev/null || true
    sleep 0.2
    kill -9 "${stale[@]}" 2>/dev/null || true
    sleep 0.2
  fi
}

run_under_lock() {
  local cmd held=$STATE_DIR/lock.held rc zsh_bin script_path=$0 tmp_script=""
  if [[ ! -f $script_path || $script_path == bash || $script_path == */bash ]]; then
    if [[ -z ${BASH_EXECUTION_STRING:-} ]]; then
      log_error_err "无法持锁重入。用 bash -c \"\$(curl -fsSL ...)\"，不要把脚本管道喂给 bash"
      exit 1
    fi
    tmp_script=$(mktemp "${TMPDIR:-/tmp}/ubuntu-setup.XXXXXX.sh")
    printf '%s\n' "$BASH_EXECUTION_STRING" >"$tmp_script"
    script_path=$tmp_script
  fi
  printf -v cmd '%q ' env SETUP_LOCK_HELD=1 bash "$script_path" "$@"
  rm -f "$held"
  flock -n -o "$STATE_DIR/lock" -c "touch $(printf %q "$held") && $cmd"
  rc=$?
  [[ -n $tmp_script ]] && rm -f "$tmp_script"

  if [[ $rc -eq 1 && ! -f $held ]]; then
    return 1
  fi
  if [[ -f $STATE_DIR/launch-zsh ]]; then
    zsh_bin=$(head -n 1 "$STATE_DIR/launch-zsh")
    rm -f "$STATE_DIR/launch-zsh"
    if [[ -x $zsh_bin && -t 0 && -t 1 ]]; then
      trap - EXIT INT TERM
      on_exit
      printf '\n%s%s%s 进入 zsh，加载 %s%s%s\n' \
        "$BOLD_GREEN" "$EMOJI_SUCCESS" "$RESET" "$BOLD" "$HOME/.zshrc" "$RESET"
      exec "$zsh_bin" -l
    fi
  fi
  exit "$rc"
}

enter_locked() {
  if run_under_lock "$@"; then
    return 0
  fi
  if lock_held_by_live_setup; then
    log_error_err "已有 setup.sh 在运行"
    fuser -v "$STATE_DIR/lock" >&2 || true
    exit 1
  fi
  log_warn_err "上次的锁已失效，重新创建"
  rm -f "$STATE_DIR/lock"
  if run_under_lock "$@"; then
    return 0
  fi
  log_error_err "已有 setup.sh 在运行"
  fuser -v "$STATE_DIR/lock" >&2 || true
  exit 1
}

finish_into_zsh() {
  local zsh_bin shell
  if [[ -x /usr/bin/zsh ]]; then
    zsh_bin=/usr/bin/zsh
  elif [[ -x /bin/zsh ]]; then
    zsh_bin=/bin/zsh
  else
    log_warn "zsh 未安装，保持当前 shell"
    return 0
  fi
  if ! grep -qxF "$zsh_bin" /etc/shells 2>/dev/null; then
    log_error_err "未改登录 shell：${zsh_bin} 不在 /etc/shells"
  else
    shell=$(getent passwd "${USER:-momo}" | awk -F: '{ print $NF }')
    if [[ $shell != *zsh ]]; then
      if as_root chsh -s "$zsh_bin" "${USER:-momo}"; then
        log_success "登录 shell 已改为 $zsh_bin"
      else
        log_error_err "切换登录 shell 失败"
      fi
    fi
  fi
  [[ -t 0 && -t 1 ]] || return 0
  printf '%s\n' "$zsh_bin" >"$STATE_DIR/launch-zsh"
}

main() {
  parse_args "$@"
  arm_traps
  tty_fix
  start_isig_keeper
  mkdir -p "$STATE_DIR" "$STATE_DIR/cache" "$STATE_DIR/src"
  if [[ ${SETUP_LOCK_HELD:-} != 1 ]]; then
    recover_stale_lock
    enter_locked "$@"
  fi
  rm -f "$STATE_DIR/launch-zsh"
  touch "$LOG_FILE"
  log "######## session $(date -Iseconds) ACTION=$ACTION ########"

  if [[ $ACTION == clear ]]; then
    if [[ -f $CHOICE_FILE ]]; then
      rm -f "$CHOICE_FILE"
      log_success "已清空选择 $CHOICE_FILE"
    else
      log_warn "没有已保存的选择"
    fi
    exit 0
  fi

  if [[ $ACTION == uninstall ]]; then
    print_banner "ubuntu setup uninstall" "卸掉本脚本添加的组件。git、curl、python3 和已经升级过的系统包会留下。"
    kv "$EMOJI_NOTE" "日志" "$LOG_FILE"
    printf '\n'
    if ! ensure_sudo; then
      log_warn "sudo 未通过。需要 root 的步骤会失败，其余继续。"
      printf '\n'
    fi
    run_uninstall
    printf '\n'
    summary
    if ((${#FAIL_IDS[@]})); then
      exit 1
    fi
    rm -rf "$STATE_DIR"
    log_success "已删除 $STATE_DIR"
    exit 0
  fi

  state_load
  load_choices

  print_banner "ubuntu setup" "可重复执行 · 已完成的步骤会跳过 · 失败的步骤会重试"
  kv "$EMOJI_LIST" "状态" "$STATE_FILE"
  kv "$EMOJI_NOTE" "日志" "$LOG_FILE"
  if ! snapshot_configs; then
    log_error_err "配置备份失败，已停止。"
    exit 1
  fi
  kv "$EMOJI_GEAR" "配置备份" "$CONFIG_BACKUP"
  printf '\n'
  choice_rows full
  printf '\n'
  if ! ensure_sudo; then
    log_warn "sudo 未通过。需要 root 的步骤会失败，其余继续。"
    printf '\n'
  fi

  # deps 是硬依赖：前置不是 ok，本步跳过。未列入的失败不挡住本步。
  add_step sshKey "GitHub SSH 密钥" "" step_ssh_key
  add_step osCheck "系统检查" "" step_os_check
  add_step basePkgs "基础包 git/curl/wget" "osCheck" step_base_pkgs
  add_step gitIdentity "Git 身份" "basePkgs" step_git_identity
  add_step pullScript "拉取 ~/script" "basePkgs" step_pull_script
  add_step pullConfig "同步 ~/.config" "basePkgs" step_pull_config
  add_step aptMirror "更换 APT 软件源" "basePkgs" step_apt_mirror
  add_step aptUpdate "更新软件列表" "basePkgs" step_apt_update
  add_step aptUpgrade "升级已安装软件" "aptUpdate" step_apt_upgrade
  add_step cpp "C/C++ 工具链" "aptUpdate" step_cpp
  add_step cli "命令行工具" "aptUpdate" step_cli
  add_step bottom "bottom" "basePkgs" step_bottom
  add_step zsh "zsh 与 oh-my-zsh" "basePkgs" step_zsh
  add_step node "Node.js" "aptUpdate" step_node
  add_step golang "Go" "aptUpdate" step_golang
  add_step python "Python 3" "aptUpdate" step_python
  add_step cmake "CMake" "aptUpdate" step_cmake
  add_step lazygit "lazygit" "aptUpdate" step_lazygit
  add_step autojump "autojump" "basePkgs" step_autojump
  add_step dustLink "dust 链接" "pullConfig" step_dust
  add_step addssh "addssh 链接" "pullScript" step_addssh
  add_step rustup "Rust" "basePkgs" step_rustup
  add_step yazi "yazi" "basePkgs" step_yazi
  add_step nvim "Neovim" "basePkgs" step_nvim
  add_step nerdFont "Nerd Font" "pullConfig" step_nerd_font
  add_step edge "Microsoft Edge" "aptUpdate" step_edge
  add_step aptClean "清理 APT 缓存" "aptUpdate" step_apt_clean

  run_steps

  printf '\n'
  if command -v fastfetch >/dev/null 2>&1; then
    fastfetch || true
    printf '\n'
  elif command -v neofetch >/dev/null 2>&1; then
    neofetch || true
    printf '\n'
  fi
  summary
  finish_into_zsh
  if ((${#FAIL_IDS[@]})); then
    exit 1
  fi
}

main "$@"
