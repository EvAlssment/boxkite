"""`boxkite mcp init <target>` — one-shot wire boxkite's MCP server (the
`boxkite-mcp` package, see mcp-server/) into an MCP-compatible client's own
config file, using the hosted base_url/api_key already saved by
`boxkite signup` (or `boxkite config set-url`/`set-key`).

This is the maintainer-suggested smallest slice of issue #219's broader
first-run-wizard request -- just the MCP-wiring step. The full `boxkite init`
wizard (starter image picker + first sandbox + generated snippet) is left
for a follow-on issue.

Each target's config file is a JSON object with a top-level `mcpServers`
dict keyed by server name -- merge-write only ever touches the `boxkite` key
within that dict, so any other servers (or unrelated top-level keys, for
clients that keep other settings in the same file) already present survive
untouched.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import typer

from .config_store import read_hosted_config
from .errors import CliError

MCP_COMMAND = "boxkite-mcp"
SERVER_NAME = "boxkite"

TARGETS = ("claude-code", "cursor", "windsurf", "claude-desktop")


def _claude_desktop_config_path() -> Path:
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "Claude" / "claude_desktop_config.json"
    if sys.platform.startswith("win"):
        appdata = os.environ.get("APPDATA", str(Path.home()))
        return Path(appdata) / "Claude" / "claude_desktop_config.json"
    return Path.home() / ".config" / "Claude" / "claude_desktop_config.json"


def _config_path_for_target(target: str) -> Path:
    if target == "claude-code":
        return Path.cwd() / ".mcp.json"
    if target == "cursor":
        return Path.home() / ".cursor" / "mcp.json"
    if target == "windsurf":
        return Path.home() / ".codeium" / "windsurf" / "mcp_config.json"
    if target == "claude-desktop":
        return _claude_desktop_config_path()
    raise CliError(f"Unknown target {target!r}. Choose one of: {', '.join(TARGETS)}.")


def _merge_write(path: Path, *, base_url: str, api_key: str) -> bool:
    """Merge a `boxkite` entry into `path`'s `mcpServers` block, leaving
    every other key untouched. Returns True if this added a brand-new
    entry, False if it updated one that was already there (idempotent)."""
    if path.exists():
        try:
            data = json.loads(path.read_text())
        except ValueError as exc:
            raise CliError(f"{path} is not valid JSON -- refusing to overwrite it: {exc}") from exc
        if not isinstance(data, dict):
            raise CliError(f"{path} does not contain a JSON object at the top level -- refusing to overwrite it.")
    else:
        data = {}

    servers = data.get("mcpServers")
    if not isinstance(servers, dict):
        servers = {}
    is_new_entry = SERVER_NAME not in servers

    servers[SERVER_NAME] = {
        "command": MCP_COMMAND,
        "env": {
            "BOXKITE_BASE_URL": base_url,
            "BOXKITE_API_KEY": api_key,
        },
    }
    data["mcpServers"] = servers

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n")
    try:
        path.chmod(0o600)  # the entry embeds a live API key
    except OSError:
        pass  # e.g. platforms without POSIX permission bits
    return is_new_entry


def init(
    target: str = typer.Argument(
        ..., help=f"MCP client to configure. One of: {', '.join(TARGETS)}."
    ),
) -> None:
    """Wire boxkite's MCP server into an MCP-compatible client's config file."""
    if target not in TARGETS:
        raise CliError(f"Unknown target {target!r}. Choose one of: {', '.join(TARGETS)}.")

    hosted = read_hosted_config()
    if not hosted.base_url or not hosted.api_key:
        raise CliError(
            "No hosted control-plane configured yet. Run `boxkite signup`, or "
            "`boxkite config set-url` and `boxkite config set-key`, before `boxkite mcp init`."
        )

    path = _config_path_for_target(target)
    added = _merge_write(path, base_url=hosted.base_url, api_key=hosted.api_key)

    verb = "Added" if added else "Updated"
    typer.secho(f"{verb} the boxkite MCP server entry in {path}.", fg=typer.colors.GREEN)
    typer.echo("Restart your MCP client to pick up the change.")
