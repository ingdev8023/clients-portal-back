-- ============================================================
-- 07_security_tests.sql
-- RLS verification tests — run in Supabase SQL Editor
-- ============================================================
-- Each test uses a transaction to impersonate a user via
-- SET LOCAL, then ROLLBACK to avoid side effects.
--
-- HOW TO RUN:
--   1. Replace the placeholder UUIDs with actual values
--   2. Run each test block individually in the SQL Editor
--   3. Verify the result matches the expected outcome
--
-- The SQL Editor runs as postgres (service_role) by default.
-- SET LOCAL ROLE authenticated + request.jwt.claims simulates
-- a real SDK request with RLS enforced.
-- ============================================================

-- ⚠️ Replace these with actual UUIDs before running tests
-- You can find them in: Authentication → Users → click user → copy UUID
--
-- Example:
--   v_admin_uid  = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
--   v_client_uid = 'f9e8d7c6-b5a4-3210-fedc-ba0987654321'


-- =========================================================
-- =========================================================
--                    CLIENT CAN DO
-- =========================================================
-- =========================================================


-- ---------------------------------------------------------
-- TEST 1: Client can read their own client organization
-- Expected: Returns 1 row (ABC Construction)
-- ---------------------------------------------------------
BEGIN;
  SET LOCAL ROLE authenticated;
  SET LOCAL "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-000000000002", "role": "authenticated"}';

  SELECT id, name, contact_name FROM public.clients;
  -- Expected: 1 row → ABC Construction
ROLLBACK;


-- ---------------------------------------------------------
-- TEST 2: Client can read their own projects
-- Expected: Returns 1 row (Local File Server Implementation)
-- ---------------------------------------------------------
BEGIN;
  SET LOCAL ROLE authenticated;
  SET LOCAL "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-000000000002", "role": "authenticated"}';

  SELECT id, name, status, progress_percentage FROM public.projects;
  -- Expected: 1 row → Local File Server Implementation, active, 60
ROLLBACK;


-- ---------------------------------------------------------
-- TEST 3: Client can read project phases
-- Expected: Returns 5 rows ordered by position
-- ---------------------------------------------------------
BEGIN;
  SET LOCAL ROLE authenticated;
  SET LOCAL "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-000000000002", "role": "authenticated"}';

  SELECT name, status, position
  FROM public.project_phases
  ORDER BY position;
  -- Expected: 5 rows
  --   1. Requirements Gathering — completed
  --   2. Solution Design — completed
  --   3. Implementation — active
  --   4. Testing — pending
  --   5. Delivery — pending
ROLLBACK;


-- ---------------------------------------------------------
-- TEST 4: Client can read project updates
-- Expected: Returns 2 rows
-- ---------------------------------------------------------
BEGIN;
  SET LOCAL ROLE authenticated;
  SET LOCAL "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-000000000002", "role": "authenticated"}';

  SELECT title, message, created_at
  FROM public.project_updates
  ORDER BY created_at;
  -- Expected: 2 rows
ROLLBACK;


-- ---------------------------------------------------------
-- TEST 5: Client can read payments
-- Expected: Returns 2 rows (1 paid, 1 pending)
-- ---------------------------------------------------------
BEGIN;
  SET LOCAL ROLE authenticated;
  SET LOCAL "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-000000000002", "role": "authenticated"}';

  SELECT description, amount, status
  FROM public.payments;
  -- Expected: 2 rows
  --   Initial payment — paid — $600,000
  --   Final payment — pending — $600,000
ROLLBACK;


-- ---------------------------------------------------------
-- TEST 6: Client can read comments (non-deleted)
-- Expected: Returns 1 row
-- ---------------------------------------------------------
BEGIN;
  SET LOCAL ROLE authenticated;
  SET LOCAL "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-000000000002", "role": "authenticated"}';

  SELECT message, created_at FROM public.comments;
  -- Expected: 1 row → admin's comment
ROLLBACK;


-- ---------------------------------------------------------
-- TEST 7: Client can INSERT a comment on their project
-- Expected: INSERT succeeds
-- ---------------------------------------------------------
BEGIN;
  SET LOCAL ROLE authenticated;
  SET LOCAL "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-000000000002", "role": "authenticated"}';

  -- First get the project_id (replace if needed)
  INSERT INTO public.comments (project_id, user_id, message)
  SELECT p.id, '00000000-0000-0000-0000-000000000002'::UUID, 'Thank you for the update! Everything looks great.'
  FROM public.projects p
  LIMIT 1;
  -- Expected: 1 row inserted
ROLLBACK;


-- =========================================================
-- =========================================================
--                   CLIENT CANNOT DO
-- =========================================================
-- =========================================================


-- ---------------------------------------------------------
-- TEST 8: Client CANNOT change project progress
-- Expected: 0 rows affected
-- ---------------------------------------------------------
BEGIN;
  SET LOCAL ROLE authenticated;
  SET LOCAL "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-000000000002", "role": "authenticated"}';

  UPDATE public.projects SET progress_percentage = 100;
  -- Expected: UPDATE 0
ROLLBACK;


-- ---------------------------------------------------------
-- TEST 9: Client CANNOT change project status
-- Expected: 0 rows affected
-- ---------------------------------------------------------
BEGIN;
  SET LOCAL ROLE authenticated;
  SET LOCAL "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-000000000002", "role": "authenticated"}';

  UPDATE public.projects SET status = 'completed';
  -- Expected: UPDATE 0
ROLLBACK;


-- ---------------------------------------------------------
-- TEST 10: Client CANNOT mark a phase as completed
-- Expected: 0 rows affected
-- ---------------------------------------------------------
BEGIN;
  SET LOCAL ROLE authenticated;
  SET LOCAL "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-000000000002", "role": "authenticated"}';

  UPDATE public.project_phases SET status = 'completed';
  -- Expected: UPDATE 0
ROLLBACK;


-- ---------------------------------------------------------
-- TEST 11: Client CANNOT modify payment status
-- Expected: 0 rows affected
-- ---------------------------------------------------------
BEGIN;
  SET LOCAL ROLE authenticated;
  SET LOCAL "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-000000000002", "role": "authenticated"}';

  UPDATE public.payments SET status = 'paid';
  -- Expected: UPDATE 0
ROLLBACK;


-- ---------------------------------------------------------
-- TEST 12: Client CANNOT create project updates
-- Expected: 0 rows inserted (policy violation)
-- ---------------------------------------------------------
BEGIN;
  SET LOCAL ROLE authenticated;
  SET LOCAL "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-000000000002", "role": "authenticated"}';

  INSERT INTO public.project_updates (project_id, created_by, message)
  SELECT p.id, '00000000-0000-0000-0000-000000000002'::UUID, 'Unauthorized update attempt'
  FROM public.projects p
  LIMIT 1;
  -- Expected: ERROR — new row violates RLS policy
ROLLBACK;


-- ---------------------------------------------------------
-- TEST 13: Client CANNOT delete payments
-- Expected: 0 rows affected
-- ---------------------------------------------------------
BEGIN;
  SET LOCAL ROLE authenticated;
  SET LOCAL "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-000000000002", "role": "authenticated"}';

  DELETE FROM public.payments;
  -- Expected: DELETE 0
ROLLBACK;


-- ---------------------------------------------------------
-- TEST 14: Client CANNOT read audit_logs
-- Expected: 0 rows returned
-- ---------------------------------------------------------
BEGIN;
  SET LOCAL ROLE authenticated;
  SET LOCAL "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-000000000002", "role": "authenticated"}';

  SELECT * FROM public.audit_logs;
  -- Expected: 0 rows
ROLLBACK;


-- ---------------------------------------------------------
-- TEST 15: Client CANNOT modify client information
-- Expected: 0 rows affected
-- ---------------------------------------------------------
BEGIN;
  SET LOCAL ROLE authenticated;
  SET LOCAL "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-000000000002", "role": "authenticated"}';

  UPDATE public.clients SET name = 'HACKED NAME';
  -- Expected: UPDATE 0
ROLLBACK;


-- ---------------------------------------------------------
-- TEST 16: Client CANNOT create projects
-- Expected: ERROR (policy violation)
-- ---------------------------------------------------------
BEGIN;
  SET LOCAL ROLE authenticated;
  SET LOCAL "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-000000000002", "role": "authenticated"}';

  INSERT INTO public.projects (client_id, name, slug, description)
  SELECT c.id, 'Fake Project', 'fake-project', 'Unauthorized'
  FROM public.clients c
  LIMIT 1;
  -- Expected: ERROR — new row violates RLS policy
ROLLBACK;


-- ---------------------------------------------------------
-- TEST 17: Client CANNOT delete projects
-- Expected: 0 rows affected
-- ---------------------------------------------------------
BEGIN;
  SET LOCAL ROLE authenticated;
  SET LOCAL "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-000000000002", "role": "authenticated"}';

  DELETE FROM public.projects;
  -- Expected: DELETE 0
ROLLBACK;


-- =========================================================
-- =========================================================
--                    ADMIN CAN DO
-- =========================================================
-- =========================================================


-- ---------------------------------------------------------
-- TEST 18: Admin can update project progress
-- Expected: 1 row updated
-- ---------------------------------------------------------
BEGIN;
  SET LOCAL ROLE authenticated;
  SET LOCAL "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-000000000001", "role": "authenticated"}';

  UPDATE public.projects SET progress_percentage = 75;
  -- Expected: UPDATE 1
ROLLBACK;


-- ---------------------------------------------------------
-- TEST 19: Admin can update phase status
-- Expected: rows updated
-- ---------------------------------------------------------
BEGIN;
  SET LOCAL ROLE authenticated;
  SET LOCAL "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-000000000001", "role": "authenticated"}';

  -- Complete the current active phase
  UPDATE public.project_phases
  SET status = 'completed', completed_at = now()
  WHERE status = 'active';
  -- Expected: UPDATE 1
ROLLBACK;


-- ---------------------------------------------------------
-- TEST 20: Admin can create project updates
-- Expected: 1 row inserted
-- ---------------------------------------------------------
BEGIN;
  SET LOCAL ROLE authenticated;
  SET LOCAL "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-000000000001", "role": "authenticated"}';

  INSERT INTO public.project_updates (project_id, created_by, title, message)
  SELECT p.id, '00000000-0000-0000-0000-000000000001'::UUID, 'Test Update', 'Admin test update'
  FROM public.projects p
  LIMIT 1;
  -- Expected: INSERT 0 1
ROLLBACK;


-- ---------------------------------------------------------
-- TEST 21: Admin can update payment status
-- Expected: rows updated
-- ---------------------------------------------------------
BEGIN;
  SET LOCAL ROLE authenticated;
  SET LOCAL "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-000000000001", "role": "authenticated"}';

  UPDATE public.payments SET status = 'paid', paid_at = now()
  WHERE status = 'pending';
  -- Expected: UPDATE 1
ROLLBACK;


-- ---------------------------------------------------------
-- TEST 22: Admin can read audit_logs
-- Expected: multiple rows (from seed data operations)
-- ---------------------------------------------------------
BEGIN;
  SET LOCAL ROLE authenticated;
  SET LOCAL "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-000000000001", "role": "authenticated"}';

  SELECT id, action, entity_type, entity_id, created_at
  FROM public.audit_logs
  ORDER BY created_at DESC
  LIMIT 10;
  -- Expected: multiple audit entries
ROLLBACK;


-- ---------------------------------------------------------
-- TEST 23: Admin can create a new client
-- Expected: 1 row inserted
-- ---------------------------------------------------------
BEGIN;
  SET LOCAL ROLE authenticated;
  SET LOCAL "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-000000000001", "role": "authenticated"}';

  INSERT INTO public.clients (name, contact_name, contact_email)
  VALUES ('Test Client', 'Test Contact', 'test@example.com');
  -- Expected: INSERT 0 1
ROLLBACK;


-- =========================================================
-- =========================================================
--          CROSS-TENANT ISOLATION (CRITICAL)
-- =========================================================
-- =========================================================
-- This test creates a second client + project, then verifies
-- the original client user CANNOT access the new data.
-- This proves RLS tenant isolation works correctly.
-- =========================================================


-- ---------------------------------------------------------
-- TEST 24-28: Cross-tenant isolation
-- ---------------------------------------------------------
-- First, create test data as admin (in a committed transaction)
-- Then test isolation as the original client user
-- ---------------------------------------------------------

DO $$
DECLARE
  v_client2_id  UUID := gen_random_uuid();
  v_project2_id UUID := gen_random_uuid();
  v_phase2_id   UUID := gen_random_uuid();
BEGIN
  -- Create second client (as postgres/service_role, bypasses RLS)
  INSERT INTO public.clients (id, name, contact_name, contact_email)
  VALUES (v_client2_id, 'XYZ Industries', 'Test Person', 'test@xyz.com');

  INSERT INTO public.projects (id, client_id, name, slug, status, progress_percentage)
  VALUES (v_project2_id, v_client2_id, 'Secret Project', 'secret-project', 'active', 30);

  INSERT INTO public.project_phases (id, project_id, name, status, position)
  VALUES (v_phase2_id, v_project2_id, 'Secret Phase', 'active', 1);

  INSERT INTO public.payments (project_id, description, amount, status)
  VALUES (v_project2_id, 'Secret Payment', 999999.99, 'pending');

  INSERT INTO public.project_updates (project_id, created_by, message)
  VALUES (v_project2_id, '00000000-0000-0000-0000-000000000001', 'Secret update');

  RAISE NOTICE '✅ TEST 24: Second client created (ID: %)', v_client2_id;
  RAISE NOTICE '   Second project created (ID: %)', v_project2_id;
  RAISE NOTICE '';
  RAISE NOTICE 'Now run tests 25-28 below to verify isolation.';
  RAISE NOTICE 'After testing, run the cleanup block at the bottom.';
END $$;


-- TEST 25: Client can only see their own client
-- Expected: Returns ONLY 'ABC Construction' — NOT 'XYZ Industries'
BEGIN;
  SET LOCAL ROLE authenticated;
  SET LOCAL "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-000000000002", "role": "authenticated"}';

  SELECT name FROM public.clients;
  -- Expected: 1 row → ABC Construction
  -- Must NOT include → XYZ Industries
ROLLBACK;


-- TEST 26: Client can only see their own projects
-- Expected: Returns ONLY 'Local File Server Implementation'
BEGIN;
  SET LOCAL ROLE authenticated;
  SET LOCAL "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-000000000002", "role": "authenticated"}';

  SELECT name FROM public.projects;
  -- Expected: 1 row → Local File Server Implementation
  -- Must NOT include → Secret Project
ROLLBACK;


-- TEST 27: Client cannot see phases/updates/payments of other projects
-- Expected: Returns ONLY data from their own project
BEGIN;
  SET LOCAL ROLE authenticated;
  SET LOCAL "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-000000000002", "role": "authenticated"}';

  -- Should return 5 phases (all from their project, none from secret project)
  SELECT name FROM public.project_phases ORDER BY position;

  -- Should return 2 payments (none from secret project)
  SELECT description, amount FROM public.payments;

  -- Should return 2 updates (none from secret project)
  SELECT message FROM public.project_updates;
  -- Expected: No 'Secret Phase', 'Secret Payment', or 'Secret update' in results
ROLLBACK;


-- TEST 28: Client cannot insert a comment on another client's project
-- Expected: ERROR (policy violation)
BEGIN;
  SET LOCAL ROLE authenticated;
  SET LOCAL "request.jwt.claims" = '{"sub": "00000000-0000-0000-0000-000000000002", "role": "authenticated"}';

  -- Try to comment on the secret project by directly using its ID
  -- (simulates a malicious user who discovered the project UUID)
  INSERT INTO public.comments (project_id, user_id, message)
  SELECT p.id, '00000000-0000-0000-0000-000000000002'::UUID, 'I should not be able to do this'
  FROM public.projects p
  WHERE p.name = 'Secret Project';
  -- Expected: INSERT 0 0 (no matching rows because SELECT is also filtered by RLS)
  --   OR ERROR if project_id is hardcoded
ROLLBACK;


-- =========================================================
-- CLEANUP: Remove test data for cross-tenant tests
-- =========================================================
-- Run this after completing tests 24-28 to remove the
-- second client and all cascading data.
-- =========================================================

-- DELETE FROM public.clients WHERE name = 'XYZ Industries';
-- This cascades to: projects → phases, updates, payments, comments
