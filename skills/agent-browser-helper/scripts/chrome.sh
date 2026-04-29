#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_HOME="${AGENT_BROWSER_HELPER_HOME:-$HOME/.agent-browser-helper}"
CONFIG_FILE="${AGENT_BROWSER_HELPER_CONFIG:-$SKILL_DIR/config.json}"

# --- Config helpers ---
cfg_get() {
    if [[ -f "$CONFIG_FILE" ]]; then
        jq -r "$1 // empty" "$CONFIG_FILE" 2>/dev/null
    fi
}

get_extra_args() {
    if [[ -f "$CONFIG_FILE" ]]; then
        jq -r '.browser.extraArgs // [] | .[]' "$CONFIG_FILE" 2>/dev/null
    fi
}

find_chrome() {
    local custom
    custom="$(cfg_get '.browser.executablePath')"
    if [[ -n "$custom" && -x "$custom" ]]; then echo "$custom"; return; fi
    for bin in google-chrome google-chrome-stable chromium-browser chromium microsoft-edge; do
        if command -v "$bin" &>/dev/null; then echo "$bin"; return; fi
    done
    echo "ERROR: Chrome not found" >&2; return 1
}

# --- Argument parsing ---
_PROFILE="" _PORT="" _HEADLESS=""
POSITIONAL=()

parse_flags() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --profile)  _PROFILE="$2"; shift 2 ;;
            --port)     _PORT="$2"; shift 2 ;;
            --headless) _HEADLESS="true"; shift ;;
            *)          POSITIONAL+=("$1"); shift ;;
        esac
    done
}

resolve() {
    _PROFILE="${_PROFILE:-$(cfg_get '.browser.defaultProfile')}"
    _PROFILE="${_PROFILE:-default}"
    if [[ -z "$_PORT" ]]; then
        _PORT="$(cfg_get ".browser.profiles.\"$_PROFILE\".cdpPort")"
    fi
    _PORT="${_PORT:-9222}"
}

get_user_data_dir() {
    local p
    p="$(cfg_get ".browser.profiles.\"$_PROFILE\".userDataDir")"
    echo "${p:-$DATA_HOME/$_PROFILE/user-data}"
}

get_pid_file() { echo "$DATA_HOME/$_PROFILE/chrome.pid"; }

is_cdp_ready() { curl -s --max-time 2 "http://127.0.0.1:${1}/json/version" &>/dev/null; }

# --- Commands ---

cmd_start() {
    parse_flags "$@"; resolve
    local pid_file; pid_file="$(get_pid_file)"

    if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null && is_cdp_ready "$_PORT"; then
        echo "{\"status\":\"already_running\",\"pid\":$(cat "$pid_file"),\"cdpPort\":$_PORT,\"profile\":\"$_PROFILE\"}"
        return 0
    fi

    local chrome; chrome="$(find_chrome)" || exit 1
    local user_data_dir; user_data_dir="$(get_user_data_dir)"
    mkdir -p "$user_data_dir" "$(dirname "$pid_file")"

    local args=(
        "$chrome"
        "--remote-debugging-port=$_PORT"
        "--user-data-dir=$user_data_dir"
        "--no-first-run"
        "--no-default-browser-check"
        "--disable-sync"
        "--disable-background-networking"
        "--disable-features=Translate,MediaRouter"
        "--hide-crash-restore-bubble"
    )

    if [[ "$_HEADLESS" == "true" ]] || [[ "$(cfg_get '.browser.headless')" == "true" ]]; then
        args+=("--headless=new" "--disable-gpu")
    fi
    if [[ "$(cfg_get '.browser.noSandbox')" == "true" ]]; then
        args+=("--no-sandbox" "--disable-setuid-sandbox")
    fi
    [[ "$(uname)" == "Linux" ]] && args+=("--disable-dev-shm-usage")

    while IFS= read -r extra; do
        [[ -n "$extra" ]] && args+=("$extra")
    done < <(get_extra_args)

    "${args[@]}" &>/dev/null &
    local pid=$!
    echo "$pid" > "$pid_file"

    local elapsed=0
    while ! is_cdp_ready "$_PORT" && (( elapsed < 30 )); do
        sleep 0.5; elapsed=$((elapsed + 1))
        if ! kill -0 "$pid" 2>/dev/null; then
            rm -f "$pid_file"
            echo "{\"error\":\"Chrome exited unexpectedly\"}" >&2; exit 1
        fi
    done

    if ! is_cdp_ready "$_PORT"; then
        kill "$pid" 2>/dev/null; rm -f "$pid_file"
        echo "{\"error\":\"CDP not ready after 15s\"}" >&2; exit 1
    fi

    # Check agent-browser availability
    local ab_status="installed"
    if ! command -v agent-browser &>/dev/null; then
        ab_status="cli_missing"
    fi
    local skill_hint=""
    if [[ ! -d "$HOME/.agents/skills/agent-browser" ]] && [[ ! -f "$HOME/.kiro/skills/agent-browser/SKILL.md" ]]; then
        skill_hint="agent-browser skill not found. Install: npx skills add vercel-labs/agent-browser@agent-browser -g -y"
    fi

    echo "{\"status\":\"started\",\"pid\":$pid,\"cdpPort\":$_PORT,\"profile\":\"$_PROFILE\",\"userDataDir\":\"$(get_user_data_dir)\",\"agentBrowser\":\"$ab_status\"$([ -n "$skill_hint" ] && echo ",\"warning\":\"$skill_hint\""),\"next\":\"Load agent-browser docs: agent-browser skills get core\"}"
}

cmd_stop() {
    parse_flags "$@"; resolve
    local pid_file; pid_file="$(get_pid_file)"

    if [[ ! -f "$pid_file" ]]; then
        echo "{\"status\":\"not_running\",\"profile\":\"$_PROFILE\"}"; return 0
    fi

    local pid; pid="$(cat "$pid_file")"
    if ! kill -0 "$pid" 2>/dev/null; then
        rm -f "$pid_file"
        echo "{\"status\":\"not_running\",\"profile\":\"$_PROFILE\"}"; return 0
    fi

    kill "$pid" 2>/dev/null
    local i=0; while kill -0 "$pid" 2>/dev/null && (( i < 10 )); do sleep 0.5; i=$((i+1)); done
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
    rm -f "$pid_file"
    echo "{\"status\":\"stopped\",\"pid\":$pid,\"profile\":\"$_PROFILE\"}"
}

cmd_status() {
    parse_flags "$@"; resolve
    local pid_file; pid_file="$(get_pid_file)"
    local running=false pid=0 browser=""

    if [[ -f "$pid_file" ]]; then
        pid="$(cat "$pid_file")"
        kill -0 "$pid" 2>/dev/null && running=true || { rm -f "$pid_file"; pid=0; }
    fi
    if is_cdp_ready "$_PORT"; then
        browser="$(curl -s "http://127.0.0.1:$_PORT/json/version" | jq -r '.Browser // "unknown"')"
    fi
    echo "{\"running\":$running,\"pid\":$pid,\"cdpPort\":$_PORT,\"profile\":\"$_PROFILE\",\"browser\":\"$browser\"}"
}

# --- Dispatch ---
case "${1:-help}" in
    start)  shift; cmd_start "$@" ;;
    stop)   shift; cmd_stop "$@" ;;
    status) shift; cmd_status "$@" ;;
    *)      echo "Usage: chrome.sh {start|stop|status} [--profile NAME] [--port PORT] [--headless]" ;;
esac
