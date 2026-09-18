-- ============================================================
-- 06_seed_data.sql
-- Demo data for testing the portal architecture
-- ============================================================
-- PREREQUISITES:
--   1. Run migrations 00-05 first
--   2. Create both users in Supabase Auth Dashboard
--   3. Replace the placeholder UUIDs below with actual values
--
-- Run this script from the Supabase SQL Editor (which uses
-- the postgres/service_role, bypassing RLS).
-- ============================================================

DO $$
DECLARE
  -- ========================================================
  -- ⚠️  REPLACE THESE WITH ACTUAL UUIDs FROM SUPABASE AUTH
  -- ========================================================
  -- After creating users in Dashboard → Authentication → Users,
  -- copy each user's UUID and paste it here.
  -- ========================================================
  v_admin_uid   UUID := '00000000-0000-0000-0000-000000000001';  -- ← Replace with admin UUID
  v_client_uid  UUID := '00000000-0000-0000-0000-000000000002';  -- ← Replace with client UUID

  -- Auto-generated IDs for seed data
  v_client_id   UUID := gen_random_uuid();
  v_project_id  UUID := gen_random_uuid();
  v_phase_1     UUID := gen_random_uuid();
  v_phase_2     UUID := gen_random_uuid();
  v_phase_3     UUID := gen_random_uuid();
  v_phase_4     UUID := gen_random_uuid();
  v_phase_5     UUID := gen_random_uuid();

BEGIN
  -- =======================================================
  -- STEP 1: Set admin role
  -- =======================================================
  -- The handle_new_user trigger already created profiles
  -- with role = 'client'. Promote the admin account.
  -- =======================================================

  UPDATE public.profiles
  SET role = 'admin', full_name = 'Portal Admin'
  WHERE id = v_admin_uid;

  UPDATE public.profiles
  SET full_name = 'Carlos Méndez'
  WHERE id = v_client_uid;

  -- =======================================================
  -- STEP 2: Create client organization
  -- =======================================================

  INSERT INTO public.clients (id, name, contact_name, contact_email, accent_color)
  VALUES (
    v_client_id,
    'ABC Construction',
    'Carlos Méndez',
    'carlos@abcconstruction.com',
    '#F59E0B'  -- Amber accent
  );

  -- =======================================================
  -- STEP 3: Link client user to organization
  -- =======================================================

  INSERT INTO public.client_users (client_id, user_id)
  VALUES (v_client_id, v_client_uid);

  -- =======================================================
  -- STEP 4: Create project
  -- =======================================================

  INSERT INTO public.projects (
    id, client_id, name, slug, description,
    status, progress_percentage, current_phase_id,
    start_date, estimated_end_date
  )
  VALUES (
    v_project_id,
    v_client_id,
    'Local File Server Implementation',
    'local-file-server',
    'Implementation of a local file server with user management, permissions, and automated backup system for ABC Construction offices.',
    'active',
    60,
    NULL,  -- Will be updated after phases are created
    '2026-08-01',
    '2026-11-15'
  );

  -- =======================================================
  -- STEP 5: Create project phases
  -- =======================================================

  -- Phase 1: Requirements — COMPLETED
  INSERT INTO public.project_phases (id, project_id, name, description, status, position, started_at, completed_at)
  VALUES (
    v_phase_1, v_project_id,
    'Requirements Gathering',
    'Initial meetings, stakeholder interviews, and documentation of technical and business requirements.',
    'completed', 1,
    '2026-08-01 09:00:00+00',
    '2026-08-15 17:00:00+00'
  );

  -- Phase 2: Solution Design — COMPLETED
  INSERT INTO public.project_phases (id, project_id, name, description, status, position, started_at, completed_at)
  VALUES (
    v_phase_2, v_project_id,
    'Solution Design',
    'Architecture design, hardware selection, network topology, and backup strategy planning.',
    'completed', 2,
    '2026-08-16 09:00:00+00',
    '2026-08-30 17:00:00+00'
  );

  -- Phase 3: Implementation — ACTIVE
  INSERT INTO public.project_phases (id, project_id, name, description, status, position, started_at)
  VALUES (
    v_phase_3, v_project_id,
    'Implementation',
    'Server setup, OS installation, storage configuration, user accounts, and permission structure.',
    'active', 3,
    '2026-09-01 09:00:00+00'
  );

  -- Phase 4: Testing — PENDING
  INSERT INTO public.project_phases (id, project_id, name, description, status, position)
  VALUES (
    v_phase_4, v_project_id,
    'Testing',
    'Performance testing, backup verification, failover testing, and user acceptance testing.',
    'pending', 4
  );

  -- Phase 5: Delivery — PENDING
  INSERT INTO public.project_phases (id, project_id, name, description, status, position)
  VALUES (
    v_phase_5, v_project_id,
    'Delivery',
    'Final documentation, knowledge transfer, training sessions, and project handoff.',
    'pending', 5
  );

  -- Set current_phase_id to the active phase
  UPDATE public.projects
  SET current_phase_id = v_phase_3
  WHERE id = v_project_id;

  -- =======================================================
  -- STEP 6: Create payments
  -- =======================================================

  INSERT INTO public.payments (project_id, description, amount, status, due_date, paid_at)
  VALUES (
    v_project_id,
    'Initial payment — project kickoff',
    600000.00,
    'paid',
    '2026-08-01',
    '2026-08-01 10:30:00+00'
  );

  INSERT INTO public.payments (project_id, description, amount, status, due_date)
  VALUES (
    v_project_id,
    'Final payment — upon delivery',
    600000.00,
    'pending',
    '2026-11-15'
  );

  -- =======================================================
  -- STEP 7: Create project updates (timeline)
  -- =======================================================

  INSERT INTO public.project_updates (project_id, created_by, title, message, created_at)
  VALUES (
    v_project_id,
    v_admin_uid,
    'Server Configuration Complete',
    'Initial server configuration has been completed. The operating system is installed, storage arrays are configured with RAID 5, and the base network settings are in place. Moving on to user management setup.',
    '2026-09-10 14:30:00+00'
  );

  INSERT INTO public.project_updates (project_id, created_by, title, message, created_at)
  VALUES (
    v_project_id,
    v_admin_uid,
    'User Permissions In Progress',
    'Currently configuring user accounts, group policies, and folder permission structures. Automated backup system configuration will begin next week.',
    '2026-09-17 11:00:00+00'
  );

  -- =======================================================
  -- STEP 8: Create sample comment
  -- =======================================================

  INSERT INTO public.comments (project_id, user_id, message, created_at)
  VALUES (
    v_project_id,
    v_admin_uid,
    'Let me know if you have any questions about the current progress. The implementation phase is going well and we are on schedule.',
    '2026-09-17 11:15:00+00'
  );

  RAISE NOTICE '✅ Seed data created successfully!';
  RAISE NOTICE '   Client: ABC Construction (ID: %)', v_client_id;
  RAISE NOTICE '   Project: Local File Server Implementation (ID: %)', v_project_id;
  RAISE NOTICE '   Phases: 5 (2 completed, 1 active, 2 pending)';
  RAISE NOTICE '   Payments: 2 (1 paid, 1 pending)';
  RAISE NOTICE '   Updates: 2';
  RAISE NOTICE '   Comments: 1';

END $$;
