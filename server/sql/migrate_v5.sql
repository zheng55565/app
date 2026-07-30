-- v5：AI Word/PPT 异步任务与安全下载记录
-- 可重复执行。生产发布时先执行本迁移，再启动包含文档 Worker 的服务。

CREATE TABLE IF NOT EXISTS ai_document_jobs (
    id UUID PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    conversation_id UUID REFERENCES ai_conversations(id) ON DELETE SET NULL,
    kind VARCHAR(12) NOT NULL CHECK (kind IN ('docx', 'pptx')),
    status VARCHAR(20) NOT NULL DEFAULT 'queued'
        CHECK (status IN ('queued', 'processing', 'completed', 'failed', 'cancelled', 'expired')),
    prompt TEXT NOT NULL,
    model VARCHAR(200) NOT NULL,
    image_model VARCHAR(200),
    use_images BOOLEAN NOT NULL DEFAULT FALSE,
    progress SMALLINT NOT NULL DEFAULT 0 CHECK (progress BETWEEN 0 AND 100),
    title VARCHAR(200),
    artifact_name VARCHAR(240),
    artifact_path TEXT,
    artifact_bytes BIGINT,
    output_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    error_message TEXT,
    attempts SMALLINT NOT NULL DEFAULT 0,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    expires_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ai_document_jobs_user
    ON ai_document_jobs (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_document_jobs_queue
    ON ai_document_jobs (status, created_at)
    WHERE status IN ('queued', 'processing');
CREATE INDEX IF NOT EXISTS idx_ai_document_jobs_expiry
    ON ai_document_jobs (expires_at)
    WHERE status = 'completed';

