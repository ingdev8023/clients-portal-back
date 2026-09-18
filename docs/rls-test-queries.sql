-- Manual RLS checks for the Client Project Portal.
--
-- Replace these UUIDs with real auth.users IDs after running supabase/seed.sql.
-- Run this from Supabase SQL Editor. The transaction rolls back all test writes.

begin;

-- ---------------------------------------------------------------------------
-- CLIENT positive tests
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
set local request.jwt.claim.role = 'authenticated';
select auth.uid() as acting_user;

-- CLIENT can read their client mapping and client.
select * from public.client_users;
select * from public.clients;

-- CLIENT can read their project, phases, updates, payments, and comments.
select id, name, status, progress_percentage
from public.projects
order by created_at;

select name, status, position
from public.project_phases
where project_id = '22222222-2222-2222-2222-222222222222'
order by position;

select title, message, created_at
from public.project_updates
where project_id = '22222222-2222-2222-2222-222222222222'
order by created_at;

select description, amount, status
from public.payments
where project_id = '22222222-2222-2222-2222-222222222222'
order by created_at;

select user_id, message
from public.comments
where project_id = '22222222-2222-2222-2222-222222222222'
order by created_at;

update public.profiles
set full_name = 'ABC Construction Test Name'
where id = '00000000-0000-0000-0000-000000000002'
returning id, full_name, role;

insert into public.comments (project_id, user_id, message)
values (
  '22222222-2222-2222-2222-222222222222',
  '00000000-0000-0000-0000-000000000002',
  'Client RLS insert test comment.'
)
returning id, project_id, user_id, message;

-- CLIENT may correct a fresh comment, then soft-delete it within 15 minutes.
update public.comments
set message = 'Client RLS edited comment.'
where project_id = '22222222-2222-2222-2222-222222222222'
  and user_id = '00000000-0000-0000-0000-000000000002'
  and message = 'Client RLS insert test comment.'
returning id, message;

update public.comments
set deleted_at = now()
where project_id = '22222222-2222-2222-2222-222222222222'
  and user_id = '00000000-0000-0000-0000-000000000002'
  and message = 'Client RLS edited comment.';

-- ---------------------------------------------------------------------------
-- CLIENT negative tests
-- These must affect zero rows or return an empty result because RLS blocks them.
-- ---------------------------------------------------------------------------
update public.projects
set progress_percentage = 90
where id = '22222222-2222-2222-2222-222222222222'
returning id;

update public.projects
set status = 'completed'
where id = '22222222-2222-2222-2222-222222222222'
returning id;

update public.project_phases
set status = 'completed'
where id = '33333333-3333-3333-3333-333333333333'
returning id;

update public.payments
set status = 'paid'
where id = '55555555-5555-5555-5555-555555555552'
returning id;

update public.clients
set name = 'Tampered Client Name'
where id = '11111111-1111-1111-1111-111111111111'
returning id;

delete from public.payments
where id = '55555555-5555-5555-5555-555555555552'
returning id;

delete from public.projects
where id = '22222222-2222-2222-2222-222222222222'
returning id;

select *
from public.audit_logs;

-- A client cannot insert a comment as another user.
-- Run this one separately if you want to see the expected RLS error:
--
-- insert into public.comments (project_id, user_id, message)
-- values (
--   '22222222-2222-2222-2222-222222222222',
--   '00000000-0000-0000-0000-000000000001',
--   'This should fail.'
-- );

-- INSERT into projects or project_updates as CLIENT must raise an RLS error.
-- Run each separately so the expected error does not abort this transaction.
-- update public.profiles set role = 'admin'
-- where id = '00000000-0000-0000-0000-000000000002'; -- column permission error
-- insert into public.projects (client_id, name, slug)
-- values ('11111111-1111-1111-1111-111111111111', 'Unauthorized', 'unauthorized');
-- insert into public.project_updates (project_id, created_by, message)
-- values ('22222222-2222-2222-2222-222222222222',
--         '00000000-0000-0000-0000-000000000002', 'Unauthorized');

-- ---------------------------------------------------------------------------
-- Cross-client isolation negative test
-- Creates a second client/project as the SQL editor owner, then switches back
-- to the original client. The original client must not see the second project.
-- ---------------------------------------------------------------------------
reset role;
reset request.jwt.claim.sub;
reset request.jwt.claim.role;

insert into public.clients (id, name, contact_name, contact_email)
values (
  '77777777-7777-7777-7777-777777777771',
  'XYZ Manufacturing',
  'XYZ Manufacturing',
  'xyz@example.com'
)
on conflict (id) do nothing;

insert into public.projects (id, client_id, name, slug, description, status, progress_percentage)
values (
  '88888888-8888-8888-8888-888888888881',
  '77777777-7777-7777-7777-777777777771',
  'Second Client Private Project',
  'second-client-private-project',
  'Project used only to verify tenant isolation.',
  'active',
  25
)
on conflict (id) do nothing;

insert into public.project_phases (id, project_id, name, status, position)
values ('99999999-9999-9999-9999-999999999991',
        '88888888-8888-8888-8888-888888888881', 'Private phase', 'pending', 1)
on conflict (id) do nothing;

insert into public.project_updates (id, project_id, created_by, message)
values ('99999999-9999-9999-9999-999999999992',
        '88888888-8888-8888-8888-888888888881',
        '00000000-0000-0000-0000-000000000001', 'Private update')
on conflict (id) do nothing;

insert into public.payments (id, project_id, description, amount)
values ('99999999-9999-9999-9999-999999999993',
        '88888888-8888-8888-8888-888888888881', 'Private payment', 100)
on conflict (id) do nothing;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
set local request.jwt.claim.role = 'authenticated';

select *
from public.projects
where id = '88888888-8888-8888-8888-888888888881';

select * from public.clients where id = '77777777-7777-7777-7777-777777777771';
select * from public.project_phases where project_id = '88888888-8888-8888-8888-888888888881';
select * from public.project_updates where project_id = '88888888-8888-8888-8888-888888888881';
select * from public.payments where project_id = '88888888-8888-8888-8888-888888888881';

-- Run this one separately if you want to see the expected RLS error:
--
-- insert into public.comments (project_id, user_id, message)
-- values (
--   '88888888-8888-8888-8888-888888888881',
--   '00000000-0000-0000-0000-000000000002',
--   'This cross-client comment should fail.'
-- );

-- ---------------------------------------------------------------------------
-- ADMIN positive tests
-- ---------------------------------------------------------------------------
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
set local request.jwt.claim.role = 'authenticated';
select auth.uid() as acting_user;

select id, name from public.clients order by created_at;
select id, action, entity_type, created_at from public.audit_logs order by created_at desc limit 20;

update public.projects
set progress_percentage = 70
where id = '22222222-2222-2222-2222-222222222222'
returning id, progress_percentage;

update public.project_phases
set status = 'completed'
where id = '33333333-3333-3333-3333-333333333333'
returning id, status, completed_at;

update public.payments
set status = 'paid'
where id = '55555555-5555-5555-5555-555555555552'
returning id, status, paid_at;

insert into public.project_updates (project_id, created_by, message)
values ('22222222-2222-2222-2222-222222222222',
        '00000000-0000-0000-0000-000000000001', 'Admin publish test')
returning id, message;

insert into public.comments (project_id, user_id, message)
values ('22222222-2222-2222-2222-222222222222',
        '00000000-0000-0000-0000-000000000001', 'Admin reply test')
returning id, message;

insert into public.clients (name, contact_name, contact_email)
values ('Admin Test Client', 'Admin Test Client', 'admin-test@example.com')
returning id, name;

-- Completed projects stay at 100%, even if a later update requests 70%.
update public.projects
set status = 'completed'
where id = '22222222-2222-2222-2222-222222222222';

update public.projects
set progress_percentage = 70
where id = '22222222-2222-2222-2222-222222222222'
returning id, status, progress_percentage, completed_at;

update public.projects
set status = 'active', progress_percentage = 70
where id = '22222222-2222-2222-2222-222222222222'
returning id, status, progress_percentage, completed_at;

delete from public.project_phases
where id = '99999999-9999-9999-9999-999999999991'
returning id;

delete from public.projects
where id = '88888888-8888-8888-8888-888888888881'
returning id;

select action, entity_type, entity_id, project_id, old_values
from public.audit_logs
where project_id = '88888888-8888-8888-8888-888888888881'
  and action in ('project_deleted', 'phase_deleted', 'payment_deleted')
order by created_at;

rollback;
