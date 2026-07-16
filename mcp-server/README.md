# boxkite-mcp

An MCP server over a hosted boxkite control-plane — lets any MCP-compatible
client (Claude Code, Claude Desktop, Cursor, etc.) attach a real sandboxed
code-execution backend as a native tool source, zero custom integration code.

> **Prefer no local install?** A control-plane deployment built from this
> repo also exposes a **remote** Streamable HTTP MCP endpoint directly at
> `https://your-control-plane.example.com/mcp/` — add that URL to your MCP
> client's config instead of installing this package. See
> [`docs/HOSTED-MCP-DESIGN.md`](https://github.com/HarshitKmr10/boxkite/blob/main/docs/HOSTED-MCP-DESIGN.md).
> Use this package when you want the MCP server process running on your own
> machine instead.

## Install

```bash
pip install boxkite-mcp
# or, to run it as a standalone MCP server without a project venv:
pipx install boxkite-mcp
```

## Configuration

Two required environment variables:

| Variable | Meaning |
|---|---|
| `BOXKITE_BASE_URL` | Base URL of the boxkite control-plane |
| `BOXKITE_API_KEY` | A `bxk_live_...` API key for your account |

## Run

```bash
BOXKITE_BASE_URL=https://your-control-plane.example.com \
BOXKITE_API_KEY=bxk_live_... \
boxkite-mcp
```

Speaks MCP over stdio — point an MCP client's config at the `boxkite-mcp` command.

## Tools

Sandbox lifecycle and exec/file tools — `create_sandbox`, `destroy_sandbox`,
`get_sandbox`, `list_sandboxes`, `exec`, `file_create`, `view`, `str_replace`,
`ls`, `glob`, `grep` — every per-sandbox tool takes `session_id` as a
parameter, so the calling agent owns the full lifecycle within one
conversation.

Custom image tools (build a sandbox image with extra packages baked in,
then pass its id as `create_sandbox`'s `image_id`) — `create_sandbox_image`,
`get_sandbox_image`, `list_sandbox_images`, `delete_sandbox_image`.

Independent storage volume tools (create persistent storage mountable into
one or more sandboxes via `create_sandbox`'s `volume_mounts`) —
`create_sandbox_volume`, `get_sandbox_volume`, `list_sandbox_volumes`,
`delete_sandbox_volume`.

Outbound-MCP connection tools (grant a sandbox network egress to a curated
MCP catalog entry via `create_sandbox`'s `mcp_connection_names` — see
[`docs/OUTBOUND-MCP-DESIGN.md`](https://github.com/HarshitKmr10/boxkite/blob/main/docs/OUTBOUND-MCP-DESIGN.md);
there is no MCP-proxy transport yet, so this only widens network reachability,
it doesn't yet let the sandbox speak MCP protocol to the destination) —
`create_mcp_connection`, `list_mcp_connections`, `delete_mcp_connection`.

## Security

`exec` runs arbitrary shell commands with no client-side allowlist — the
isolation boundary is the sandbox itself (see the root repo's `SECURITY.md`),
not these MCP tools' argument validation. `exec`/`view` results are returned
to the calling LLM as plain, unsanitized text — treat sandbox output as
untrusted input, the same as a web-fetch or file-read tool's result.

## Development

```bash
pip install -e ".[dev]"
pytest tests/
```

See the [root README](https://github.com/HarshitKmr10/boxkite#readme) for
what boxkite is and the full self-hosting story.
