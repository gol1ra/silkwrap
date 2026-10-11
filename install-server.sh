
#!/usr/bin/env bash
set -Eeuo pipefail

REPO="ilosthope3/silkwrap"
RELEASE_URL="https://github.com/${REPO}/releases/latest/download"
PORT=7842

BIN_DIR="$HOME/.local/bin"
SERVER_DIR="$HOME/silkwrap-server"
SERVER_BIN="$SERVER_DIR/silkwrap"
SERVER_CONFIG="$SERVER_DIR/config.json"
CLIENT_CONFIG="$HOME/.silkwrap/client_config.json"

SERVER_SERVICE="silkwrap-server"
DAEMON_SERVICE="silkwrap-daemon"

TMP_LOG="$(mktemp)"
SERVER_PID=""

cleanup() {
    if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    rm -f "$TMP_LOG"
}
trap cleanup EXIT

die() {
    echo "Error: $*" >&2
    exit 1
}

command -v curl >/dev/null || die "curl is required"
command -v sudo >/dev/null || die "sudo is required"

# Install the small utilities used for secure password generation and JSON editing.
if ! command -v jq >/dev/null 2>&1 ||
   ! command -v openssl >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y jq openssl
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y jq openssl
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -Sy --needed jq openssl
    else
        die "Install jq and openssl with your system package manager, then rerun."
    fi
fi

command -v jq >/dev/null || die "jq installation failed"
command -v openssl >/dev/null || die "openssl installation failed"

case "$(uname -m)" in
    x86_64|amd64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) die "Unsupported architecture: $(uname -m)" ;;
esac

mkdir -p "$BIN_DIR" "$SERVER_DIR"
export PATH="$BIN_DIR:$PATH"

echo "[1/10] Installing server binary..."
curl -fsSL "$RELEASE_URL/silkwrap-linux-$ARCH" -o "$SERVER_BIN"
chmod +x "$SERVER_BIN"

echo "[2/10] Installing client binary..."
curl -fsSL "$RELEASE_URL/sw-linux-$ARCH" -o "$BIN_DIR/sw"
chmod +x "$BIN_DIR/sw"

echo "[3/10] Initializing client..."
sw

echo "[4/10] Initializing server files..."
# Let the binary create its config and other files.
# It may exit because the password has not been configured yet.
if [[ ! -f "$SERVER_CONFIG" ]]; then
    (
        cd "$SERVER_DIR"
        timeout 3 "$SERVER_BIN" server >"$TMP_LOG" 2>&1 || true
    )
fi

[[ -f "$SERVER_CONFIG" ]] ||
    die "Server config was not created. Check the server output."

echo "[5/10] Generating temporary password..."
PASSWORD="$(openssl rand -hex 32)"

# Preserve the existing key's capitalization, if present.
jq --arg password "$PASSWORD" '
    (keys | map(select(ascii_downcase == "password")) | .[0]) as $key
    | if $key == null
      then . + {"Password": $password}
      else .[$key] = $password
      end
' "$SERVER_CONFIG" > "$SERVER_CONFIG.tmp"
mv "$SERVER_CONFIG.tmp" "$SERVER_CONFIG"

echo "[6/10] Starting server temporarily and authenticating..."
(
    cd "$SERVER_DIR"
    "$SERVER_BIN" server >"$TMP_LOG" 2>&1 &
    echo $! > "$SERVER_DIR/.install-server.pid"
)
SERVER_PID="$(cat "$SERVER_DIR/.install-server.pid")"
rm -f "$SERVER_DIR/.install-server.pid"

ready=0
for _ in $(seq 1 30); do
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        cat "$TMP_LOG" >&2
        die "Temporary server exited unexpectedly."
    fi

    if (echo >"/dev/tcp/127.0.0.1/$PORT") >/dev/null 2>&1; then
        ready=1
        break
    fi

    sleep 1
done

if [[ "$ready" != 1 ]]; then
    cat "$TMP_LOG" >&2
    die "Temporary server did not become ready on port $PORT."
fi

sw auth server "$PASSWORD"

echo "[7/10] Stopping temporary server..."
kill "$SERVER_PID" 2>/dev/null || true
wait "$SERVER_PID" 2>/dev/null || true
SERVER_PID=""

echo "[8/10] Clearing temporary password..."
jq '
    (keys | map(select(ascii_downcase == "password")) | .[0]) as $key
    | if $key == null
      then . + {"Password": ""}
      else .[$key] = ""
      end
' "$SERVER_CONFIG" > "$SERVER_CONFIG.tmp"
mv "$SERVER_CONFIG.tmp" "$SERVER_CONFIG"

echo "[9/10] Configuring client..."
[[ -f "$CLIENT_CONFIG" ]] || die "Client config not found: $CLIENT_CONFIG"

jq '
    (keys | map(select(ascii_downcase == "server")) | .[0]) as $server_key
    | (keys | map(select(ascii_downcase == "autodownload")) | .[0]) as $download_key
    | .[$server_key // "Server"] = "http://127.0.0.1:7842"
    | .[$download_key // "AutoDownload"] = true
' "$CLIENT_CONFIG" > "$CLIENT_CONFIG.tmp"
mv "$CLIENT_CONFIG.tmp" "$CLIENT_CONFIG"

echo "[10/10] Installing and enabling systemd services..."
[[ -d /run/systemd/system ]] ||
    die "systemd is not running. Install the service files manually."

SERVICE_USER="$(id -un)"

sudo tee "/etc/systemd/system/${SERVER_SERVICE}.service" >/dev/null <<EOF
[Unit]
Description=Silkwrap Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$SERVER_DIR
ExecStart=$SERVER_BIN server
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

sudo tee "/etc/systemd/system/${DAEMON_SERVICE}.service" >/dev/null <<EOF
[Unit]
Description=Silkwrap Autodownload Daemon
After=network-online.target ${SERVER_SERVICE}.service
Wants=network-online.target

[Service]
Type=oneshot
User=$SERVICE_USER
Environment=PATH=$BIN_DIR:/usr/local/bin:/usr/bin:/bin
ExecStart=$BIN_DIR/sw daemon start
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable "$SERVER_SERVICE.service" "$DAEMON_SERVICE.service"

echo
echo "Installation complete."
echo
echo "Server directory: $SERVER_DIR"
echo "Server config:    $SERVER_CONFIG"
echo "Client config:    $CLIENT_CONFIG"
echo
echo "The temporary password has been cleared."
echo "Edit the server config and set your desired password:"
echo "  nano \"$SERVER_CONFIG\""
echo
echo "Then start the services:"
echo "  sudo systemctl start ${SERVER_SERVICE}.service"
echo "  sudo systemctl start ${DAEMON_SERVICE}.service"
echo
echo "Logs:"
echo "  sudo journalctl -u ${SERVER_SERVICE}.service -f"
echo "  sudo journalctl -u ${DAEMON_SERVICE}.service"
echo
echo "Both services are enabled for boot, but neither was started by this installer."
