-- Manual RLS checks for the Client Project Portal.
--
-- The fixture IDs are discovered at runtime so this suite works with local seed
-- UUIDs and real hosted Auth UUIDs. The transaction rolls back all test writes.

begin;

-- Capture one seeded client project and one administrator before impersonating
-- browser roles. Custom settings remain transaction-local and avoid hardcoded
-- Auth UUIDs in the assertions below.
select set_config('test.client_user_id', coalesce((
  select cu.user_id::text
  from public.client_users cu
  join public.profiles profile on profile.id = cu.user_id
  where profile.role = 'client'
  order by cu.created_at
  limit 1
), ''), true);

select set_config('test.client_id', coalesce((
  select cu.client_id::text
  from public.client_users cu
  where cu.user_id = current_setting('test.client_user_id')::uuid
  order by cu.created_at
  limit 1
), ''), true);

select set_config('test.project_id', coalesce((
  select project.id::text
  from public.projects project
  where project.client_id = current_setting('test.client_id')::uuid
  order by project.created_at
  limit 1
), ''), true);

select set_config('test.phase_id', coalesce((
  select phase.id::text
  from public.project_phases phase
  where phase.project_id = current_setting('test.project_id')::uuid
  order by phase.position
  limit 1
), ''), true);

select set_config('test.payment_id', coalesce((
  select payment.id::text
  from public.payments payment
  where payment.project_id = current_setting('test.project_id')::uuid
  order by payment.created_at
  limit 1
), ''), true);

select set_config('test.admin_user_id', coalesce((
  select profile.id::text
  from public.profiles profile
  where profile.role = 'admin'
  order by profile.created_at
  limit 1
), ''), true);

do $fixtures$
begin
  if current_setting('test.client_user_id') = ''
    or current_setting('test.client_id') = ''
    or current_setting('test.project_id') = ''
    or current_setting('test.phase_id') = ''
    or current_setting('test.payment_id') = ''
    or current_setting('test.admin_user_id') = '' then
    raise exception 'RLS test fixtures are incomplete; seed an admin and a client project first.';
  end if;
end
$fixtures$;

-- ---------------------------------------------------------------------------
-- CLIENT positive tests
-- ---------------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claim.sub', current_setting('test.client_user_id'), true);
select set_config('request.jwt.claim.role', 'authenticated', true);
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
where project_id = current_setting('test.project_id')::uuid
order by position;

select title, message, created_at
from public.project_updates
where project_id = current_setting('test.project_id')::uuid
order by created_at;

select description, amount, status
from public.payments
where project_id = current_setting('test.project_id')::uuid
order by created_at;

select user_id, message
from public.comments
where project_id = current_setting('test.project_id')::uuid
order by created_at;

update public.profiles
set full_name = 'ABC Construction Test Name'
where id = current_setting('test.client_user_id')::uuid
returning id, full_name, role;

insert into public.comments (project_id, user_id, message)
values (
  current_setting('test.project_id')::uuid,
  current_setting('test.client_user_id')::uuid,
  'Client RLS insert test comment.'
)
returning id, project_id, user_id, message;

-- CLIENT may correct a fresh comment, then soft-delete it within 15 minutes.
update public.comments
set message = 'Client RLS edited comment.'
where project_id = current_setting('test.project_id')::uuid
  and user_id = current_setting('test.client_user_id')::uuid
  and message = 'Client RLS insert test comment.'
returning id, message;

update public.comments
set deleted_at = now()
where project_id = current_setting('test.project_id')::uuid
  and user_id = current_setting('test.client_user_id')::uuid
  and message = 'Client RLS edited comment.';

-- The author can still read their deleted comment, but it cannot be edited again.
select id, deleted_at from public.comments
where user_id = current_setting('test.client_user_id')::uuid
  and message = 'Client RLS edited comment.'
  and deleted_at is not null;

update public.comments
set message = 'This must not be saved.'
where user_id = current_setting('test.client_user_id')::uuid
  and message = 'Client RLS edited comment.'
  and deleted_at is not null
returning id;

-- ---------------------------------------------------------------------------
-- CLIENT negative tests
-- These must affect zero rows or return an empty result because RLS blocks them.
-- ---------------------------------------------------------------------------
update public.projects
set progress_percentage = 90
where id = current_setting('test.project_id')::uuid
returning id;

update public.projects
set status = 'completed'
where id = current_setting('test.project_id')::uuid
returning id;

update public.project_phases
set status = 'completed'
where id = current_setting('test.phase_id')::uuid
returning id;

update public.payments
set status = 'paid'
where id = current_setting('test.payment_id')::uuid
returning id;

update public.clients
set name = 'Tampered Client Name'
where id = current_setting('test.client_id')::uuid
returning id;

delete from public.payments
where id = current_setting('test.payment_id')::uuid
returning id;

delete from public.projects
where id = current_setting('test.project_id')::uuid
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
        current_setting('test.admin_user_id')::uuid, 'Private update')
on conflict (id) do nothing;

insert into public.payments (id, project_id, description, amount)
values ('99999999-9999-9999-9999-999999999993',
        '88888888-8888-8888-8888-888888888881', 'Private payment', 100)
on conflict (id) do nothing;

set local role authenticated;
select set_config('request.jwt.claim.sub', current_setting('test.client_user_id'), true);
select set_config('request.jwt.claim.role', 'authenticated', true);

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
select set_config('request.jwt.claim.sub', current_setting('test.admin_user_id'), true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select auth.uid() as acting_user;

select id, name from public.clients order by created_at;
select id, action, entity_type, created_at from public.audit_logs order by created_at desc limit 20;

update public.projects
set progress_percentage = 70
where id = current_setting('test.project_id')::uuid
returning id, progress_percentage;

update public.project_phases
set status = 'completed'
where id = current_setting('test.phase_id')::uuid
returning id, status, completed_at;

update public.payments
set status = 'paid'
where id = current_setting('test.payment_id')::uuid
returning id, status, paid_at;

insert into public.project_updates (project_id, created_by, message)
values (current_setting('test.project_id')::uuid,
        current_setting('test.admin_user_id')::uuid, 'Admin publish test')
returning id, message;

insert into public.comments (project_id, user_id, message)
values (current_setting('test.project_id')::uuid,
        current_setting('test.admin_user_id')::uuid, 'Admin reply test')
returning id, message;

insert into public.clients (name, contact_name, contact_email)
values ('Admin Test Client', 'Admin Test Client', 'admin-test@example.com')
returning id, name;

-- Completed projects stay at 100%, even if a later update requests 70%.
update public.projects
set status = 'completed'
where id = current_setting('test.project_id')::uuid;

update public.projects
set progress_percentage = 70
where id = current_setting('test.project_id')::uuid
returning id, status, progress_percentage, completed_at;

update public.projects
set status = 'active', progress_percentage = 70
where id = current_setting('test.project_id')::uuid
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
