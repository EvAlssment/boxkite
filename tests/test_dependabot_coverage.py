"""Regression test: .github/dependabot.yml previously only covered the root
pip package, /deploy's npm/docker directories, and github-actions -- leaving
control-plane/, sdk-python/, mcp-server/ (pip), sdk-js/ (npm), and
control-plane/Dockerfile (docker) with no automated dependency/CVE alerts at
all. This asserts every directory with a manifest Dependabot can act on is
actually configured, so a newly added sub-package can't silently go
uncovered again.

`site/` (npm) used to be covered here too, before this repo's public/
self-hostable product and private/ hosted-ops layer (which owns site/) were
split into their own trees -- see docs/OSS-VS-HOSTED-SPLIT-POSITION.md.
private/ carries its own dependabot.yml covering site/ now.
"""

from __future__ import annotations

from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
DEPENDABOT_PATH = REPO_ROOT / ".github" / "dependabot.yml"

EXPECTED_PIP_DIRS = {"/", "/control-plane", "/sdk-python", "/mcp-server"}
EXPECTED_NPM_DIRS = {"/deploy", "/sdk-js"}
EXPECTED_DOCKER_DIRS = {"/deploy", "/control-plane"}


def _dirs_for_ecosystem(ecosystem: str) -> set[str]:
    doc = yaml.safe_load(DEPENDABOT_PATH.read_text())
    return {u["directory"] for u in doc["updates"] if u["package-ecosystem"] == ecosystem}


def test_every_pyproject_toml_directory_is_covered():
    # Confirms the manifests this test asserts against actually exist, so it
    # can't pass vacuously if a sub-package is ever removed.
    for rel_dir in EXPECTED_PIP_DIRS:
        assert (REPO_ROOT / rel_dir.lstrip("/") / "pyproject.toml").is_file(), (
            f"{rel_dir}/pyproject.toml not found -- update EXPECTED_PIP_DIRS if this "
            "sub-package was removed or renamed"
        )
    assert _dirs_for_ecosystem("pip") == EXPECTED_PIP_DIRS


def test_every_package_json_directory_is_covered():
    for rel_dir in EXPECTED_NPM_DIRS:
        assert (REPO_ROOT / rel_dir.lstrip("/") / "package.json").is_file(), (
            f"{rel_dir}/package.json not found -- update EXPECTED_NPM_DIRS if this "
            "sub-package was removed or renamed"
        )
    assert _dirs_for_ecosystem("npm") == EXPECTED_NPM_DIRS


def test_every_dockerfile_directory_is_covered():
    for rel_dir in EXPECTED_DOCKER_DIRS:
        dockerfiles = list((REPO_ROOT / rel_dir.lstrip("/")).glob("*Dockerfile*"))
        assert dockerfiles, f"no Dockerfile found under {rel_dir} -- update EXPECTED_DOCKER_DIRS"
    assert _dirs_for_ecosystem("docker") == EXPECTED_DOCKER_DIRS


def test_github_actions_ecosystem_is_still_configured():
    assert _dirs_for_ecosystem("github-actions") == {"/"}
