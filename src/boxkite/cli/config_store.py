"""Persistence for both CLI modes.

- Hosted mode: ~/.boxkite/config.toml (base_url + api_key), written by
  `boxkite config set-url`/`set-key` or `boxkite signup`.
- Local mode: ~/.boxkite/local.env (SIDECAR_AUTH_TOKEN + SIDECAR_URL),
  written by `boxkite up` after it starts the docker-compose stack.

Both live under one root directory so there's a single place to look (and
delete) for a user resetting their local CLI state. Files are written
0600 (best-effort — silently skipped on platforms without POSIX chmod)
since both hold live credentials.
"""

from __future__ import annotations

import tomllib
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlparse

from .errors import CliError

CONFIG_DIR = Path.home() / ".boxkite"
CONFIG_FILE = CONFIG_DIR / "config.toml"
LOCAL_ENV_FILE = CONFIG_DIR / "local.env"

_LOCALHOST_HOSTNAMES = {"localhost", "127.0.0.1", "::1"}


def validate_base_url_scheme(base_url: str) -> None:
    """Reject a non-https base_url unless it points at localhost.

    Every hosted-mode request sends `Authorization: Bearer <api_key>` — a
    full-privilege, long-lived account credential (src/boxkite/cli/client.py's
    hosted_request) — so an http:// URL to anything other than localhost
    would put that credential on the wire in cleartext. Central to
    write_hosted_config() (below) rather than duplicated in set_url/signup,
    so every current and future caller that persists a base_url gets this
    check for free.
    """
    parsed = urlparse(base_url)
    if parsed.scheme == "https":
        return
    if parsed.scheme == "http" and parsed.hostname in _LOCALHOST_HOSTNAMES:
        return
    raise CliError(
        f"Refusing to use non-https base_url {base_url!r}: this would send your API "
        "key in cleartext. Use an https:// URL, or http://localhost (local dev only)."
    )


def _chmod_private(path: Path) -> None:
    try:
        path.chmod(0o600)
    except OSError:
        pass  # e.g. platforms without POSIX permission bits


def _toml_escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


@dataclass
class HostedConfig:
    base_url: str | None = None
    api_key: str | None = None


def read_hosted_config() -> HostedConfig:
    if not CONFIG_FILE.exists():
        return HostedConfig()
    with CONFIG_FILE.open("rb") as f:
        data = tomllib.load(f)
    return HostedConfig(base_url=data.get("base_url"), api_key=data.get("api_key"))


def write_hosted_config(*, base_url: str | None = None, api_key: str | None = None) -> HostedConfig:
    """Merge the given fields into the existing hosted config and persist it."""
    if base_url is not None:
        validate_base_url_scheme(base_url)

    current = read_hosted_config()
    if base_url is not None:
        current.base_url = base_url
    if api_key is not None:
        current.api_key = api_key

    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    lines: list[str] = []
    if current.base_url is not None:
        lines.append(f'base_url = "{_toml_escape(current.base_url)}"')
    if current.api_key is not None:
        lines.append(f'api_key = "{_toml_escape(current.api_key)}"')
    CONFIG_FILE.write_text(("\n".join(lines) + "\n") if lines else "")
    _chmod_private(CONFIG_FILE)
    return current


@dataclass
class LocalConfig:
    sidecar_url: str
    token: str


def read_local_env() -> LocalConfig | None:
    if not LOCAL_ENV_FILE.exists():
        return None
    values: dict[str, str] = {}
    for line in LOCAL_ENV_FILE.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        values[key.strip()] = value.strip()

    token = values.get("SIDECAR_AUTH_TOKEN")
    sidecar_url = values.get("SIDECAR_URL")
    if not token or not sidecar_url:
        return None
    return LocalConfig(sidecar_url=sidecar_url, token=token)


def write_local_env(*, token: str, sidecar_url: str) -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    LOCAL_ENV_FILE.write_text(
        "# Written by `boxkite up` — read automatically by `boxkite exec`/`boxkite files`.\n"
        f"SIDECAR_AUTH_TOKEN={token}\n"
        f"SIDECAR_URL={sidecar_url}\n"
    )
    _chmod_private(LOCAL_ENV_FILE)
