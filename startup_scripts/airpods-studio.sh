#!/usr/bin/env bash
# airpods-studio.sh – Bluetooth audio sink + Spotify Connect (librespot)
# Runs as root, designed for systemd service. Uses system-mode PulseAudio.

set -Eeuo pipefail

LIBRESPOT_BIN="${LIBRESPOT_BIN:-/home/pod/.cargo/bin/librespot}"
BT_DEVICE_NAME="${BT_DEVICE_NAME:-AirPods-Studio}"
PULSE_RUNTIME_PATH="${PULSE_RUNTIME_PATH:-/run/pulse}"
PULSE_SYSTEM_PA="/etc/pulse/system.pa"

msg() {
    printf '==> %s\n' "$*"
}

err() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

require_root() {
    [[ $EUID -eq 0 ]] || err "Please run as root."
}

install_if_missing() {
    local pkg
    for pkg in bluez pulseaudio pulseaudio-module-bluetooth bluez-tools mpv cargo; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            msg "Installing $pkg..."
            apt-get update -qq
            apt-get install -y -qq "$pkg"
        fi
    done
}

ensure_librespot() {
    if [[ -x "$LIBRESPOT_BIN" ]]; then
        return 0
    fi

    if command -v cargo >/dev/null 2>&1; then
        msg "Installing librespot via cargo..."
        cargo install librespot --locked
    fi

    [[ -x "$LIBRESPOT_BIN" ]] || err "librespot was not found at $LIBRESPOT_BIN. Install it with: cargo install librespot --locked"
}

ensure_pulse_access() {
    if ! id -nG root | tr ' ' '\n' | grep -Fxq 'pulse-access'; then
        msg "Adding root to pulse-access group..."
        usermod -a -G pulse-access root
    fi
}

ensure_pulse_runtime_dir() {
    mkdir -p "$PULSE_RUNTIME_PATH"
    chown root:pulse-access "$PULSE_RUNTIME_PATH" 2>/dev/null || true
    chmod 755 "$PULSE_RUNTIME_PATH"
}

ensure_pa_config() {
    if [[ ! -f "$PULSE_SYSTEM_PA" ]]; then
        cat > "$PULSE_SYSTEM_PA" <<'EOF'
load-module module-null-sink sink_name=auto_null
load-module module-native-protocol-unix
load-module module-stream-restore restore_device=false
EOF
    fi

    local module
    for module in module-bluetooth-discover module-bluetooth-policy module-switch-on-connect; do
        if ! grep -q "load-module $module" "$PULSE_SYSTEM_PA" 2>/dev/null; then
            printf 'load-module %s\n' "$module" >> "$PULSE_SYSTEM_PA"
            msg "Added $module to $PULSE_SYSTEM_PA"
        fi
    done
}

wait_for_bluetooth() {
    local attempt
    for attempt in $(seq 1 30); do
        if bluetoothctl show >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    err "Bluetooth service did not become ready in time."
}

set_bt_adapter_state() {
    if command -v bt-adapter >/dev/null 2>&1; then
        bt-adapter --set Powered 1 || true
        bt-adapter --set Discoverable 1 || true
        bt-adapter --set Pairable 1 || true
    fi

    if command -v bluetoothctl >/dev/null 2>&1; then
        bluetoothctl power on >/dev/null 2>&1 || true
        bluetoothctl discoverable on >/dev/null 2>&1 || true
        bluetoothctl pairable on >/dev/null 2>&1 || true
    fi

    if command -v hciconfig >/dev/null 2>&1 && hciconfig hci0 >/dev/null 2>&1; then
        hciconfig hci0 name "$BT_DEVICE_NAME" 2>/dev/null || true
    fi
}

start_bluetooth_agent() {
    if pgrep -x bt-agent >/dev/null 2>&1; then
        pkill -x bt-agent || true
    fi

    msg "Starting pairing agent (no PIN required)..."
    bt-agent -c NoInputNoOutput >/dev/null 2>&1 &
    AGENT_PID=$!
}

play_optional_sound() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    mpv --audio-device=alsa/hw:0,0 "$file" >/dev/null 2>&1 || true
}

cleanup() {
    if [[ -n "${AGENT_PID:-}" ]]; then
        kill "$AGENT_PID" 2>/dev/null || true
    fi

    if command -v bt-adapter >/dev/null 2>&1; then
        bt-adapter --set Discoverable 0 2>/dev/null || true
        bt-adapter --set Pairable 0 2>/dev/null || true
    fi

    if command -v bluetoothctl >/dev/null 2>&1; then
        bluetoothctl discoverable off >/dev/null 2>&1 || true
        bluetoothctl pairable off >/dev/null 2>&1 || true
    fi

    play_optional_sound "/home/pod/airpodsstudio/audio/shutdown_airpodsstudio.mp3"
    msg "Shutting down..."
    exit 0
}

require_root
install_if_missing
ensure_librespot
ensure_pulse_access
ensure_pulse_runtime_dir
ensure_pa_config

if ! pgrep -x pulseaudio >/dev/null 2>&1; then
    msg "Starting PulseAudio in system mode..."
    pulseaudio --system --daemonize
fi

for _ in $(seq 1 10); do
    [[ -S "$PULSE_RUNTIME_PATH/pulse/native" ]] && break
    sleep 1
done

play_optional_sound "/home/pod/airpodsstudio/audio/startup_airpodsstudio.mp3"

msg "Starting Bluetooth service..."
systemctl enable bluetooth --quiet
systemctl start bluetooth
wait_for_bluetooth
set_bt_adapter_state
start_bluetooth_agent
trap cleanup SIGINT SIGTERM

msg ""
msg "================================================="
msg "  Bluetooth sink is discoverable as '$BT_DEVICE_NAME'"
msg "  Spotify Connect starting: $LIBRESPOT_BIN"
msg "  Press Ctrl+C to stop everything."
msg "================================================="

exec "$LIBRESPOT_BIN" -n "$BT_DEVICE_NAME" -b 320 --disable-audio-cache --initial-volume 100 --enable-volume-normalisation