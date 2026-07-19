#!/usr/bin/env bash
# airpods-studio.sh – Bluetooth audio sink + Spotify Connect (librespot)
# Runs as root, designed for systemd service. Uses system-mode PulseAudio.

set -euo pipefail

# ----- config -----
LIBRESPOT_CMD="/home/pod/.cargo/bin/librespot -n 'AirPods-Studio' -b 320 --disable-audio-cache --initial-volume 100 --enable-volume-normalisation"
BT_DEVICE_NAME="AirPods-Studio"

# ----- helpers -----
msg() { echo "==> $*"; }
err() { echo "ERROR: $*" >&2; exit 1; }

# Must be root
if [[ $EUID -ne 0 ]]; then
    err "Please run as root."
fi

install_if_missing() {
    for pkg in bluez pulseaudio pulseaudio-module-bluetooth bluez-tools mpv; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            msg "Installing $pkg..."
            apt-get update -qq
            apt-get install -y -qq "$pkg"
        fi
    done
}
install_if_missing

if ! groups root | grep -q pulse-access; then
    adduser root pulse-access
    msg "Added root to pulse-access group."
fi

PA_CONFIG="/etc/pulse/system.pa"
if [ ! -f "$PA_CONFIG" ]; then
    # Create a minimal system.pa if missing
    cat > "$PA_CONFIG" <<EOF
load-module module-null-sink sink_name=auto_null
load-module module-native-protocol-unix
load-module module-stream-restore restore_device=false
EOF
fi

msg "Enabling Bluetooth modules in $PA_CONFIG..."
for module in module-bluetooth-discover module-bluetooth-policy module-switch-on-connect; do
    if ! grep -q "load-module $module" "$PA_CONFIG" 2>/dev/null; then
        echo "load-module $module" >> "$PA_CONFIG"
        msg "Added $module"
    fi
done

if ! pgrep -x pulseaudio &>/dev/null; then
    msg "Starting PulseAudio in system mode..."
    pulseaudio --system --daemonize
    sleep 2
fi

# Optional startup sound – only plays if file exists, won't crash on failure
if [ -f /home/pod/airpodsstudio/audio/startup_airpodsstudio.mp3 ]; then
    mpv --audio-device=alsa/hw:0,0 /home/pod/airpodsstudio/audio/startup_airpodsstudio.mp3 || true
fi

msg "Starting Bluetooth service..."
systemctl enable bluetooth --quiet
systemctl start bluetooth

bt-adapter --set Powered 1
bt-adapter --set Discoverable 1
bt-adapter --set Pairable 1
hciconfig hci0 name "$BT_DEVICE_NAME" 2>/dev/null || true

msg "Starting pairing agent (no PIN required)..."
bt-agent -c NoInputNoOutput &
AGENT_PID=$!

cleanup() {
    # Optional shutdown sound
    if [ -f /home/pod/airpodsstudio/audio/shutdown_airpodsstudio.mp3 ]; then
        mpv --audio-device=alsa/hw:0,0 /home/pod/airpodsstudio/audio/shutdown_airpodsstudio.mp3 || true
    fi
    msg "Shutting down..."
    kill "$AGENT_PID" 2>/dev/null || true
    bt-adapter --set Discoverable 0 2>/dev/null || true
    bt-adapter --set Pairable 0 2>/dev/null || true
    exit 0
}
trap cleanup SIGINT SIGTERM

msg ""
msg "================================================="
msg "  Bluetooth sink is DISCOVERABLE as '$BT_DEVICE_NAME'"
msg "  Spotify Connect starting: $LIBRESPOT_CMD"
msg "  Press Ctrl+C to stop everything."
msg "================================================="

eval exec "$LIBRESPOT_CMD"