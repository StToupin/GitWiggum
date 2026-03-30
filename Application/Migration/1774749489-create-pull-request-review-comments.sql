CREATE TABLE IF NOT EXISTS pull_request_review_comments (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    pull_request_id UUID NOT NULL,
    author_user_id UUID NOT NULL,
    file_path TEXT NOT NULL,
    side TEXT NOT NULL,
    line_number INT NOT NULL,
    head_sha TEXT NOT NULL,
    body TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    CONSTRAINT pull_request_review_comments_side_check CHECK (side IN ('old', 'new')),
    CONSTRAINT pull_request_review_comments_line_number_check CHECK (line_number > 0)
);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'pull_request_review_comments_ref_pull_request_id'
    ) THEN
        ALTER TABLE pull_request_review_comments
            ADD CONSTRAINT pull_request_review_comments_ref_pull_request_id
            FOREIGN KEY (pull_request_id)
            REFERENCES pull_requests (id)
            ON DELETE CASCADE;
    END IF;
END
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'pull_request_review_comments_ref_author_user_id'
    ) THEN
        ALTER TABLE pull_request_review_comments
            ADD CONSTRAINT pull_request_review_comments_ref_author_user_id
            FOREIGN KEY (author_user_id)
            REFERENCES users (id)
            ON DELETE CASCADE;
    END IF;
END
$$;

CREATE INDEX IF NOT EXISTS pull_request_review_comments_pull_request_id_idx ON pull_request_review_comments (pull_request_id);
CREATE INDEX IF NOT EXISTS pull_request_review_comments_author_user_id_idx ON pull_request_review_comments (author_user_id);
CREATE INDEX IF NOT EXISTS pull_request_review_comments_location_idx ON pull_request_review_comments (pull_request_id, head_sha, file_path, side, line_number);
