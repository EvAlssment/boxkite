# boxkite-client (Rust)

A Rust client for a **hosted** boxkite control-plane — create sandboxes, run
commands, edit files, over HTTP/WebSocket. Not the `boxkite` package itself
(the self-hosted Python core that embeds `SandboxManager` against your own
Kubernetes cluster) — use this to talk to *someone else's* running
control-plane, hosted or self-hosted, over its API. Async-first (`tokio`),
mirroring the same `/v1/*` REST API `sdk-python`/`sdk-js` wrap.

## Install

```toml
[dependencies]
boxkite-client = "0.1"
tokio = { version = "1", features = ["full"] }
```

## Quickstart

```rust
use boxkite_client::{Client, CreateSandboxOptions, ExecOptions};

#[tokio::main]
async fn main() -> Result<(), boxkite_client::BoxkiteError> {
    let client = Client::new("https://your-control-plane.example.com", "bxk_live_...")?;

    let sandbox = client
        .create_sandbox(CreateSandboxOptions::new().label("demo"))
        .await?;

    let result = client
        .exec(&sandbox.id, "python3 -c 'print(1 + 1)'", ExecOptions::new())
        .await?;
    println!("{}", result.stdout); // "2\n"

    client.file_create(&sandbox.id, "notes.txt", "hello from boxkite-client\n", Default::default()).await?;
    println!("{}", client.view(&sandbox.id, "notes.txt", Default::default()).await?.content);

    client.destroy_sandbox(&sandbox.id).await?;
    Ok(())
}
```

`Client::new(base_url, api_key)` covers the common case; use
`Client::builder()` for a custom timeout or a preconfigured `reqwest::Client`
(e.g. pointed at a test server).

Also available: file/directory search (`ls`/`glob`/`grep`), an audit-log feed
(`get_log`/`watch`, the latter a `Stream` over Server-Sent Events), interactive
human takeover (`takeover`, a raw `tokio-tungstenite` WebSocket byte stream),
and desktop (GUI) takeover over the same raw-WebSocket pattern
(`desktop_takeover`) — plus CRUD for custom images, independent storage volumes,
outbound-MCP connections, and webhook subscriptions. Full reference with
examples for all of these:
[`docs/API.md`](https://github.com/EvAlssment/boxkite/blob/main/docs/API.md).

## Error handling

Every fallible call returns `Result<T, BoxkiteError>`. A non-2xx response
becomes `BoxkiteError::Api { status, code, message }`; a transport-level
failure becomes `BoxkiteError::Connection`.

```rust
use boxkite_client::BoxkiteError;

match client.exec(&sandbox.id, "echo hi", Default::default()).await {
    Ok(result) => println!("{}", result.stdout),
    Err(BoxkiteError::Api { code, .. }) if code == "concurrent_sandbox_limit_reached" => {
        // back off, destroy an old session, etc.
    }
    Err(err) => return Err(err),
}
```

## Scope

This crate wraps a subset of the `/v1/*` API that `sdk-python`/`sdk-js` also
wrap: sandbox lifecycle (`create_sandbox`/`get_sandbox`/`list_sandboxes`/
`destroy_sandbox`), exec/file operations, background process management, the
audit log, human takeover, desktop takeover, and CRUD for
images/volumes/outbound-MCP connections/webhooks/secrets.

**Deliberately not included in this pass:**

- **A LangChain-style tool-factory wrapper.** `sdk-python`/`sdk-js` both ship
  one because LangChain/LangChain.js are the dominant integration point in
  their ecosystems. No comparably dominant Rust agent-framework tool-spec
  convention exists yet to mirror, so this crate stops at the plain HTTP/WS
  client — wire it into whatever tool-calling shape your own agent framework
  expects.
- **A synchronous/blocking client variant.** Rust's async ecosystem is
  `tokio`-first by convention; this crate follows that rather than
  maintaining a redundant blocking wrapper. If you need one, wrap calls in
  `tokio::runtime::Runtime::block_on` yourself.
- **A route `sdk-python`/`sdk-js` themselves don't wrap yet**, even though
  it exists on the control-plane: filesystem snapshots (`/snapshots/*`).
  This crate mirrors its two reference SDKs' actual method sets rather
  than inventing new surface area ahead of them.
- **Account/usage introspection, auth-flow helpers, the `http_request`
  secrets-broker proxy, network-ingress preview URLs, and the per-account
  command allowlist.** Unlike the item above, this one is **not** a shared
  gap across all three SDKs — `sdk-python`/`sdk-js` already wrap all of it
  (`account()`/`usage()`; `request_password_reset`/`confirm_password_reset`/
  `verify_email`/`refresh_token`/`logout`; `http_request()`;
  `create_preview_url()`/`revoke_preview_url()`; `get_allowed_commands()`/
  `set_allowed_commands()`/`clear_allowed_commands()`). This crate genuinely
  lags its two reference SDKs here and doesn't implement any of it yet —
  left for a follow-up pass, not a deliberate design choice like the items
  above.
- **`Webhook`'s newer `payload_format`/`hec_token` fields** (added to
  `control_plane.schemas.WebhookCreateRequest` for the Splunk HEC/audit-log
  export addendum, issue #125) — `sdk-python`/`sdk-js` haven't picked these
  up yet, so this crate's `create_webhook` sticks to `url`/`event_types`/
  `description`, the same three fields those two SDKs send.

## Development

```bash
cargo build
cargo test
cargo clippy --all-targets -- -D warnings
cargo fmt
```

Tests mock the control-plane with [`wiremock`](https://docs.rs/wiremock) (a
real local HTTP server, not an in-process shim) — no real deployment needed.
`takeover()`'s test spins up a bare `tokio` TCP listener and does the
WebSocket handshake by hand with `tokio-tungstenite`'s server-side helpers,
since `wiremock` is HTTP-only.

See the [root README](https://github.com/EvAlssment/boxkite#readme) for
what boxkite is and the full self-hosting story.
