"""Regression test: deploy/docker-compose.yml mounts /var/run/docker.sock
into the root-running sidecar container (needed for its `docker exec` into
the sandbox container). This is a full host-root escape primitive if the
sidecar is ever compromised -- verified directly during a security audit
that even a docker-socket-proxy configured with the minimal permissions
`docker exec` needs still permits creating a `--privileged` container with
the host root filesystem bind-mounted, so there is no cheap mitigation
available beyond documenting the risk prominently. This test guards against
that documentation being quietly dropped in a future edit (e.g. someone
"cleaning up" comments) rather than the risk itself, since the risk is
inherent to docker-compose's `docker exec`-based design.
"""

from __future__ import annotations

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SECURITY_MD_PATH = REPO_ROOT / "SECURITY.md"
DOCKER_COMPOSE_PATH = REPO_ROOT / "deploy" / "docker-compose.yml"


def test_security_md_documents_the_docker_sock_host_escape_risk():
    text = SECURITY_MD_PATH.read_text()
    assert "docker.sock" in text
    assert "privileged" in text.lower()
    assert "host" in text.lower()


def test_docker_compose_warns_at_the_docker_sock_mount_itself():
    text = DOCKER_COMPOSE_PATH.read_text()
    mount_line = "/var/run/docker.sock:/var/run/docker.sock"
    assert mount_line in text
    warning_marker = "CRITICAL, local-dev-only"
    assert warning_marker in text
    # The warning must appear BEFORE the mount line it's warning about.
    assert text.index(warning_marker) < text.index(mount_line)
