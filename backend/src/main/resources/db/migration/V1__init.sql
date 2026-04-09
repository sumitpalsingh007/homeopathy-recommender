-- Flyway managed by the app; see /sql/ for the standalone DBA versions.
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS patient (
    id              BIGSERIAL PRIMARY KEY,
    email           VARCHAR(255) NOT NULL UNIQUE,
    password_hash   VARCHAR(255) NOT NULL,
    full_name       VARCHAR(255),
    age             INT,
    sex             VARCHAR(16),
    personality_notes TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS medicine (
    canonical_key            VARCHAR(128) PRIMARY KEY,
    display_name             VARCHAR(255) NOT NULL,
    allen_name               VARCHAR(255),
    kent_abbrev              VARCHAR(64),
    allen_description        TEXT,
    kent_lecture_description TEXT,
    aggravation              TEXT,
    amelioration             TEXT,
    relationship             TEXT,
    kent_symptom_count       INT
);
CREATE INDEX IF NOT EXISTS idx_medicine_display ON medicine (display_name);

CREATE TABLE IF NOT EXISTS consultation (
    id          BIGSERIAL PRIMARY KEY,
    patient_id  BIGINT NOT NULL REFERENCES patient(id) ON DELETE CASCADE,
    session_id  VARCHAR(64) NOT NULL UNIQUE,
    summary     TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_consultation_patient ON consultation (patient_id);

-- Spring AI PGVector managed table. Must match application.yml dimensions.
CREATE TABLE IF NOT EXISTS medicine_vectors (
    id          uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    content     text,
    metadata    jsonb,
    embedding   vector(768)
);
CREATE INDEX IF NOT EXISTS medicine_vectors_hnsw
    ON medicine_vectors USING hnsw (embedding vector_cosine_ops);
