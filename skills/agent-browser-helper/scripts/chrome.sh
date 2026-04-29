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

cfg_set() {
    local key="$1" value="$2"
    local tmp; tmp=$(mktemp)
    jq "$key = \"$value\"" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
}

get_extra_args() {
    if [[ -f "$CONFIG_FILE" ]]; then
        jq -r '.browser.extraArgs // [] | .[]' "$CONFIG_FILE" 2>/dev/null
    fi
}

# --- Browser resolution ---
# Priority: config browserPath > detection with user confirmation
find_browser() {
    # 1. Check configured browserPath
    local configured
    configured="$(cfg_get '.browser.browserPath')"
    if [[ -n "$configured" ]]; then
        if [[ -x "$configured" ]] || [[ -f "$configured" ]]; then
            echo "$configured"; return 0
        fi
        echo "ERROR: Configured browserPath '$configured' is not executable. Run: chrome.sh detect" >&2
        return 1
    fi

    # 2. browserPath is empty — require detection
    echo "NEEDS_DETECTION"
    return 0
}

cmd_detect() {
    local result
    result="$(bash "$SCRIPTS/detect-browsers.sh" 2>/dev/null)" || {
        echo '{"error":"No browsers found. Install a Chromium-based browser or set browserPath in config.json"}'
        return 1
    }

    local count
    count=$(echo "$result" | jq '.browsers | length')
    if [[ "$count" -eq 0 ]]; then
        echo '{"error":"No browsers found. Install a Chromium-based browser or set browserPath in config.json"}'
        return 1
    fi

    echo "$result" | jq '{
        action_required: "select_browser",
        message: "Multiple browsers detected. Ask the user which one to use, then call: chrome.sh set-browser <number>",
        browsers: [.browsers | to_entries[] | {index: (.key + 1), name: .value.name, path: .value.path, version: .value.version}]
    }'
}

cmd_set_browser() {
    local choice="${1:-}"
    if [[ -z "$choice" ]]; then
        echo '{"error":"Usage: chrome.sh set-browser <number> OR chrome.sh set-browser <path>"}'; return 1
    fi

    # If it's a number, resolve from detection
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
        local result
        result="$(bash "$SCRIPTS/detect-browsers.sh" 2>/dev/null)" || { echo '{"error":"Detection failed"}'; return 1; }
        local path
        path=$(echo "$result" | jq -r ".browsers[$((choice - 1))].path // empty")
        if [[ -z "$path" ]]; then
            echo "{\"error\":\"Invalid selection: $choice\"}"; return 1
        fi
        cfg_set '.browser.browserPath' "$path"
        echo "{\"status\":\"configured\",\"browserPath\":\"$path\"}"
    else
        # Direct path provided
        if [[ -x "$choice" ]] || [[ -f "$choice" ]]; then
            cfg_set '.browser.browserPath' "$choice"
            echo "{\"status\":\"configured\",\"browserPath\":\"$choice\"}"
        else
            echo "{\"error\":\"Path not found or not executable: $choice\"}"; return 1
        fi
    fi
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
    _PORT="${_PORT:-19222}"
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

    if [[ -f "$pid_file" ]] && is_cdp_ready "$_PORT"; then
        echo "{\"status\":\"already_running\",\"pid\":$(cat "$pid_file"),\"cdpPort\":$_PORT,\"profile\":\"$_PROFILE\"}"
        return 0
    fi

    # Resolve browser — if not configured, run detection
    local chrome
    chrome="$(find_browser)"
    if [[ "$chrome" == "NEEDS_DETECTION" ]]; then
        cmd_detect
        return 1
    fi

    local user_data_dir; user_data_dir="$(get_user_data_dir)"
    mkdir -p "$user_data_dir" "$(dirname "$pid_file")"

    # For Windows browsers (.exe), use a Windows-native path for user-data-dir
    # UNC paths (\\wsl.localhost\...) fail with LockFileEx errors
    local launch_data_dir="$user_data_dir"
    if [[ "$chrome" == *.exe ]]; then
        local win_appdata
        win_appdata=$(/mnt/c/Windows/System32/cmd.exe /c "echo %LOCALAPPDATA%" 2>/dev/null | tr -d '\r')
        if [[ -n "$win_appdata" ]]; then
            launch_data_dir="${win_appdata}\\agent-browser-helper\\${_PROFILE}"
        fi
    fi

    # Auto-increment port if already in use
    while ss -tlnp 2>/dev/null | grep -q ":$_PORT " || is_cdp_ready "$_PORT"; do
        _PORT=$((_PORT + 1))
    done

    local args=(
        "$chrome"
        "--remote-debugging-port=$_PORT"
        "--user-data-dir=$launch_data_dir"
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
    if [[ "$(cfg_get '.browser.noSandbox')" == "true" ]] && [[ "$chrome" != *.exe ]]; then
        args+=("--no-sandbox" "--disable-setuid-sandbox")
    fi
    [[ "$(uname)" == "Linux" ]] && [[ "$chrome" != *.exe ]] && args+=("--disable-dev-shm-usage")

    while IFS= read -r extra; do
        [[ -n "$extra" ]] && args+=("$extra")
    done < <(get_extra_args)

    "${args[@]}" </dev/null &>/dev/null &
    local pid=$!
    echo "$pid" > "$pid_file"

    local is_win_exe=false
    [[ "$chrome" == *.exe ]] && is_win_exe=true

    local elapsed=0
    while ! is_cdp_ready "$_PORT" && (( elapsed < 30 )); do
        sleep 0.5; elapsed=$((elapsed + 1))
        # For Windows .exe, the WSL PID exits immediately — only check CDP
        if [[ "$is_win_exe" == false ]] && ! kill -0 "$pid" 2>/dev/null; then
            rm -f "$pid_file"
            echo "{\"error\":\"Chrome exited unexpectedly\"}" >&2; exit 1
        fi
    done

    if ! is_cdp_ready "$_PORT"; then
        kill "$pid" 2>/dev/null; rm -f "$pid_file"
        echo "{\"error\":\"CDP not ready after 15s\"}" >&2; exit 1
    fi

    local skill_hint=""
    if ! command -v playwright-cli &>/dev/null; then
        skill_hint="playwright-cli not found. Install: npx skills add microsoft/playwright-cli@playwright-cli -g -y && npm i -g @playwright/cli@latest"
    fi

    echo "{\"status\":\"started\",\"pid\":$pid,\"cdpPort\":$_PORT,\"profile\":\"$_PROFILE\",\"userDataDir\":\"$(get_user_data_dir)\"$([ -n "$skill_hint" ] && echo ",\"warning\":\"$skill_hint\"")}"
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
    echo "{\"running\":$running,\"pid\":$pid,\"cdpPort\":$_PORT,\"profile\":\"$_PROFILE\",\"browser\":\"$browser\",\"browserPath\":\"$(cfg_get '.browser.browserPath')\"}"
}

# --- Dispatch ---
case "${1:-help}" in
    start)       shift; cmd_start "$@" ;;
    stop)        shift; cmd_stop "$@" ;;
    status)      shift; cmd_status "$@" ;;
    detect)      shift; cmd_detect ;;
    set-browser) shift; cmd_set_browser "$@" ;;
    *)           echo "Usage: chrome.sh {start|stop|status|detect|set-browser} [--profile NAME] [--port PORT] [--headless]" ;;
esac
