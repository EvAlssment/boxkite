# Changelog

All notable changes to boxkite are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); dates are UTC.

## v0.2.0 — 2026-07-18

### Added
- Helm chart (`deploy/helm/boxkite/`) wrapping the existing cluster-level
  manifests (RBAC, NetworkPolicy, pod security policy, image-builder RBAC).
- SBOM generation (SPDX, via Syft) and keyless cosign/Sigstore image signing
  in the image-publish workflow, ahead of the EU CRA's vulnerability-
  reporting deadline.
- A one-click Render Blueprint deploy for the control-plane API
  (`deploy/render.yaml`).
- `boxkite mcp init <target>` — wires the MCP server into Claude Code,
  Cursor, Windsurf, or Claude Desktop's config in one command.
- A GCS storage backend for the sidecar's file-sync path, alongside the
  existing S3 and Azure Blob backends.
- Secret management (`create_secret`/`list_secrets`/`delete_secret`, or the
  language-appropriate casing) across all four SDKs — previously only
  *referencing* an existing secret by name at sandbox-creation time was
  supported.
- A short-lived, single-use token letting the dashboard create a sandbox
  directly from a logged-in session, instead of requiring a pasted API key.
- Live usage-rollup, dynamic SDK code snippets, and email-verification
  status in the dashboard UI.

### Fixed
- Accessibility: a real focus trap and correct dialog semantics on the
  destroy-sandbox confirmation modal, plus contrast and reduced-motion
  fixes.
- A cross-replica race in the control-plane's session-count enforcement
  (`BOXKITE_USAGE_LOCK_BACKEND=postgres`, opt-in) — the default single-
  process lock could be exceeded across multiple control-plane replicas.
- `DATABASE_URL` now normalizes a bare `postgres://`/`postgresql://` (as
  handed back by Render, Heroku, and other managed Postgres providers) to
  the `+asyncpg` driver form `create_async_engine()` requires.
- Documentation accuracy: `sdk-rust`/`sdk-go` are now listed in the
  packages table and comparison docs, instead of being described as
  unsupported languages.

## v0.1.0 — 2026-07-12

Initial public release: the self-hostable sandbox runtime (`src/boxkite/`),
the sidecar, the hosted-API control-plane, four client SDKs (Python, JS/TS,
Go, Rust), the MCP server, and the standalone SSH bastion — all under the
MIT license.
