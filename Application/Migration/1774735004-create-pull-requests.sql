CREATE TABLE IF NOT EXISTS pull_requests (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    repository_id UUID NOT NULL,
    number INT NOT NULL,
    title TEXT NOT NULL,
    description TEXT DEFAULT NULL,
    base_branch TEXT NOT NULL,
    compare_branch TEXT NOT NULL,
    author_user_id UUID NOT NULL,
    state TEXT DEFAULT 'open' NOT NULL,
    is_draft BOOLEAN DEFAULT FALSE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'pull_requests_ref_repository_id'
    ) THEN
        ALTER TABLE pull_requests
            ADD CONSTRAINT pull_requests_ref_repository_id
            FOREIGN KEY (repository_id) REFERENCES repositories (id) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'pull_requests_ref_author_user_id'
    ) THEN
        ALTER TABLE pull_requests
            ADD CONSTRAINT pull_requests_ref_author_user_id
            FOREIGN KEY (author_user_id) REFERENCES users (id) ON DELETE CASCADE;
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS pull_requests_repository_id_number_idx ON pull_requests (repository_id, number);
CREATE INDEX IF NOT EXISTS pull_requests_repository_id_idx ON pull_requests (repository_id);
CREATE INDEX IF NOT EXISTS pull_requests_author_user_id_idx ON pull_requests (author_user_id);
CREATE INDEX IF NOT EXISTS pull_requests_state_idx ON pull_requests (state);
