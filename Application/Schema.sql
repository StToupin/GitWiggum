CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE users (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    email TEXT NOT NULL,
    username TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    is_confirmed BOOLEAN DEFAULT FALSE NOT NULL,
    confirmation_token TEXT DEFAULT NULL,
    password_reset_token TEXT DEFAULT NULL,
    password_reset_token_expires_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    ssh_public_key TEXT DEFAULT NULL,
    failed_login_attempts INT DEFAULT 0 NOT NULL,
    locked_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

CREATE UNIQUE INDEX users_email_idx ON users ((LOWER(email)));
CREATE UNIQUE INDEX users_username_idx ON users (username);
CREATE INDEX users_confirmation_token_idx ON users (confirmation_token);
CREATE INDEX users_password_reset_token_idx ON users (password_reset_token);

CREATE TABLE repositories (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    owner_user_id UUID NOT NULL,
    name TEXT NOT NULL,
    description TEXT DEFAULT NULL,
    is_private BOOLEAN DEFAULT FALSE NOT NULL,
    default_branch TEXT DEFAULT 'main' NOT NULL,
    latest_commit_sha TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

ALTER TABLE repositories ADD CONSTRAINT repositories_ref_owner_user_id FOREIGN KEY (owner_user_id) REFERENCES users (id) ON DELETE CASCADE;
CREATE UNIQUE INDEX repositories_owner_user_id_name_idx ON repositories (owner_user_id, LOWER(name));
CREATE INDEX repositories_owner_user_id_idx ON repositories (owner_user_id);

CREATE TABLE pull_requests (
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

ALTER TABLE pull_requests ADD CONSTRAINT pull_requests_ref_repository_id FOREIGN KEY (repository_id) REFERENCES repositories (id) ON DELETE CASCADE;
ALTER TABLE pull_requests ADD CONSTRAINT pull_requests_ref_author_user_id FOREIGN KEY (author_user_id) REFERENCES users (id) ON DELETE CASCADE;
CREATE UNIQUE INDEX pull_requests_repository_id_number_idx ON pull_requests (repository_id, number);
CREATE INDEX pull_requests_repository_id_idx ON pull_requests (repository_id);
CREATE INDEX pull_requests_author_user_id_idx ON pull_requests (author_user_id);
CREATE INDEX pull_requests_state_idx ON pull_requests (state);

CREATE TABLE diff_ai_response_jobs (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    pull_request_id UUID NOT NULL,
    file_path TEXT NOT NULL,
    side TEXT NOT NULL,
    line_number INT NOT NULL,
    head_sha TEXT NOT NULL,
    fingerprint TEXT NOT NULL,
    response TEXT DEFAULT NULL,
    dismissed BOOLEAN DEFAULT FALSE NOT NULL,
    status JOB_STATUS DEFAULT 'job_status_not_started' NOT NULL,
    locked_by UUID DEFAULT NULL,
    locked_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    run_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    attempts_count INT DEFAULT 0 NOT NULL,
    last_error TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    CONSTRAINT diff_ai_response_jobs_side_check CHECK (side IN ('old', 'new'))
);

ALTER TABLE diff_ai_response_jobs ADD CONSTRAINT diff_ai_response_jobs_ref_pull_request_id FOREIGN KEY (pull_request_id) REFERENCES pull_requests (id) ON DELETE CASCADE;
CREATE UNIQUE INDEX diff_ai_response_jobs_fingerprint_idx ON diff_ai_response_jobs (fingerprint);
CREATE INDEX diff_ai_response_jobs_pull_request_id_idx ON diff_ai_response_jobs (pull_request_id);
CREATE INDEX diff_ai_response_jobs_status_idx ON diff_ai_response_jobs (status);

CREATE TABLE pull_request_review_comments (
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

ALTER TABLE pull_request_review_comments ADD CONSTRAINT pull_request_review_comments_ref_pull_request_id FOREIGN KEY (pull_request_id) REFERENCES pull_requests (id) ON DELETE CASCADE;
ALTER TABLE pull_request_review_comments ADD CONSTRAINT pull_request_review_comments_ref_author_user_id FOREIGN KEY (author_user_id) REFERENCES users (id) ON DELETE CASCADE;
CREATE INDEX pull_request_review_comments_pull_request_id_idx ON pull_request_review_comments (pull_request_id);
CREATE INDEX pull_request_review_comments_author_user_id_idx ON pull_request_review_comments (author_user_id);
CREATE INDEX pull_request_review_comments_location_idx ON pull_request_review_comments (pull_request_id, head_sha, file_path, side, line_number);
