# Silkwrap

**A self-hosted, queue-based file transfer and messaging system for the command line.**

Silkwrap transfers files, nested directories, text, and links between users and devices through a server you control. It is designed for moving data between a desktop, laptop, VPS, virtual machine, or any other machine that can reach the server.

Unlike tools that depend on a live SSH session or a direct connection between the sender and receiver, Silkwrap uses **asynchronous, queue-based delivery**. The sender uploads content and registers deliveries; recipients retrieve it when convenient. The sender and receiver do not need to be online simultaneously.

The central design goal is simplicity: a lightweight server, a CLI client, persistent authentication, and an optional background daemon. Once configured, devices can exchange content without repeatedly establishing interactive sessions or relying on a third-party cloud-storage service.

## Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Design Philosophy](#deign-philosophy)
- [Architecture](#architecture)
- [Network Interaction](#network-interaction)
- [Storage and Database Model](#storage-and-database-model)
- [Directory Transfer and Transactional Consistency](#directory-transfer-and-transactional-consistency)
- [Payload Lifecycle and Cleanup](#payload-lifecycle-and-cleanup)
- [Security and Trust Model](#security-and-trust-model)
- [Configuration](#configuration)
- [Building from Source](#building-from-source)
- [Future Development](#future-development)

## Installation

Silkwrap provides separate installers for the client and server. These installers download prebuilt Linux release binaries for AMD64 or ARM64; they do not compile the application from source.

### Client

Run on each machine that will use the CLI:

```bash
curl -fsSL https://raw.githubusercontent.com/ilosthope3/silkwrap/main/install.sh | bash
```

The client binary is installed to:

```text
~/.local/bin/sw
```

The installer prints a `PATH` adjustment if `~/.local/bin` is not already on your path.

### Server

Run on the machine that will host the server:

```bash
curl -fsSL https://raw.githubusercontent.com/ilosthope3/silkwrap/main/install-server.sh | bash
```

The installer downloads the server release binary to:

```text
~/silkwrap-server/silkwrap
```

It initializes the server configuration and installs a systemd service definition. The generated configuration must be edited before normal operation.

Review the installer scripts before executing them, especially on a production machine.

## Quick Start

### 1. Configure the server

Edit the generated configuration:

```bash
nano "$HOME/silkwrap-server/config.json"
```

Set the required `Password`. 
Review `AllowCrossUserDelete` as well; it controls whether authenticated users can delete other accounts.

The server's first initialization generates a self-signed TLS certificate if one does not already exist and prints its SHA-256 fingerprint. The certificate and private key are stored in the server working directory.

### 2. Start the server

Run it manually:

```bash
cd "$HOME/silkwrap-server" && ./silkwrap server
```

Alternatively, run it as a persistent service:

```bash
sudo systemctl enable --now silkwrap-server
```

### 3. Configure the client

Edit the client configuration:

```bash
nano "$HOME/.silkwrap/client_config.json"
```

Set `server` to the HTTPS URL of the server, including the correct port. For example:

```json
{
    "server": "https://127.0.0.1:7842/",
    "timeout_seconds": 5,
    "save_dir": "~/Downloads/silkwrap",
    "autodownload": false,
    "daemon_retry_secs": 15
}
```

`127.0.0.1` refers to the local machine. When connecting to a remotely hosted server, use its reachable IP address or domain instead.

Verify the server's TLS fingerprint during setup and check the CLI's reported configuration if anything is not initialized correctly.

### 4. Authenticate

```bash
sw auth <username> <password>
```

Authentication logs in to an existing username or creates the account if that username does not exist. The password must match the shared password configured on the server.

Use `sw help` for the CLI's command reference.

## Design Philosophy

Silkwrap is built around a simple idea: **moving files between your machines should be as straightforward as sending a message, without requiring both ends to be present at the same time.**

A file transfer should not depend on keeping an SSH session alive, coordinating when two devices are online, or entrusting your files to another cloud-storage provider. Upload the content, queue the delivery, and let the recipient retrieve it when convenient. The sender can move on; the receiver can catch up later.

This makes Silkwrap less like a remote shell and more like a lightweight, self-hosted delivery system. The server coordinates who receives what, retains the necessary payloads and metadata, and provides a common point of contact for devices that may never communicate directly with one another. The optional background daemon takes this one step further, turning queued deliveries into automatic downloads without changing the underlying transfer model.

### One server, many machines

A desktop, a laptop, a VPS, a virtual machine, or another computer can all participate in the same workflow. They do not need to share a local network, maintain direct connections to each other, or be online simultaneously. They only need to reach the server when sending or retrieving content.

This is useful for the ordinary friction of working across machines: moving a project from a laptop to a server, retrieving an artifact on a desktop, sending a directory to another device, or passing a link or short piece of text between environments. Silkwrap provides one consistent mechanism for these tasks instead of requiring a different tool or workflow for each situation.

### Simplicity is a design constraint

Silkwrap is deliberately small in scope. Its setup consists of a server, a client configuration, and authentication; after that, the same command-line interface is available wherever the client is installed. The daemon is optional rather than a prerequisite for receiving files.

The authentication model reflects the same priority. A shared password makes it easy to establish identities across trusted devices without introducing a separate account-management workflow for each one. This favors convenience in a controlled environment over strict isolation between independent users. It is an explicit trade-off, not an attempt to provide the access-control model of a public multi-tenant service.

The same philosophy applies to the rest of the system: use a small API, persistent metadata, filesystem-backed payloads, and a queue that can be consumed manually or automatically. Avoid adding infrastructure unless it serves the core transfer workflow.

### Direct transfers, without direct-session requirements

Silkwrap does not attempt to make two devices behave as though they are connected by a permanent interactive session. Instead, it separates sending from retrieval.

A sender uploads content and registers deliveries for the intended recipients. The server records the deliveries and retains the payload while it is needed. Recipients retrieve their items independently, and an optional WebSocket notification channel lets the daemon react to pending deliveries. Actual content retrieval continues over HTTPS.

This separation is particularly useful when the receiving device is asleep, disconnected, or simply not being used at the moment the sender uploads something. Silkwrap does not eliminate the need for network access to the server, nor is its queue intended as permanent cloud storage; it removes the requirement for a live sender-to-recipient session and simultaneous availability.

### Files are more than individual blobs

A directory is not merely a collection of unrelated files. Its hierarchy is part of the content being transferred.

Silkwrap represents directory structure through a manifest that references uploaded child payloads. This lets the server retain a flat, UUID-based storage layout while preserving the logical hierarchy needed by the receiving client. The manifest and its related child-accounting changes are registered transactionally, keeping those database relationships consistent.

The underlying storage model also separates a payload from its deliveries. Multiple recipients can reference the same stored bytes while maintaining their own delivery state. That distinction allows the system to support multi-recipient transfers without treating each recipient's copy as an entirely separate physical object.

### A tool, not a cloud platform

Silkwrap is not intended to replace a full cloud drive, synchronization suite, or collaboration platform. It focuses on a narrower problem: moving content between trusted machines with minimal ceremony.

It does not currently provide continuously synchronized shared folders or a web-based graphical client. Those are possible extensions, but they introduce their own requirements, such as change detection, conflict resolution, and a broader user interface. They are not prerequisites for the central workflow.

The goal is to make self-hosted file delivery practical: configure it once, use it from the machines you choose, and let the queue bridge the gaps between when content is sent and when it is received.

## Architecture

Silkwrap separates the client interface, delivery metadata, and stored payloads.

```text
                         Sender Client
                               |
                               | HTTPS upload
                               v
                   +-------------------------+
                   |     Silkwrap Server     |
                   |                         |
                   | Authentication          |
                   | Upload / download API   |
                   | Recipient delivery rows |
                   | SQLite metadata          |
                   | Filesystem payloads      |
                   +-------------------------+
                               |
                   +-----------+-----------+
                   |                       |
             Recipient A              Recipient B
                   |                       |
                HTTPS GET              HTTPS GET
                   |                       |
                   v                       v
               Local files             Local files

                   Optional notification path:
                   WebSocket -> Autodownload daemon
                              -> HTTPS retrieval
```

The main components are:

- **Client:** authenticates, uploads content, lists incoming deliveries, retrieves items, and optionally runs the background daemon.
- **Server:** exposes the API over HTTPS, authenticates requests, resolves recipients, manages delivery metadata, stores payloads, and serves notification connections.
- **SQLite:** stores users and recipient-specific delivery state.
- **Filesystem:** stores uploaded payload bytes under UUID-based names.

The server does not need to keep an interactive sender-receiver session alive. It coordinates delivery and retains queued content according to the application's consumption and cleanup rules.

## Network Interaction

The client-server protocol separates transfer operations from notifications. API requests use HTTPS, while the optional daemon uses a WebSocket connection over TLS.

### HTTP API

| Endpoint | Role |
|---|---|
| `/auth` | Authenticate an existing user or create a user using the configured shared password |
| `/whoami` | Identify the authenticated account |
| `/devices` | Retrieve the available user/device identities |
| `/upload` | Receive a file or link and create recipient-specific delivery records |
| `/files` | List pending deliveries for the authenticated recipient |
| `/download` | Retrieve a pending item identified by UUID |
| `/delete` | Mark the authenticated recipient's deliveries as consumed |
| `/delete-user` | Delete a user subject to the server's cross-user deletion setting |
| `/health` | Check server/database health |
| `/ws` | Establish an authenticated WebSocket notification connection |

Authenticated API requests use a bearer token. The server resolves that token to a user identity and applies recipient checks when listing, downloading, or consuming delivery records.

### Upload and delivery registration

For a file upload, the client sends multipart data to `/upload`, including the payload and recipient information. An `InputType` header distinguishes ordinary files, directory children, directory manifests, and links.

The server generates a payload UUID and stores file bytes once. It then creates a separate delivery row for each valid recipient. Recipient results are tracked individually, so one recipient's failed registration does not inherently invalidate successful registrations for other recipients.

Links use delivery metadata without needing a filesystem payload.

### Retrieval

A recipient lists pending items through `/files`. The server returns the records belonging to that recipient and excludes directory-child records from the ordinary inbox.

When retrieving an item, the client requests `/download` using its UUID. The server validates that the item belongs to the authenticated recipient and is still available. File downloads stream the stored payload; link downloads return the URL as structured data.

Consumption is recorded in the database rather than requiring immediate deletion of the payload bytes. This distinction matters when several recipient records refer to the same stored object.

### WebSocket notifications

The autodownload daemon connects to `/ws` using the same token-based authentication model. The server periodically checks the database for eligible pending deliveries and sends notification metadata, including UUID and type. The client then uses the normal HTTPS download path to retrieve the item.

The WebSocket is therefore a notification channel, not a separate file-transfer protocol. Notifications are backed by periodic database polling, so the connection does not require a separate event broker.

The server sends periodic WebSocket pings to help detect stale connections. Client-side retry behavior allows the daemon to reconnect when the notification connection drops.

## Storage and Database Model

A central design decision is the separation of **payload identity** from **delivery identity**.

The `items` table can contain multiple rows with the same UUID. These rows represent deliveries to different recipients, while the UUID identifies the shared payload. This avoids storing a separate physical copy for every recipient and lets each recipient maintain independent consumption state.

### Users

The `users` table stores the account identity and authentication token:

```sql
CREATE TABLE users (
    id       INTEGER PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    token    TEXT UNIQUE NOT NULL
);
```

The username provides the human-readable identity used during authentication. The numeric user ID is used by the database to associate senders and recipients with delivery records. The token authenticates subsequent requests.

### Items

The core delivery schema is:

```sql
CREATE TABLE items (
    id          INTEGER PRIMARY KEY,
    uuid        TEXT NOT NULL,
    sender_id   INTEGER NOT NULL REFERENCES users(id),
    receiver_id INTEGER NOT NULL REFERENCES users(id),
    type        TEXT NOT NULL
                CHECK (type IN (
                    'file',
                    'link',
                    'dir-struct',
                    'dir-child'
                )),
    filename    TEXT,
    size        INTEGER,
    url         TEXT,
    uploaded_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    consumed    BOOLEAN DEFAULT FALSE,
    consumed_at DATETIME,
    is_child    BOOLEAN DEFAULT FALSE
);
```

The UUID is deliberately not unique in this table: multiple rows can refer to the same physical payload. The primary key `id` identifies an individual delivery record.

| Field | Purpose |
|---|---|
| `id` | Unique delivery-row identifier |
| `uuid` | Shared identifier for a payload or linked delivery |
| `sender_id` | User who submitted the content |
| `receiver_id` | User whose inbox receives the delivery |
| `type` | Distinguishes files, links, directory manifests, and directory children |
| `filename` | Original file or manifest filename where applicable |
| `size` | Recorded payload size |
| `url` | URL for link deliveries |
| `uploaded_at` | Timestamp used by the storage lifecycle |
| `consumed` | Whether this recipient's delivery has been consumed |
| `consumed_at` | Timestamp of consumption |
| `is_child` | Whether a directory-child record has been accounted for by a directory manifest |

The server opens SQLite with a busy timeout, giving SQLite time to wait for a database lock rather than immediately failing on every brief contention event.

### Filesystem layout

The payload directory stores files under UUID-based names rather than the original filenames:

```text
silkwrap-server/
├── silkwrap
├── config.json
├── items.db
├── tls.crt
├── tls.key
└── data/
    ├── <payload-uuid>
    ├── <payload-uuid>
    └── ...
```

This separates the physical object from delivery-specific metadata. The original filename remains in the database and can be used when presenting or downloading the item.

For a multi-recipient upload, several rows can reference the same UUID. Cleanup must consequently consider the set of relevant rows for a UUID, rather than treating any single consumed delivery as sufficient reason to remove the shared payload.

## Directory Transfer and Transactional Consistency

Directory transfer is one of the more involved parts of Silkwrap because it combines multiple uploaded payloads with a logical hierarchy.

A directory is represented by a manifest:

```json
{
  "name": "project",
  "files": [
    "uuid-for-main-go",
    "uuid-for-go-mod"
  ],
  "dirs": [
    {
      "name": "internal",
      "files": [
        "uuid-for-helper-go"
      ],
      "dirs": []
    }
  ]
}
```

The `name` field identifies the directory, `files` contains child payload UUIDs, and `dirs` recursively describes nested directories. The manifest references payloads rather than embedding file contents.

### Why the manifest is registered transactionally

Directory children are uploaded before the manifest. The server must then register the manifest and associate the referenced child delivery rows with that directory.

For each recipient, the server performs the manifest-row insertion and the corresponding child-accounting updates in one SQLite transaction. If the insert or an accounting update fails, the transaction is rolled back rather than leaving a partially committed directory relationship.

This protects a specific invariant:

**A directory manifest and its corresponding child-accounting changes are committed together for a recipient.**

Atomicity is necessary because these database changes describe a single logical operation. Without the transaction, the database could record the manifest while only some children were marked as directory children, or alter child accounting without successfully registering the manifest.

The transaction covers these related database changes; it is not a single distributed transaction spanning SQLite and every preceding filesystem upload. The file payloads exist independently on disk, and abandoned payloads are handled by the cleanup lifecycle.

### How the child relationship works

1. The client uploads the child files and receives their UUIDs.
2. The client constructs the directory manifest from those references.
3. The server stores and decodes the manifest.
4. In a transaction for each valid recipient, the server inserts the manifest row and marks matching child rows for that recipient as accounted directory children.
5. The transaction commits both changes together.
6. The ordinary inbox hides `dir-child` records, so the receiver sees the logical directory item rather than every child as a separate inbox entry.

This keeps the physical storage flat while preserving the logical directory hierarchy through database metadata and the manifest.

## Payload Lifecycle and Cleanup

Silkwrap separates consuming a delivery from deleting the stored bytes.

A delivery becomes consumed in the database, with `consumed_at` recording when the transition occurred. The physical payload can remain available during a grace period, especially when multiple delivery rows refer to the same UUID or the data is part of a directory transfer.

The cleanup process evaluates which UUIDs must be retained. It accounts for unconsumed deliveries, recent consumption, and directory-child accounting. A payload remains on disk while relevant delivery records require it.

Files on disk that are no longer referenced by the retention query are only removed after an additional filesystem-age guard. In the current implementation, that guard is ten minutes, independently of `DeleteGracePeriodMins`.

Cleanup also removes delivery rows whose receiver account no longer exists. The cleanup process runs once at startup and then periodically according to `CleanIntervalMins`.

The key distinction is that delivery state, database retention, and physical file deletion are separate stages. This lets the server handle shared payloads and incomplete uploads without assuming that consuming one delivery means the underlying file can immediately be deleted.

## Security and Trust Model

Silkwrap is designed for a trusted environment where ease of moving content between devices matters more than strong isolation between independent users.

### Shared-password authentication

The same configured password is used for account authentication. A username identifies the account and deliveries are routed by account identity, but the password is not intended to establish separate security boundaries between users: anyone with the shared password can authenticate using another username.

This is a deliberate setup trade-off. It avoids requiring a separate password-management workflow for every trusted device or user. Cross-user account deletion is controlled separately through `AllowCrossUserDelete`.

The server also applies an in-memory rate limit to authentication attempts. In the current implementation, the limit is five attempts per IP address per minute; it is process-local rather than a persistent or distributed rate limiter.

### TLS and certificate fingerprint verification

The server uses HTTPS for API operations and TLS for WebSocket connections. If a TLS certificate is not already present, the server generates a self-signed RSA certificate and prints its SHA-256 fingerprint.

The client verifies the expected fingerprint through its certificate-pinning flow and stores the pinned value locally. This is designed for self-hosted deployment without requiring a publicly trusted certificate authority.

Pinning does not eliminate the need to establish initial trust correctly. The server's private key, client tokens, and shared password should still be protected.

### Account deletion

`AllowCrossUserDelete` controls whether an authenticated account can delete another account. A an account can delete itself.
Security and trust model allows this to be default true.

### Scope

Silkwrap does not aim to be a public multi-tenant storage service. Deployments exposed to untrusted users should revisit the shared-password model, deletion permissions, network exposure, upload limits, and operational security.

## Configuration

### Server configuration

The server reads `config.json` from its working directory. The installer initializes this file under `~/silkwrap-server/config.json`. Relative paths such as `data` and `items.db` resolve relative to the working directory.

| Setting | Default in current server code | Purpose |
|---|---:|---|
| `Password` | Empty | Shared authentication password. The server refuses to start when it is empty. |
| `ServerPort` | `:7842` | Address and port used by the HTTPS server. |
| `DBPath` | `items.db` | SQLite database path. |
| `SaveDir` | `data` | Directory used for stored payloads. |
| `MaxFormSize` | `500 << 20` | Memory threshold passed to Go's multipart parser; it is not a strict request-body size limit. |
| `AllowCrossUserDelete` | `true` in the current code | Allows authenticated users to delete other users' accounts when enabled. Set to `false` for the intended safer default. |
| `CleanIntervalMins` | `60` | Interval between scheduled cleanup runs. Cleanup also runs at startup. |
| `DeleteGracePeriodMins` | `60` | Grace period used by cleanup's delivery-retention logic. The separate filesystem-age guard remains ten minutes. |
| `QueryIntervalSecs` | `5` | Period between database checks for pending WebSocket notifications. |
| `KeepAliveSecs` | `30` | WebSocket ping interval and part of connection-liveness handling. |

TLS files use fixed names, `tls.crt` and `tls.key`, in the server's working directory.

`MaxFormSize` is passed to `ParseMultipartForm` and controls the parser's memory threshold before spilling multipart content to temporary storage. It should not be treated as a complete maximum-upload-size policy.

### Client configuration

The client configuration is stored in `~/.silkwrap/client_config.json`.

| Setting | Default | Purpose |
|---|---|---|
| `server` | Empty | Base HTTPS URL of the Silkwrap server. Must be configured before use. |
| `timeout_seconds` | `5` | HTTP client timeout in seconds. |
| `save_dir` | `~/Downloads/silkwrap` | Destination directory for downloaded content. |
| `autodownload` | `false` | Controls whether automatic downloads are enabled. |
| `daemon_retry_secs` | `15` | Retry delay used by the daemon connection logic. |

The client also stores its authentication token and locally maintained certificate-fingerprint state under `~/.silkwrap`. Keep this directory private to the user account.

## Building from Source

Prebuilt release binaries are the recommended route for ordinary installation. To build the client and server from source, use a Go version compatible with the module's `go.mod`.

```bash
git clone https://github.com/ilosthope3/silkwrap.git
cd silkwrap

go build -o sw ./client
go build -o silkwrap ./server
```
Server should be started from its own directory
Client should be added to path to be used everywhere 

Automated regression testing is planned as part of future development; building successfully should not be confused with comprehensive automated coverage of transfer and failure scenarios.

## Future Development

- **Documentation:** provide detailed setup, configuration, architecture, and troubleshooting guides.
- **Web-hosted GUI:** explore a graphical client for devices where installing a CLI is inconvenient. It would act as a universal manually operated client without requiring the autodownload daemon.
- **Shared folders:** support a folder shared between two devices, with explicit synchronization and conflict-handling semantics.
- **Automated regression tests:** introduce focused tests during a future v2 so new development preserves v1 behavior. Priority cases include multi-recipient delivery, atomic directory registration, interrupted operations, and cleanup invariants.

