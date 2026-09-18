-- ============================================================
-- 01_tables.sql
-- Core schema: 9 tables for the Client Project Portal
-- ============================================================
-- Execution order matters due to foreign key dependencies.
-- The circular reference between projects ↔ project_phases
-- is resolved by creating projects first, then project_phases,
-- then adding current_phase_id via ALTER TABLE.
-- ============================================================

-- ---------------------------------------------------------
-- 1. profiles
-- Extended user information linked to Supabase Auth.
-- One row per authenticated user, created automatically
-- by the handle_new_user trigger (see 05_triggers.sql).
-- ---------------------------------------------------------
CREATE TABLE public.profiles (
  id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name   TEXT NOT NULL DEFAULT '',
  role        user_role NOT NULL DEFAULT 'client',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.profiles IS 'Extended user profile data. Role is the single source of truth for authorization.';
COMMENT ON COLUMN public.profiles.role IS 'Authorization role. Only modifiable by admin (enforced by trigger).';

-- ---------------------------------------------------------
-- 2. clients
-- Organizations/companies that hire us.
-- Currently one client, designed for growth.
-- ---------------------------------------------------------
CREATE TABLE public.clients (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name           TEXT NOT NULL,
  contact_name   TEXT NOT NULL,
  contact_email  TEXT NOT NULL,
  logo_url       TEXT,
  accent_color   TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.clients IS 'Client organizations. Each client can have multiple users and projects.';
COMMENT ON COLUMN public.clients.accent_color IS 'Optional hex color (e.g. #3B82F6) for future portal theming.';

-- ---------------------------------------------------------
-- 3. client_users
-- Junction table: which auth users belong to which client.
-- Enables multi-tenant isolation via RLS.
-- ---------------------------------------------------------
CREATE TABLE public.client_users (
  client_id   UUID NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (client_id, user_id)
);

COMMENT ON TABLE public.client_users IS 'Maps authenticated users to client organizations. Core table for tenant isolation.';

-- ---------------------------------------------------------
-- 4. projects
-- Core entity: each project belongs to exactly one client.
-- current_phase_id is added after project_phases exists.
-- ---------------------------------------------------------
CREATE TABLE public.projects (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id             UUID NOT NULL REFERENCES public.clients(id) ON DELETE RESTRICT,
  name                  TEXT NOT NULL,
  slug                  TEXT NOT NULL,
  description           TEXT,
  status                project_status NOT NULL DEFAULT 'planned',
  progress_percentage   INT NOT NULL DEFAULT 0,
  start_date            DATE,
  estimated_end_date    DATE,
  completed_at          TIMESTAMPTZ,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT chk_progress_range CHECK (progress_percentage BETWEEN 0 AND 100)
);

COMMENT ON TABLE public.projects IS 'Client projects. ON DELETE RESTRICT prevents accidental client deletion with active projects.';
COMMENT ON COLUMN public.projects.slug IS 'URL-friendly identifier. Unique per client (enforced by index).';
COMMENT ON COLUMN public.projects.progress_percentage IS 'Overall progress 0-100. Only admin can modify.';

-- ---------------------------------------------------------
-- 5. project_phases
-- Ordered roadmap phases within a project.
-- ---------------------------------------------------------
CREATE TABLE public.project_phases (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id    UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  name          TEXT NOT NULL,
  description   TEXT,
  status        phase_status NOT NULL DEFAULT 'pending',
  position      INT NOT NULL,
  started_at    TIMESTAMPTZ,
  completed_at  TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.project_phases IS 'Ordered phases within a project. At most one active phase per project (enforced by partial unique index).';
COMMENT ON COLUMN public.project_phases.position IS 'Display order. 1-based. Unique per project (enforced by index).';

-- ---------------------------------------------------------
-- Now add the circular FK: projects.current_phase_id
-- ---------------------------------------------------------
ALTER TABLE public.projects
  ADD COLUMN current_phase_id UUID REFERENCES public.project_phases(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.projects.current_phase_id IS 'Points to the currently active phase. SET NULL if phase is deleted.';

-- ---------------------------------------------------------
-- 6. project_updates
-- Timeline/changelog entries. Admin-only creation.
-- ---------------------------------------------------------
CREATE TABLE public.project_updates (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id  UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  created_by  UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title       TEXT,
  message     TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.project_updates IS 'Project timeline entries. Only admin can create/modify. Clients can read.';

-- ---------------------------------------------------------
-- 7. payments
-- Financial status display. No real payment processing.
-- ---------------------------------------------------------
CREATE TABLE public.payments (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id  UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  description TEXT NOT NULL,
  amount      NUMERIC(12, 2) NOT NULL,
  status      payment_status NOT NULL DEFAULT 'pending',
  due_date    DATE,
  paid_at     TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT chk_amount_positive CHECK (amount >= 0)
);

COMMENT ON TABLE public.payments IS 'Payment status records. Display only — no card data, no real transactions.';

-- ---------------------------------------------------------
-- 8. comments
-- Simple conversation between admin and client per project.
-- Comments are IMMUTABLE once posted (no edit allowed).
-- Soft-delete via deleted_at (admin only).
-- ---------------------------------------------------------
CREATE TABLE public.comments (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id  UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  message     TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at  TIMESTAMPTZ
);

COMMENT ON TABLE public.comments IS 'Project comments. Immutable after creation. Admin can soft-delete via deleted_at.';
COMMENT ON COLUMN public.comments.deleted_at IS 'Soft-delete timestamp. Only admin can set this. NULL = visible.';

-- ---------------------------------------------------------
-- 9. audit_logs
-- Administrative change tracking. Written by triggers only.
-- ---------------------------------------------------------
CREATE TABLE public.audit_logs (
  id          BIGSERIAL PRIMARY KEY,
  user_id     UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  project_id  UUID,
  action      TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id   UUID,
  old_values  JSONB,
  new_values  JSONB,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.audit_logs IS 'Administrative audit trail. Written exclusively by SECURITY DEFINER triggers. No direct user writes.';
COMMENT ON COLUMN public.audit_logs.action IS 'PostgreSQL trigger operation: INSERT, UPDATE, DELETE.';
COMMENT ON COLUMN public.audit_logs.entity_type IS 'Source table name (e.g. projects, project_phases, payments).';
