DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_type
        WHERE typname = 'job_status'
    ) THEN
        CREATE TYPE job_status AS ENUM (
            'job_status_not_started',
            'job_status_running',
            'job_status_failed',
            'job_status_timed_out',
            'job_status_succeeded',
            'job_status_retry'
        );
    END IF;
END
$$;

CREATE TABLE IF NOT EXISTS diff_ai_response_jobs (
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

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'diff_ai_response_jobs_ref_pull_request_id'
    ) THEN
        ALTER TABLE diff_ai_response_jobs
            ADD CONSTRAINT diff_ai_response_jobs_ref_pull_request_id
            FOREIGN KEY (pull_request_id)
            REFERENCES pull_requests (id)
            ON DELETE CASCADE;
    END IF;
END
$$;

CREATE UNIQUE INDEX IF NOT EXISTS diff_ai_response_jobs_fingerprint_idx ON diff_ai_response_jobs (fingerprint);
CREATE INDEX IF NOT EXISTS diff_ai_response_jobs_pull_request_id_idx ON diff_ai_response_jobs (pull_request_id);
CREATE INDEX IF NOT EXISTS diff_ai_response_jobs_status_idx ON diff_ai_response_jobs (status);
