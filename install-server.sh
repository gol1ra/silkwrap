
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

echo
echo "Silkwrap server installed."
echo "Server directory: $SERVER_DIR"
echo "Config file:      $SERVER_CONFIG"
echo
echo "1. Edit the config and set your server password:"
echo "   nano \"$SERVER_CONFIG\""
echo
echo "2. Start the server manually:"
echo "   cd \"$SERVER_DIR\" && ./silkwrap server"
echo
echo "Or configure systemd separately if you want the server to run in the background."
