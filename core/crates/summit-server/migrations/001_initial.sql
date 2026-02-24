-- Summit server schema
-- Idempotent: safe to run on every startup

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Registered passkey credentials
CREATE TABLE IF NOT EXISTS passkey_credentials (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID        NOT NULL,
    credential_id BYTEA       NOT NULL UNIQUE,
    did_key       TEXT        NOT NULL UNIQUE,
    display_name  TEXT        NOT NULL DEFAULT '',
    passkey_json  TEXT        NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Pending WebAuthn registration challenges (short-lived)
CREATE TABLE IF NOT EXISTS pending_registrations (
    challenge_id UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID        NOT NULL,
    display_name TEXT        NOT NULL DEFAULT '',
    state_json   TEXT        NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at   TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '5 minutes'
);

-- Pending WebAuthn authentication challenges (short-lived)
CREATE TABLE IF NOT EXISTS pending_authentications (
    challenge_id UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    state_json   TEXT        NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at   TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '5 minutes'
);

-- Issued Verifiable Credentials
CREATE TABLE IF NOT EXISTS issued_vcs (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    subject_did TEXT        NOT NULL,
    vc_type     TEXT        NOT NULL,
    vc_json     TEXT        NOT NULL,
    issued_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS issued_vcs_subject_did ON issued_vcs(subject_did);

-- Node ↔ passkey bindings
CREATE TABLE IF NOT EXISTS node_bindings (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    passkey_did     TEXT        NOT NULL,
    node_did        TEXT        NOT NULL,
    binding_vc_json TEXT        NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(passkey_did, node_did)
);

-- Sessions (opaque UUID tokens stored in localStorage)
CREATE TABLE IF NOT EXISTS sessions (
    token       UUID        PRIMARY KEY,
    user_id     UUID        NOT NULL,
    passkey_did TEXT        NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at  TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '30 days'
);
