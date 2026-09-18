-- ============================================================
-- 05_triggers.sql
-- Trigger functions and trigger attachments
-- ============================================================
-- All SECURITY DEFINER functions use SET search_path = ''
-- to prevent search-path hijacking attacks.
-- ============================================================


-- =========================================================
-- 1. AUTO-CREATE PROFILE ON USER SIGNUP
-- =========================================================
-- When a user is created in auth.users (via Dashboard or API),
-- this trigger automatically creates a profiles row with
-- role = 'client'. The admin must then manually UPDATE the
-- role to 'admin' for admin accounts via the SQL Editor.
-- =========================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, role)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data ->> 'full_name', ''),
    'client'  -- ALWAYS default to 'client'. Never trust metadata for role.
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();


-- =========================================================
-- 2. PROTECT ROLE MODIFICATION
-- =========================================================
-- Prevents non-admin users from changing their own role
-- via the SDK. Even if RLS allows UPDATE on profiles,
-- this trigger rejects role changes from non-admin callers.
-- =========================================================

CREATE OR REPLACE FUNCTION public.protect_role_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  -- If role is being changed, verify the caller is admin
  IF OLD.role IS DISTINCT FROM NEW.role THEN
    IF NOT public.is_admin() THEN
      RAISE EXCEPTION 'Only administrators can modify user roles';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_profile_role_protect
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.protect_role_update();


-- =========================================================
-- 3. AUTO-UPDATE updated_at TIMESTAMP
-- =========================================================
-- Generic trigger function applied to all tables that have
-- an updated_at column. Ensures timestamps are always
-- accurate regardless of whether the frontend sets them.
-- =========================================================

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- Apply to all tables with updated_at
CREATE TRIGGER set_updated_at_profiles
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_updated_at_clients
  BEFORE UPDATE ON public.clients
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_updated_at_projects
  BEFORE UPDATE ON public.projects
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_updated_at_project_phases
  BEFORE UPDATE ON public.project_phases
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_updated_at_project_updates
  BEFORE UPDATE ON public.project_updates
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_updated_at_payments
  BEFORE UPDATE ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 4. AUDIT LOG TRIGGER
-- =========================================================
-- Automatically logs INSERT, UPDATE, DELETE operations
-- with full old/new JSONB snapshots and the acting user.
--
-- SECURITY DEFINER is required because:
--   - audit_logs has no INSERT policy (only triggers write)
--   - The trigger must bypass RLS to write audit records
--
-- Applied to: projects, project_phases, project_updates,
--             payments, comments
-- =========================================================

CREATE OR REPLACE FUNCTION public.audit_log_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _project_id UUID;
  _old        JSONB;
  _new        JSONB;
BEGIN
  -- Determine project_id based on source table
  IF TG_TABLE_NAME = 'projects' THEN
    _project_id := COALESCE(NEW.id, OLD.id);
  ELSIF TG_TABLE_NAME IN ('project_phases', 'project_updates', 'payments', 'comments') THEN
    _project_id := COALESCE(NEW.project_id, OLD.project_id);
  END IF;

  -- Capture old/new row data as JSONB
  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    _old := to_jsonb(OLD);
  END IF;

  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    _new := to_jsonb(NEW);
  END IF;

  -- Write audit record (bypasses RLS via SECURITY DEFINER)
  INSERT INTO public.audit_logs (
    user_id, project_id, action, entity_type, entity_id, old_values, new_values
  )
  VALUES (
    auth.uid(),
    _project_id,
    TG_OP,
    TG_TABLE_NAME,
    COALESCE(NEW.id, OLD.id),
    _old,
    _new
  );

  RETURN NULL; -- AFTER trigger: return value is ignored
END;
$$;

-- Attach audit trigger to all audited tables
CREATE TRIGGER audit_projects
  AFTER INSERT OR UPDATE OR DELETE ON public.projects
  FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();

CREATE TRIGGER audit_project_phases
  AFTER INSERT OR UPDATE OR DELETE ON public.project_phases
  FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();

CREATE TRIGGER audit_project_updates
  AFTER INSERT OR UPDATE OR DELETE ON public.project_updates
  FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();

CREATE TRIGGER audit_payments
  AFTER INSERT OR UPDATE OR DELETE ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();

CREATE TRIGGER audit_comments
  AFTER INSERT OR UPDATE OR DELETE ON public.comments
  FOR EACH ROW EXECUTE FUNCTION public.audit_log_trigger();
