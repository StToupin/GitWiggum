CREATE TABLE repositories (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    owner_user_id UUID NOT NULL,
    name TEXT NOT NULL,
    description TEXT DEFAULT NULL,
    is_private BOOLEAN DEFAULT FALSE NOT NULL,
    default_branch TEXT DEFAULT 'main' NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

ALTER TABLE repositories ADD CONSTRAINT repositories_ref_owner_user_id FOREIGN KEY (owner_user_id) REFERENCES users (id) ON DELETE CASCADE;
CREATE UNIQUE INDEX repositories_owner_user_id_name_idx ON repositories (owner_user_id, LOWER(name));
CREATE INDEX repositories_owner_user_id_idx ON repositories (owner_user_id);
