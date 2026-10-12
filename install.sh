bash
#!/usr/bin/env bash
set -euo pipefail

REPO="ilosthope3/silkwrap"
INSTALL_DIR="${HOME}/.local/bin"
BINARY="sw"
CLIENT_CONFIG="${HOME}/.silkwrap/client_config.json"

if ! command -v curl >/dev/null 2>&1; then
    echo "Error: curl is required." >&2
    exit 1
fi

ARCH="$(uname -m)"
case "$ARCH" in
    x86_64|amd64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *)
        echo "Unsupported architecture: $ARCH" >&2
        exit 1
        ;;
esac

OS="$(uname -s)"
if [[ "$OS" != "Linux" ]]; then
    echo "Unsupported operating system: $OS" >&2
    exit 1
fi

DOWNLOAD_URL="https://github.com/${REPO}/releases/latest/download/sw-linux-${ARCH}"

mkdir -p "$INSTALL_DIR"
TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

echo "Downloading Silkwrap..."
curl -fsSL "$DOWNLOAD_URL" -o "$TMP_FILE"
chmod 755 "$TMP_FILE"
mv "$TMP_FILE" "${INSTALL_DIR}/${BINARY}"
trap - EXIT

echo "Installed Silkwrap to ${INSTALL_DIR}/${BINARY}"

case ":$PATH:" in
    *":${INSTALL_DIR}:"*) ;;
    *)
        echo 'Add this to your shell profile if needed:'
        echo 'export PATH="$HOME/.local/bin:$PATH"'
        ;;
esac

SERVICE_DIR="${HOME}/.config/systemd/user"
SERVICE_FILE="${SERVICE_DIR}/silkwrap-daemon.service"

mkdir -p "$SERVICE_DIR"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Silkwrap Autodownload Startup

[Service]
Type=oneshot
ExecStart=${INSTALL_DIR}/${BINARY} daemon start
RemainAfterExit=yes

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable silkwrap-daemon.service
systemctl --user start silkwrap-daemon.service

echo
echo "Config path: \"$CLIENT_CONFIG\""
echo "ADD SERVER TO CONFIG"
echo 'Format: "https://127.0.0.1:7842/"'
echo "copy format EXACTLY"
echo "127.0.0.1 is localhost (serverside client) for remote use server ip"
echo "check rsa fingerprint !!!!"

"${INSTALL_DIR}/${BINARY}"
