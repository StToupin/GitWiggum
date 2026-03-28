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
