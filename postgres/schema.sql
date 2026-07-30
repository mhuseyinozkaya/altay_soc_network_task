-- SOC görevi veritabanı şeması
-- Policy Engine (FastAPI) ve Wazuh bu tabloları okuyup yazacak.

CREATE TYPE access_profile AS ENUM ('admin', 'employee', 'guest', 'quarantine');
CREATE TYPE auth_method AS ENUM ('vpn', 'eap-tls');
CREATE TYPE auth_result AS ENUM ('success', 'failure');

-- Yerel kullanıcı / profil tanımı
CREATE TABLE users (
    id              SERIAL PRIMARY KEY,
    username        VARCHAR(64) UNIQUE NOT NULL,
    profile         access_profile NOT NULL DEFAULT 'guest',
    vlan_id         INTEGER,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- EAP-TLS sertifika kayıtları
CREATE TABLE certificates (
    id              SERIAL PRIMARY KEY,
    user_id         INTEGER REFERENCES users(id) ON DELETE CASCADE,
    common_name     VARCHAR(128) NOT NULL,
    serial_number   VARCHAR(64) NOT NULL UNIQUE,
    valid_from      TIMESTAMPTZ NOT NULL,
    valid_to        TIMESTAMPTZ NOT NULL,
    revoked         BOOLEAN NOT NULL DEFAULT false,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Her VPN / EAP-TLS giriş denemesi (Policy Engine kararı burada loglanır)
CREATE TABLE auth_events (
    id                  BIGSERIAL PRIMARY KEY,
    username            VARCHAR(64),
    method              auth_method NOT NULL,
    result              auth_result NOT NULL,
    assigned_profile    access_profile,
    assigned_vlan       INTEGER,
    source_ip           INET NOT NULL,
    reason              TEXT,               -- red/kabul gerekçesi
    occurred_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_auth_events_occurred_at ON auth_events (occurred_at DESC);
CREATE INDEX idx_auth_events_source_ip   ON auth_events (source_ip);
CREATE INDEX idx_auth_events_result      ON auth_events (result);

-- Wazuh active-response tarafından tetiklenen aksiyonlar
CREATE TABLE security_actions (
    id              BIGSERIAL PRIMARY KEY,
    trigger_event_id BIGINT REFERENCES auth_events(id),
    action_type     VARCHAR(32) NOT NULL,   -- 'block_ip' | 'quarantine_vlan' vb.
    target          VARCHAR(64) NOT NULL,   -- IP veya kullanıcı adı
    detail          TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Test/lab amaçlı örnek kullanıcılar (freeradius/users ile tutarlı)
INSERT INTO users (username, profile, vlan_id) VALUES
    ('testadmin',    'admin',    10),
    ('testemployee', 'employee', 20),
    ('testguest',    'guest',    30);
