-- Member Database Version Update
-- Generated: 2025-09-15T23:53:54Z
-- Version: 3.0.0.76

-- Create version table if it doesn't exist
CREATE TABLE IF NOT EXISTS member.schema_version (
    id SERIAL PRIMARY KEY,
    version VARCHAR(50) NOT NULL,
    major INTEGER NOT NULL,
    minor INTEGER NOT NULL,
    patch INTEGER NOT NULL,
    build INTEGER NOT NULL,
    git_commit VARCHAR(40),
    git_branch VARCHAR(100),
    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB
);

-- Insert version record
INSERT INTO member.schema_version (version, major, minor, patch, build, git_commit, git_branch, metadata)
VALUES (
    '3.0.0.76',
    3,
    0,
    0,
    76,
    '50d2e0e',
    'main',
    '{
        "timestamp": "2025-09-15T23:53:54Z",
        "dirty": true,
        "repository": "member-database-sql",
        "tier": "member"
    }'::jsonb
);
