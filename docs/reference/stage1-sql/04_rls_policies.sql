-- ============================================================
-- 04_rls_policies.sql
-- Row Level Security policies for all tables
-- ============================================================
-- Security model:
--   ADMIN: Full CRUD on all business tables. Read audit_logs.
--   CLIENT: Read-only on their own client's data. Can INSERT
--           comments on their own projects only. No writes
--           to any other table.
--
-- Performance notes:
--   - (SELECT auth.uid()) caches the value as a subplan
--   - (SELECT public.is_admin()) caches the boolean result
--   - (SELECT public.get_client_ids()) caches the client IDs
--   These patterns prevent per-row re-evaluation.
--
-- Policy naming convention:
--   {table}_{operation}_{who}
-- ============================================================


-- =========================================================
-- ENABLE RLS ON ALL TABLES
-- =========================================================
-- Once enabled, default access is DENIED unless a policy
-- explicitly grants it. This is the secure default.
-- =========================================================

ALTER TABLE public.profiles        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clients         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_users    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.projects        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.project_phases  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.project_updates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.comments        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs      ENABLE ROW LEVEL SECURITY;


-- =========================================================
-- PROFILES
-- =========================================================
-- Users can read their own profile.
-- Admin can read all profiles.
-- Users can update their own profile (role change blocked by trigger).
-- No INSERT policy needed (handled by handle_new_user trigger).
-- No DELETE policy (profiles cascade-delete with auth.users).
-- =========================================================

CREATE POLICY "profiles_select_own"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (id = (SELECT auth.uid()));

CREATE POLICY "profiles_select_admin"
  ON public.profiles FOR SELECT
  TO authenticated
  USING ((SELECT public.is_admin()));

CREATE POLICY "profiles_update_own"
  ON public.profiles FOR UPDATE
  TO authenticated
  USING (id = (SELECT auth.uid()))
  WITH CHECK (id = (SELECT auth.uid()));


-- =========================================================
-- CLIENTS
-- =========================================================
-- Admin: full CRUD.
-- Client: read only their own client organization.
-- =========================================================

CREATE POLICY "clients_all_admin"
  ON public.clients FOR ALL
  TO authenticated
  USING ((SELECT public.is_admin()))
  WITH CHECK ((SELECT public.is_admin()));

CREATE POLICY "clients_select_own"
  ON public.clients FOR SELECT
  TO authenticated
  USING (id IN (SELECT public.get_client_ids()));


-- =========================================================
-- CLIENT_USERS
-- =========================================================
-- Admin: full CRUD (manages user-client assignments).
-- Client: can read their own membership row.
-- =========================================================

CREATE POLICY "client_users_all_admin"
  ON public.client_users FOR ALL
  TO authenticated
  USING ((SELECT public.is_admin()))
  WITH CHECK ((SELECT public.is_admin()));

CREATE POLICY "client_users_select_own"
  ON public.client_users FOR SELECT
  TO authenticated
  USING (user_id = (SELECT auth.uid()));


-- =========================================================
-- PROJECTS
-- =========================================================
-- Admin: full CRUD.
-- Client: read only projects belonging to their client.
-- =========================================================

CREATE POLICY "projects_all_admin"
  ON public.projects FOR ALL
  TO authenticated
  USING ((SELECT public.is_admin()))
  WITH CHECK ((SELECT public.is_admin()));

CREATE POLICY "projects_select_client"
  ON public.projects FOR SELECT
  TO authenticated
  USING (client_id IN (SELECT public.get_client_ids()));


-- =========================================================
-- PROJECT_PHASES
-- =========================================================
-- Admin: full CRUD.
-- Client: read only phases of their projects.
-- =========================================================

CREATE POLICY "phases_all_admin"
  ON public.project_phases FOR ALL
  TO authenticated
  USING ((SELECT public.is_admin()))
  WITH CHECK ((SELECT public.is_admin()));

CREATE POLICY "phases_select_client"
  ON public.project_phases FOR SELECT
  TO authenticated
  USING (
    project_id IN (
      SELECT id FROM public.projects
      WHERE client_id IN (SELECT public.get_client_ids())
    )
  );


-- =========================================================
-- PROJECT_UPDATES
-- =========================================================
-- Admin: full CRUD.
-- Client: read only updates of their projects.
-- =========================================================

CREATE POLICY "updates_all_admin"
  ON public.project_updates FOR ALL
  TO authenticated
  USING ((SELECT public.is_admin()))
  WITH CHECK ((SELECT public.is_admin()));

CREATE POLICY "updates_select_client"
  ON public.project_updates FOR SELECT
  TO authenticated
  USING (
    project_id IN (
      SELECT id FROM public.projects
      WHERE client_id IN (SELECT public.get_client_ids())
    )
  );


-- =========================================================
-- PAYMENTS
-- =========================================================
-- Admin: full CRUD.
-- Client: read only payments of their projects.
-- =========================================================

CREATE POLICY "payments_all_admin"
  ON public.payments FOR ALL
  TO authenticated
  USING ((SELECT public.is_admin()))
  WITH CHECK ((SELECT public.is_admin()));

CREATE POLICY "payments_select_client"
  ON public.payments FOR SELECT
  TO authenticated
  USING (
    project_id IN (
      SELECT id FROM public.projects
      WHERE client_id IN (SELECT public.get_client_ids())
    )
  );


-- =========================================================
-- COMMENTS
-- =========================================================
-- Comments are IMMUTABLE once posted. No UPDATE for clients.
--
-- Admin:
--   - Can read ALL comments (including soft-deleted).
--   - Can insert comments (user_id must match their own).
--   - Can soft-delete any comment (UPDATE to set deleted_at).
--
-- Client:
--   - Can read comments on their projects (excluding deleted).
--   - Can insert comments on their projects only.
--   - CANNOT update or delete comments.
-- =========================================================

-- Admin read (includes soft-deleted for moderation)
CREATE POLICY "comments_select_admin"
  ON public.comments FOR SELECT
  TO authenticated
  USING ((SELECT public.is_admin()));

-- Admin insert (must use own user_id)
CREATE POLICY "comments_insert_admin"
  ON public.comments FOR INSERT
  TO authenticated
  WITH CHECK (
    (SELECT public.is_admin())
    AND user_id = (SELECT auth.uid())
  );

-- Admin soft-delete (set deleted_at on any comment)
CREATE POLICY "comments_update_admin"
  ON public.comments FOR UPDATE
  TO authenticated
  USING ((SELECT public.is_admin()))
  WITH CHECK ((SELECT public.is_admin()));

-- Client read (only their projects, exclude soft-deleted)
CREATE POLICY "comments_select_client"
  ON public.comments FOR SELECT
  TO authenticated
  USING (
    deleted_at IS NULL
    AND project_id IN (
      SELECT id FROM public.projects
      WHERE client_id IN (SELECT public.get_client_ids())
    )
  );

-- Client insert (only on their projects, must use own user_id)
CREATE POLICY "comments_insert_client"
  ON public.comments FOR INSERT
  TO authenticated
  WITH CHECK (
    user_id = (SELECT auth.uid())
    AND project_id IN (
      SELECT id FROM public.projects
      WHERE client_id IN (SELECT public.get_client_ids())
    )
  );


-- =========================================================
-- AUDIT_LOGS
-- =========================================================
-- Read-only for admin. No direct writes allowed.
-- All inserts come from SECURITY DEFINER trigger functions.
-- =========================================================

CREATE POLICY "audit_logs_select_admin"
  ON public.audit_logs FOR SELECT
  TO authenticated
  USING ((SELECT public.is_admin()));
