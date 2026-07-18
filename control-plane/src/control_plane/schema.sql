-- boxkite control-plane schema (PostgreSQL).
--
-- Hand-maintained mirror of src/control_plane/models_orm.py, for operators
-- who want to inspect or apply the schema directly (e.g. via `psql`). The
-- running application does NOT execute this file — at startup it applies
-- the same tables via SQLAlchemy's `Base.metadata.create_all` (see
-- db.py:init_schema), which works identically against the Postgres DSN
-- configured in DATABASE_URL. Keep this file in sync when a column changes;
-- there is no Alembic migration chain yet for v1 (see the TODO below).
--
-- TODO(v2): once this schema needs to evolve post-release, replace
-- create_all with real Alembic migrations so existing deployments can be
-- upgraded without a destructive schema diff.
--
-- All statements are idempotent (IF NOT EXISTS) so this is safe to run
-- against an already-initialized database.

CREATE TABLE IF NOT EXISTS accounts (
    id                          UUID PRIMARY KEY,
    email                       VARCHAR(320) NOT NULL UNIQUE,
    -- Nullable: a social-login-only account (GitHub/Google, see github_id/
    -- google_id below) has no password at all. See
    -- docs/MCP-OAUTH-AND-SOCIAL-LOGIN-DESIGN.md §4.1.
    password_hash               VARCHAR(255),
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Optional per-account override for hosted /v1/sandboxes/{id}/exec's
    -- command allowlist. NULL means unrestricted (default for every account).
    -- See command_whitelist.py for the stored rule format.
    custom_allowed_commands     JSONB,
    -- Set once by POST /v1/auth/verify-email (opt-in,
    -- BOXKITE_EMAIL_VERIFICATION_ENABLED). NULL for every pre-existing
    -- account and informational only -- no route gates access on it.
    email_verified_at           TIMESTAMPTZ,
    -- Cross-account visibility grant (docs/ADMIN-ROLE-DESIGN.md). No API
    -- route ever sets this -- grant only via a direct UPDATE against this
    -- table, by design (no self-serve privilege escalation path).
    is_admin                    BOOLEAN NOT NULL DEFAULT false,
    -- Either, neither, or both may be set -- see
    -- docs/MCP-OAUTH-AND-SOCIAL-LOGIN-DESIGN.md §4.2.
    github_id                   VARCHAR(64) UNIQUE,
    google_id                   VARCHAR(64) UNIQUE,
    -- Enterprise SSO (docs/ENTERPRISE-SSO-DESIGN.md, issue #126 Phase 1).
    -- Same "either, neither, or alongside the columns above" posture.
    sso_provider_user_id        VARCHAR(191) UNIQUE,
    sso_organization_id         VARCHAR(191),
    sso_connection_id           VARCHAR(191),
    -- SCIM 2.0 provisioning via WorkOS Directory Sync (Phase 2 of issue
    -- #126). `scim_directory_user_id` is WorkOS's own "directory_user_..."
    -- id -- a genuinely distinct resource from sso_provider_user_id's
    -- "prof_..." id, not the same identifier reused (Directory Sync and
    -- SSO are two separate WorkOS products). `scim_deactivated_at` gates
    -- login (see models_orm.py's Account docstring) -- set once a
    -- dsync.user.updated/deleted event reports the directory user is no
    -- longer active.
    scim_directory_user_id      VARCHAR(191) UNIQUE,
    scim_deactivated_at         TIMESTAMPTZ
);

-- Upgrading an already-deployed database (this file/init_schema only
-- CREATE TABLE IF NOT EXISTS -- see the TODO(v2) above; it never ALTERs an
-- existing table): run these by hand before the SCIM webhook route is
-- enabled against that deployment.
--   ALTER TABLE accounts ADD COLUMN IF NOT EXISTS scim_directory_user_id VARCHAR(191) UNIQUE;
--   ALTER TABLE accounts ADD COLUMN IF NOT EXISTS scim_deactivated_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS ix_accounts_email ON accounts (email);
CREATE INDEX IF NOT EXISTS ix_accounts_sso_organization_id ON accounts (sso_organization_id);
CREATE INDEX IF NOT EXISTS ix_accounts_sso_connection_id ON accounts (sso_connection_id);
CREATE INDEX IF NOT EXISTS ix_accounts_scim_directory_user_id ON accounts (scim_directory_user_id);

CREATE TABLE IF NOT EXISTS api_keys (
    id              UUID PRIMARY KEY,
    account_id      UUID NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    name            VARCHAR(200) NOT NULL,
    prefix          VARCHAR(64) NOT NULL,
    key_hash        VARCHAR(64) NOT NULL UNIQUE,
    -- "admin" (default, every capability incl. WS /takeover) or "member"
    -- (everything except initiating a takeover session). See
    -- control_plane.security.can_initiate_takeover.
    role            VARCHAR(32) NOT NULL DEFAULT 'admin',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at      TIMESTAMPTZ,
    last_used_at    TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS ix_api_keys_account_id ON api_keys (account_id);
CREATE INDEX IF NOT EXISTS ix_api_keys_key_hash ON api_keys (key_hash);

-- Usage-accounting rows only. The sandbox pod's actual runtime state is
-- owned entirely by SandboxManager/Kubernetes, never mirrored here.
CREATE TABLE IF NOT EXISTS sandbox_sessions (
    id                  UUID PRIMARY KEY,
    account_id          UUID NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    pod_name            VARCHAR(255),
    label               VARCHAR(200),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    destroyed_at        TIMESTAMPTZ,
    duration_seconds    DOUBLE PRECISION,
    destroyed_reason    VARCHAR(64)
);

CREATE INDEX IF NOT EXISTS ix_sandbox_sessions_account_id ON sandbox_sessions (account_id);
CREATE INDEX IF NOT EXISTS ix_sandbox_sessions_account_active
    ON sandbox_sessions (account_id, destroyed_at);

-- Durable audit-log row, one per exec/file operation against a sandbox
-- session (agent-issued or, later, human-takeover-issued). See
-- docs/SANDBOX-OBSERVABILITY-DESIGN.md section 3.
--
-- row_hash/prev_hash (GitHub issue #136, docs/TAMPER-EVIDENT-AUDIT-DESIGN.md):
-- nullable, additive hash-chain columns -- rows written before this feature
-- shipped keep NULL in both. Since this file's own create_all-only startup
-- (no Alembic migration chain yet, per this file's header TODO) never adds
-- columns to an already-existing table, an operator upgrading a live
-- deployment must run the two ALTER TABLE statements below by hand before
-- the new code path starts writing these columns:
--   ALTER TABLE exec_log_entries ADD COLUMN IF NOT EXISTS row_hash VARCHAR(64);
--   ALTER TABLE exec_log_entries ADD COLUMN IF NOT EXISTS prev_hash VARCHAR(64);
-- A fresh install applying this file (or create_all against an empty
-- database) already gets both columns from the CREATE TABLE below.
CREATE TABLE IF NOT EXISTS exec_log_entries (
    id                  UUID PRIMARY KEY,
    session_id          UUID NOT NULL REFERENCES sandbox_sessions (id) ON DELETE CASCADE,
    account_id          UUID NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    source              VARCHAR(32) NOT NULL,
    operation           VARCHAR(32) NOT NULL,
    detail              JSONB NOT NULL,
    exit_code           INTEGER,
    output_truncated    TEXT,
    started_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    duration_ms         INTEGER NOT NULL,
    row_hash            VARCHAR(64),
    prev_hash           VARCHAR(64)
);

CREATE INDEX IF NOT EXISTS ix_exec_log_entries_session_id ON exec_log_entries (session_id);
CREATE INDEX IF NOT EXISTS ix_exec_log_entries_account_id ON exec_log_entries (account_id);
CREATE INDEX IF NOT EXISTS ix_exec_log_entries_session_started
    ON exec_log_entries (session_id, started_at);

-- Filesystem snapshot metadata (docs/SNAPSHOT-DESIGN.md). session_id is
-- nullable + SET NULL (not CASCADE) -- a snapshot must outlive the session
-- it was taken from. The actual snapshotted bytes live in blob storage
-- under storage_key_prefix, namespaced by account_id.
CREATE TABLE IF NOT EXISTS snapshots (
    id                  UUID PRIMARY KEY,
    account_id          UUID NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    session_id          UUID REFERENCES sandbox_sessions (id) ON DELETE SET NULL,
    label               VARCHAR(200),
    storage_key_prefix  VARCHAR(500) NOT NULL,
    size_bytes          INTEGER NOT NULL DEFAULT 0,
    status              VARCHAR(32) NOT NULL DEFAULT 'pending',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at          TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS ix_snapshots_account_id ON snapshots (account_id);
CREATE INDEX IF NOT EXISTS ix_snapshots_session_id ON snapshots (session_id);
CREATE INDEX IF NOT EXISTS ix_snapshots_account_created
    ON snapshots (account_id, created_at);

-- Org-scoped secret for the proxy-substitution secrets broker
-- (docs/SECRETS-DESIGN.md). The raw value is NEVER stored -- only an
-- envelope-encrypted ciphertext plus the metadata needed to decrypt it
-- (nonce, wrapped_data_key, encryption_key_id) -- see secrets_kms.py.
-- allowed_hosts is required, never null: an unscoped secret defeats the
-- entire point of this feature.
CREATE TABLE IF NOT EXISTS secrets (
    id                  UUID PRIMARY KEY,
    account_id          UUID NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    name                VARCHAR(200) NOT NULL,
    ciphertext          TEXT NOT NULL,
    nonce               VARCHAR(64) NOT NULL,
    wrapped_data_key    TEXT NOT NULL,
    encryption_key_id   VARCHAR(200) NOT NULL,
    allowed_hosts       JSONB NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_used_at        TIMESTAMPTZ,
    UNIQUE (account_id, name)
);

CREATE INDEX IF NOT EXISTS ix_secrets_account_id ON secrets (account_id);
CREATE INDEX IF NOT EXISTS ix_secrets_account_created ON secrets (account_id, created_at);

-- Org-scoped outbound-MCP connection grant (GitHub issues #116/#117,
-- docs/OUTBOUND-MCP-DESIGN.md §3). `host` is resolved from the curated
-- catalog (config.py's BOXKITE_MCP_CATALOG) at creation time and recorded
-- here -- never a caller-supplied hostname. No credential field: OAuth
-- credential handling for MCP catalog entries is an explicit open
-- question this feature does not solve.
CREATE TABLE IF NOT EXISTS mcp_connections (
    id                  UUID PRIMARY KEY,
    account_id          UUID NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    label               VARCHAR(200) NOT NULL,
    catalog_id          VARCHAR(100) NOT NULL,
    host                VARCHAR(255) NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_used_at        TIMESTAMPTZ,
    UNIQUE (account_id, label)
);

CREATE INDEX IF NOT EXISTS ix_mcp_connections_account_id ON mcp_connections (account_id);
CREATE INDEX IF NOT EXISTS ix_mcp_connections_account_created ON mcp_connections (account_id, created_at);

-- Opt-in dashboard-auth credential tables added for issue #79. Each is
-- gated by its own settings flag (BOXKITE_REFRESH_TOKENS_ENABLED,
-- BOXKITE_PASSWORD_RESET_ENABLED, BOXKITE_EMAIL_VERIFICATION_ENABLED, all
-- off by default) -- see routers/auth.py. All three follow api_keys'
-- credential-storage shape: only a SHA-256 digest of the raw token
-- (token_hash) is ever persisted.

CREATE TABLE IF NOT EXISTS refresh_tokens (
    id              UUID PRIMARY KEY,
    account_id      UUID NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    token_hash      VARCHAR(64) NOT NULL UNIQUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at      TIMESTAMPTZ NOT NULL,
    revoked_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS ix_refresh_tokens_account_id ON refresh_tokens (account_id);
CREATE INDEX IF NOT EXISTS ix_refresh_tokens_token_hash ON refresh_tokens (token_hash);
CREATE INDEX IF NOT EXISTS ix_refresh_tokens_account_created ON refresh_tokens (account_id, created_at);

CREATE TABLE IF NOT EXISTS password_reset_tokens (
    id              UUID PRIMARY KEY,
    account_id      UUID NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    token_hash      VARCHAR(64) NOT NULL UNIQUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at      TIMESTAMPTZ NOT NULL,
    used_at         TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS ix_password_reset_tokens_account_id ON password_reset_tokens (account_id);
CREATE INDEX IF NOT EXISTS ix_password_reset_tokens_token_hash ON password_reset_tokens (token_hash);
CREATE INDEX IF NOT EXISTS ix_password_reset_tokens_account_created
    ON password_reset_tokens (account_id, created_at);

CREATE TABLE IF NOT EXISTS email_verification_tokens (
    id              UUID PRIMARY KEY,
    account_id      UUID NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    token_hash      VARCHAR(64) NOT NULL UNIQUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at      TIMESTAMPTZ NOT NULL,
    used_at         TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS ix_email_verification_tokens_account_id ON email_verification_tokens (account_id);
CREATE INDEX IF NOT EXISTS ix_email_verification_tokens_token_hash ON email_verification_tokens (token_hash);
CREATE INDEX IF NOT EXISTS ix_email_verification_tokens_account_created
    ON email_verification_tokens (account_id, created_at);

-- Fixed-window request counters backing rate_limit.py's PostgresRateLimiter
-- -- the shared-store alternative to the default single-process in-memory
-- limiter, for deployments running more than one control-plane replica.
-- One row per (key, window_start); "key" mirrors the in-memory limiter's
-- own "{bucket}:{subject-or-ip}" key shape.
CREATE TABLE IF NOT EXISTS rate_limit_windows (
    key             VARCHAR(300) NOT NULL,
    window_start    INTEGER NOT NULL,
    count           INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (key, window_start)
);

-- One row per call to any /v1/admin/* route (docs/ADMIN-ROLE-DESIGN.md) --
-- the accountability side of the admin-role concept, since cross-account
-- visibility is new, sensitive surface. Written before the route's handler
-- runs (see deps.get_current_admin_account).
CREATE TABLE IF NOT EXISTS admin_access_log (
    id                  UUID PRIMARY KEY,
    admin_account_id    UUID NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    endpoint            VARCHAR(200) NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_admin_access_log_admin_created
    ON admin_access_log (admin_account_id, created_at);

-- MCP OAuth 2.1 authorization server (docs/MCP-OAUTH-AND-SOCIAL-LOGIN-DESIGN.md
-- §3). One row per MCP client that has dynamically registered itself via
-- POST /oauth/register (RFC 7591). Always a public client -- no
-- client_secret is ever issued or stored; PKCE (S256-only) is mandatory
-- instead.
CREATE TABLE IF NOT EXISTS oauth_clients (
    id              UUID PRIMARY KEY,
    client_id       VARCHAR(64) NOT NULL UNIQUE,
    client_name     VARCHAR(200) NOT NULL,
    redirect_uris   JSONB NOT NULL,
    client_type     VARCHAR(32) NOT NULL DEFAULT 'public',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_oauth_clients_client_id ON oauth_clients (client_id);

-- One row per in-flight GET /oauth/authorize grant -- single-use, short
-- TTL. account_id is set once the resource owner approves; consumed_at is
-- set atomically on exchange at POST /oauth/token so a code can never be
-- exchanged twice.
CREATE TABLE IF NOT EXISTS oauth_authorization_codes (
    id                      UUID PRIMARY KEY,
    code                    VARCHAR(128) NOT NULL UNIQUE,
    client_id               VARCHAR(64) NOT NULL REFERENCES oauth_clients (client_id) ON DELETE CASCADE,
    account_id              UUID NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    redirect_uri            VARCHAR(2048) NOT NULL,
    code_challenge          VARCHAR(128) NOT NULL,
    code_challenge_method   VARCHAR(16) NOT NULL DEFAULT 'S256',
    scope                   VARCHAR(200),
    expires_at              TIMESTAMPTZ NOT NULL,
    consumed_at             TIMESTAMPTZ,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_oauth_auth_codes_code ON oauth_authorization_codes (code);
CREATE INDEX IF NOT EXISTS ix_oauth_auth_codes_client_id ON oauth_authorization_codes (client_id);
CREATE INDEX IF NOT EXISTS ix_oauth_auth_codes_account_id ON oauth_authorization_codes (account_id);
CREATE INDEX IF NOT EXISTS ix_oauth_auth_codes_expires_at ON oauth_authorization_codes (expires_at);

-- One row per issued refresh token (access tokens are stateless JWTs,
-- never stored). refresh_token_hash uses the same SHA-256 hash_secret
-- helper API keys already use -- the raw refresh token is never
-- persisted. rotated_from chains each rotation back to the token it
-- replaced, so a reuse-detection hit can revoke the whole chain.
CREATE TABLE IF NOT EXISTS oauth_tokens (
    id                      UUID PRIMARY KEY,
    refresh_token_hash      VARCHAR(64) NOT NULL UNIQUE,
    client_id               VARCHAR(64) NOT NULL REFERENCES oauth_clients (client_id) ON DELETE CASCADE,
    account_id              UUID NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at              TIMESTAMPTZ,
    rotated_from            UUID REFERENCES oauth_tokens (id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS ix_oauth_tokens_hash ON oauth_tokens (refresh_token_hash);
CREATE INDEX IF NOT EXISTS ix_oauth_tokens_client_id ON oauth_tokens (client_id);
CREATE INDEX IF NOT EXISTS ix_oauth_tokens_account_id ON oauth_tokens (account_id);
CREATE INDEX IF NOT EXISTS ix_oauth_tokens_account_created ON oauth_tokens (account_id, created_at);

-- Outbound webhook registration (docs/WEBHOOKS-DESIGN.md). The signing
-- secret is envelope-encrypted at rest using the exact same primitive
-- `secrets.ciphertext`/nonce/wrapped_data_key/encryption_key_id above use --
-- see secrets_kms.py. The raw secret is returned to the caller exactly
-- once, at creation time, and never stored in plaintext.
CREATE TABLE IF NOT EXISTS webhook_subscriptions (
    id                          UUID PRIMARY KEY,
    account_id                  UUID NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    url                         VARCHAR(2048) NOT NULL,
    description                 VARCHAR(200),
    event_types                 JSONB NOT NULL,
    ciphertext                  TEXT NOT NULL,
    nonce                       VARCHAR(64) NOT NULL,
    wrapped_data_key            TEXT NOT NULL,
    encryption_key_id           VARCHAR(200) NOT NULL,
    is_active                   BOOLEAN NOT NULL DEFAULT true,
    -- 'boxkite_v1' (default) or 'splunk_hec' -- see webhooks.py's
    -- WEBHOOK_PAYLOAD_FORMATS. hec_token_* is an OPTIONAL destination
    -- credential (the receiver's Splunk HEC token), envelope-encrypted at
    -- rest with the exact same primitive as ciphertext/nonce/
    -- wrapped_data_key/encryption_key_id above, added per GitHub issue #125
    -- (SIEM/audit-log export).
    payload_format              VARCHAR(32) NOT NULL DEFAULT 'boxkite_v1',
    hec_token_ciphertext        TEXT,
    hec_token_nonce             VARCHAR(64),
    hec_token_wrapped_data_key  TEXT,
    hec_token_encryption_key_id VARCHAR(200),
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_triggered_at           TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS ix_webhook_subscriptions_account_created
    ON webhook_subscriptions (account_id, created_at);

-- One row per fired-event-x-matching-subscription delivery attempt
-- (docs/WEBHOOKS-DESIGN.md). Updated in place across retries by
-- webhook_delivery.py's background worker, never re-created per attempt.
CREATE TABLE IF NOT EXISTS webhook_deliveries (
    id                          UUID PRIMARY KEY,
    subscription_id             UUID NOT NULL REFERENCES webhook_subscriptions (id) ON DELETE CASCADE,
    account_id                  UUID NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    event_type                  VARCHAR(64) NOT NULL,
    payload                     JSONB NOT NULL,
    status                      VARCHAR(32) NOT NULL DEFAULT 'pending',
    attempt_count               INTEGER NOT NULL DEFAULT 0,
    next_attempt_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_attempt_at             TIMESTAMPTZ,
    response_status_code        INTEGER,
    response_body_truncated     TEXT,
    failure_reason              VARCHAR(500),
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    delivered_at                TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS ix_webhook_deliveries_subscription_created
    ON webhook_deliveries (subscription_id, created_at);
CREATE INDEX IF NOT EXISTS ix_webhook_deliveries_status_next_attempt
    ON webhook_deliveries (status, next_attempt_at);
