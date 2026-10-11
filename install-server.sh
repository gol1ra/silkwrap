
#!/usr/bin/env bash
set -Eeuo pipefail

REPO="ilosthope3/silkwrap"
RELEASE_URL="https://github.com/${REPO}/releases/latest/download"

SERVER_DIR="$HOME/silkwrap-server"
SERVER_BIN="$SERVER_DIR/silkwrap"
SERVER_CONFIG="$SERVER_DIR/config.json"

command -v curl >/dev/null || {
    echo "Error: curl is required." >&2
    exit 1
}

case "$(uname -m)" in
    x86_64|amd64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *)
        echo "Unsupported architecture: $(uname -m)" >&2
        exit 1
        ;;
esac

mkdir -p "$SERVER_DIR"

echo "Installing Silkwrap server..."
curl -fsSL "$RELEASE_URL/silkwrap-linux-$ARCH" -o "$SERVER_BIN"
chmod +x "$SERVER_BIN"

echo "Initializing server files..."
if [[ ! -f "$SERVER_CONFIG" ]]; then
    (
        cd "$SERVER_DIR"
        timeout 3 "$SERVER_BIN" server || true
    )
fi

if [[ ! -f "$SERVER_CONFIG" ]]; then
    echo "Error: server config was not created." >&2
    exit 1
fi
SERVICE_FILE="/etc/systemd/system/silkwrap-server.service"

sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Silkwrap Server
After=network.target

[Service]
Type=simple
WorkingDirectory=$SERVER_DIR
ExecStart=$SERVER_BIN server
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload

echo "Silkwrap server installed."
echo "Server directory: $SERVER_DIR"
echo "Config file:      $SERVER_CONFIG"
echo "ADD PASSWORD TO SERVER CONFIG"
echo
echo "Start the server manually:"
echo "   cd \"$SERVER_DIR\" && ./silkwrap server"
echo "OR"
echo "   sudo systemctl enable --now silkwrap-server"
echo "   to start it as a persistent daemon"
