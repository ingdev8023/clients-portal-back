-- ============================================================
-- 03_helper_functions.sql
-- SECURITY DEFINER helper functions used by RLS policies
-- ============================================================
-- These functions centralize authorization logic so that
-- RLS policies stay clean and DRY.
--
-- SECURITY DEFINER: Executes with owner's privileges (postgres),
--   bypassing RLS on the tables they query. This avoids the
--   circular dependency where profiles has RLS that needs
--   is_admin() which needs to read profiles.
--
-- STABLE: Tells PostgreSQL the result is constant within a
--   single SQL statement, enabling query plan caching.
--
-- SET search_path = '': Prevents search-path hijacking attacks.
--   All table references inside must be fully qualified.
-- ============================================================

-- ---------------------------------------------------------
-- is_admin()
-- Returns TRUE if the currently authenticated user has
-- role = 'admin' in the profiles table.
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid()
      AND role = 'admin'
  );
$$;

COMMENT ON FUNCTION public.is_admin IS 'Returns TRUE if current auth user is admin. Used in RLS policies.';

-- ---------------------------------------------------------
-- get_client_ids()
-- Returns all client_ids that the currently authenticated
-- user belongs to (via client_users junction table).
-- Returns empty set for admin users (admin is not in
-- client_users, they use is_admin() instead).
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_client_ids()
RETURNS SETOF UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT client_id
  FROM public.client_users
  WHERE user_id = auth.uid();
$$;

COMMENT ON FUNCTION public.get_client_ids IS 'Returns client_ids for current auth user. Used in RLS for tenant isolation.';
