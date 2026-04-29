#!/usr/bin/env bash
# detect-browsers.sh — Scan for Chromium-based browsers on Linux, macOS, and Windows (WSL)
set -euo pipefail

declare -a FOUND=()

check_path() {
    local path="$1" name="$2"
    if [[ -x "$path" ]] || [[ -f "$path" ]]; then
        local version=""
        # Skip --version for Windows .exe (may hang or launch GUI)
        if [[ "$path" != *.exe ]]; then
            version=$(timeout 3 "$path" --version 2>/dev/null | tr -d '\n\r\t' | head -c 100 || true)
        fi
        version="${version//\\/\\\\}"
        version="${version//\"/\\\"}"
        FOUND+=("{\"name\":\"$name\",\"path\":\"$path\",\"version\":\"$version\"}")
    fi
}

OS="$(uname -s)"

# --- Linux / WSL: PATH lookup ---
if [[ "$OS" == "Linux" ]]; then
    for bin in google-chrome google-chrome-stable google-chrome-beta google-chrome-dev \
               chromium-browser chromium microsoft-edge microsoft-edge-stable microsoft-edge-beta \
               brave-browser brave-browser-stable vivaldi vivaldi-stable opera; do
        p="$(command -v "$bin" 2>/dev/null || true)"
        [[ -n "$p" ]] && check_path "$p" "$bin"
    done

    # Common Linux install paths
    LINUX_PATHS=(
        "/opt/google/chrome/chrome:Google Chrome"
        "/opt/google/chrome-beta/chrome:Google Chrome Beta"
        "/opt/google/chrome-unstable/chrome:Google Chrome Dev"
        "/usr/bin/chromium-browser:Chromium"
        "/usr/bin/chromium:Chromium"
        "/snap/bin/chromium:Chromium (snap)"
        "/usr/bin/microsoft-edge:Microsoft Edge"
        "/opt/microsoft/msedge/msedge:Microsoft Edge"
        "/usr/bin/brave-browser:Brave"
        "/opt/brave.com/brave/brave-browser:Brave"
        "/usr/bin/vivaldi:Vivaldi"
        "/opt/vivaldi/vivaldi:Vivaldi"
    )
    for entry in "${LINUX_PATHS[@]}"; do
        path="${entry%%:*}"; name="${entry#*:}"
        check_path "$path" "$name"
    done

    # Windows browsers via WSL
    if [[ -d "/mnt/c/Program Files" ]]; then
        WIN_PATHS=(
            "/mnt/c/Program Files/Google/Chrome/Application/chrome.exe:Google Chrome (Windows)"
            "/mnt/c/Program Files (x86)/Google/Chrome/Application/chrome.exe:Google Chrome (Windows x86)"
            "/mnt/c/Program Files/Microsoft/Edge/Application/msedge.exe:Microsoft Edge (Windows)"
            "/mnt/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe:Microsoft Edge (Windows x86)"
            "/mnt/c/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe:Brave (Windows)"
            "/mnt/c/Program Files/Vivaldi/Application/vivaldi.exe:Vivaldi (Windows)"
            "/mnt/c/Program Files/Chromium/Application/chrome.exe:Chromium (Windows)"
        )
        for entry in "${WIN_PATHS[@]}"; do
            path="${entry%%:*}"; name="${entry#*:}"
            check_path "$path" "$name"
        done
        # User-level installs
        for udir in /mnt/c/Users/*/AppData/Local/Google/Chrome/Application/chrome.exe; do
            [[ -f "$udir" ]] && check_path "$udir" "Google Chrome (Windows User)"
        done
        for udir in /mnt/c/Users/*/AppData/Local/Microsoft/Edge/Application/msedge.exe; do
            [[ -f "$udir" ]] && check_path "$udir" "Microsoft Edge (Windows User)"
        done
        for udir in /mnt/c/Users/*/AppData/Local/BraveSoftware/Brave-Browser/Application/brave.exe; do
            [[ -f "$udir" ]] && check_path "$udir" "Brave (Windows User)"
        done
    fi
fi

# --- macOS ---
if [[ "$OS" == "Darwin" ]]; then
    MAC_PATHS=(
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome:Google Chrome"
        "/Applications/Google Chrome Beta.app/Contents/MacOS/Google Chrome Beta:Google Chrome Beta"
        "/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary:Google Chrome Canary"
        "/Applications/Chromium.app/Contents/MacOS/Chromium:Chromium"
        "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge:Microsoft Edge"
        "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser:Brave"
        "/Applications/Vivaldi.app/Contents/MacOS/Vivaldi:Vivaldi"
        "/Applications/Opera.app/Contents/MacOS/Opera:Opera"
        "/Applications/Arc.app/Contents/MacOS/Arc:Arc"
    )
    for entry in "${MAC_PATHS[@]}"; do
        path="${entry%%:*}"; name="${entry#*:}"
        check_path "$path" "$name"
    done
    # Also check ~/Applications
    for entry in "${MAC_PATHS[@]}"; do
        path="${entry%%:*}"; name="${entry#*:}"
        home_path="$HOME${path#/Applications}"
        # Prepend ~/Applications
        home_path="$HOME/Applications${path#/Applications}"
        check_path "$home_path" "$name (User)"
    done
fi

# --- Deduplicate by resolved path ---
declare -A SEEN=()
UNIQUE=()
for item in "${FOUND[@]+"${FOUND[@]}"}"; do
    [[ -z "$item" ]] && continue
    p=$(echo "$item" | grep -o '"path":"[^"]*"' | cut -d'"' -f4)
    rp=$(readlink -f "$p" 2>/dev/null || echo "$p")
    if [[ -z "${SEEN[$rp]:-}" ]]; then
        SEEN["$rp"]=1
        UNIQUE+=("$item")
    fi
done

# --- Output ---
if [[ ${#UNIQUE[@]} -eq 0 ]]; then
    echo '{"browsers":[]}'
    exit 1
fi

echo -n '{"browsers":['
for i in "${!UNIQUE[@]}"; do
    [[ $i -gt 0 ]] && echo -n ","
    echo -n "${UNIQUE[$i]}"
done
echo ']}'
