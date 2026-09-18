-- ============================================================
-- 02_indexes.sql
-- Performance indexes, unique constraints, and data integrity
-- ============================================================

-- ---------------------------------------------------------
-- profiles
-- ---------------------------------------------------------
-- PK on id already serves as the primary lookup.
-- Role index speeds up is_admin() helper function.
CREATE INDEX idx_profiles_role ON public.profiles (role);

-- ---------------------------------------------------------
-- client_users
-- ---------------------------------------------------------
-- PK is (client_id, user_id) → client_id is already the leading column.
-- We need an index on user_id for get_client_ids() which queries by user_id.
CREATE INDEX idx_client_users_user_id ON public.client_users (user_id);

-- ---------------------------------------------------------
-- projects
-- ---------------------------------------------------------
-- Fast lookup: all projects for a given client
CREATE INDEX idx_projects_client_id ON public.projects (client_id);

-- URL-friendly slug: unique PER CLIENT (not globally)
-- Two different clients can have a project with slug "website-redesign"
CREATE UNIQUE INDEX idx_projects_client_slug ON public.projects (client_id, slug);

-- ---------------------------------------------------------
-- project_phases
-- ---------------------------------------------------------
-- All phases for a project
CREATE INDEX idx_project_phases_project_id ON public.project_phases (project_id);

-- Ordered phase listing: phases sorted by position within a project
CREATE UNIQUE INDEX idx_project_phases_position ON public.project_phases (project_id, position);

-- CRITICAL: Enforce at most ONE active phase per project.
-- This is a partial unique index — it only indexes rows where status = 'active'.
-- PostgreSQL will reject any INSERT or UPDATE that would create a second
-- active phase for the same project.
CREATE UNIQUE INDEX idx_one_active_phase_per_project
  ON public.project_phases (project_id)
  WHERE status = 'active';

-- ---------------------------------------------------------
-- project_updates
-- ---------------------------------------------------------
-- Timeline entries per project, typically ordered by created_at
CREATE INDEX idx_project_updates_project_id ON public.project_updates (project_id);

-- ---------------------------------------------------------
-- payments
-- ---------------------------------------------------------
-- Payment records per project
CREATE INDEX idx_payments_project_id ON public.payments (project_id);

-- ---------------------------------------------------------
-- comments
-- ---------------------------------------------------------
-- Comments per project
CREATE INDEX idx_comments_project_id ON public.comments (project_id);

-- ---------------------------------------------------------
-- audit_logs
-- ---------------------------------------------------------
-- Lookup audit entries by entity (e.g., "show me all changes to project X")
CREATE INDEX idx_audit_logs_entity ON public.audit_logs (entity_type, entity_id);

-- Lookup audit entries by project
CREATE INDEX idx_audit_logs_project_id ON public.audit_logs (project_id);

-- Chronological queries (most recent first)
CREATE INDEX idx_audit_logs_created_at ON public.audit_logs (created_at DESC);
