CREATE TABLE meta (
  singleton INTEGER PRIMARY KEY CHECK(singleton=1),
  schema_version INTEGER NOT NULL CHECK(schema_version=1),
  schema_fingerprint TEXT NOT NULL CHECK(length(schema_fingerprint)=64 AND schema_fingerprint NOT GLOB '*[^0-9a-f]*'),
  codec_fingerprint TEXT NOT NULL CHECK(length(codec_fingerprint)=64 AND codec_fingerprint NOT GLOB '*[^0-9a-f]*'),
  store_id TEXT NOT NULL CHECK(length(store_id)=32 AND store_id NOT GLOB '*[^0-9a-f]*'),
  owner_run_id TEXT NOT NULL CHECK(length(owner_run_id)=32 AND owner_run_id NOT GLOB '*[^0-9a-f]*'),
  created_utc TEXT NOT NULL CHECK(length(created_utc)=20),
  commit_sequence TEXT NOT NULL CHECK(length(commit_sequence) BETWEEN 1 AND 20 AND commit_sequence NOT GLOB '*[^0-9]*' AND (commit_sequence='0' OR substr(commit_sequence,1,1)!='0') AND (length(commit_sequence)<20 OR commit_sequence COLLATE BINARY<='18446744073709551615'))
) STRICT;
CREATE TABLE players (
  commit_sequence TEXT NOT NULL CHECK(length(commit_sequence) BETWEEN 1 AND 20 AND commit_sequence NOT GLOB '*[^0-9]*' AND substr(commit_sequence,1,1) BETWEEN '1' AND '9' AND (length(commit_sequence)<20 OR commit_sequence COLLATE BINARY<='18446744073709551615')),
  id TEXT PRIMARY KEY NOT NULL CHECK(length(id)=32 AND id NOT GLOB '*[^0-9a-f]*'),
  revision TEXT NOT NULL CHECK(length(revision) BETWEEN 1 AND 20 AND revision NOT GLOB '*[^0-9]*' AND substr(revision,1,1) BETWEEN '1' AND '9' AND (length(revision)<20 OR revision COLLATE BINARY<='18446744073709551615')),
  record BLOB NOT NULL CHECK(length(record) BETWEEN 1 AND 8192),
  record_sha256 TEXT NOT NULL CHECK(length(record_sha256)=64 AND record_sha256 NOT GLOB '*[^0-9a-f]*')
) STRICT;
CREATE TABLE preferences (
  player_id TEXT PRIMARY KEY NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  revision TEXT NOT NULL CHECK(length(revision) BETWEEN 1 AND 20 AND revision NOT GLOB '*[^0-9]*' AND substr(revision,1,1) BETWEEN '1' AND '9' AND (length(revision)<20 OR revision COLLATE BINARY<='18446744073709551615')),
  record BLOB NOT NULL CHECK(length(record) BETWEEN 1 AND 614400),
  record_sha256 TEXT NOT NULL CHECK(length(record_sha256)=64 AND record_sha256 NOT GLOB '*[^0-9a-f]*')
) STRICT;
CREATE TABLE practices (
  id TEXT PRIMARY KEY NOT NULL CHECK(length(id)=32 AND id NOT GLOB '*[^0-9a-f]*'),
  player_id TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  source_fingerprint TEXT NOT NULL CHECK(length(source_fingerprint)=64 AND source_fingerprint NOT GLOB '*[^0-9a-f]*'),
  source_session TEXT NOT NULL CHECK(length(source_session) BETWEEN 1 AND 128),
  creation_sequence TEXT NOT NULL UNIQUE CHECK(length(creation_sequence) BETWEEN 1 AND 20 AND creation_sequence NOT GLOB '*[^0-9]*' AND substr(creation_sequence,1,1) BETWEEN '1' AND '9' AND (length(creation_sequence)<20 OR creation_sequence COLLATE BINARY<='18446744073709551615')),
  commit_sequence TEXT NOT NULL CHECK(length(commit_sequence) BETWEEN 1 AND 20 AND commit_sequence NOT GLOB '*[^0-9]*' AND substr(commit_sequence,1,1) BETWEEN '1' AND '9' AND (length(commit_sequence)<20 OR commit_sequence COLLATE BINARY<='18446744073709551615')),
  revision TEXT NOT NULL CHECK(length(revision) BETWEEN 1 AND 20 AND revision NOT GLOB '*[^0-9]*' AND substr(revision,1,1) BETWEEN '1' AND '9' AND (length(revision)<20 OR revision COLLATE BINARY<='18446744073709551615')),
  status TEXT NOT NULL CHECK(status IN ('active','manually_ended','source_ended','interrupted')),
  record BLOB NOT NULL CHECK(length(record) BETWEEN 1 AND 8192),
  record_sha256 TEXT NOT NULL CHECK(length(record_sha256)=64 AND record_sha256 NOT GLOB '*[^0-9a-f]*'),
  UNIQUE(source_fingerprint,source_session)
) STRICT;
CREATE UNIQUE INDEX practices_one_active ON practices(status) WHERE status='active';
CREATE INDEX practices_player_creation ON practices(player_id,length(creation_sequence) DESC,creation_sequence COLLATE BINARY DESC);
