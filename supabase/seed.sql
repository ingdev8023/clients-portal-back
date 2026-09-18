-- Demo seed for Client Project Portal.
--
-- Before running:
-- 1. Run the migration, then create admin@example.com and client@example.com in Auth.
-- 2. Promote the admin profile in SQL Editor as described in README.md.
-- 3. Replace the placeholder UUIDs below with the real Auth user IDs.
--
-- Do not put real passwords or service_role keys in this file.

begin;

do $$
begin
  if not exists (
    select 1 from public.profiles
    where id = '00000000-0000-0000-0000-000000000001'
      and role = 'admin'::public.app_role
  ) then
    raise exception 'Create the admin user and promote the profile before seeding';
  end if;

  if not exists (
    select 1 from public.profiles
    where id = '00000000-0000-0000-0000-000000000002'
      and role = 'client'::public.app_role
  ) then
    raise exception 'Create the client user after the migration before seeding';
  end if;
end;
$$;

update public.profiles
set full_name = 'Portal Administrator'
where id = '00000000-0000-0000-0000-000000000001';

update public.profiles
set full_name = 'ABC Construction Shared Access'
where id = '00000000-0000-0000-0000-000000000002';

insert into public.clients (id, name, contact_name, contact_email, accent_color)
values (
  '11111111-1111-1111-1111-111111111111',
  'ABC Construction',
  'ABC Construction',
  'client@example.com',
  '#2563EB'
)
on conflict (id) do update
set name = excluded.name,
    contact_name = excluded.contact_name,
    contact_email = excluded.contact_email,
    accent_color = excluded.accent_color,
    updated_at = now();

insert into public.client_users (client_id, user_id)
values (
  '11111111-1111-1111-1111-111111111111',
  '00000000-0000-0000-0000-000000000002'
)
on conflict (client_id, user_id) do nothing;

insert into public.projects (
  id,
  client_id,
  name,
  slug,
  description,
  status,
  progress_percentage,
  start_date,
  estimated_end_date
)
values (
  '22222222-2222-2222-2222-222222222222',
  '11111111-1111-1111-1111-111111111111',
  'Local File Server Implementation',
  'local-file-server',
  'Implementation of a local file server with user permissions and backup configuration.',
  'active'::public.project_status,
  60,
  '2026-09-01',
  '2026-10-15'
)
on conflict (id) do update
set name = excluded.name,
    slug = excluded.slug,
    description = excluded.description,
    status = excluded.status,
    progress_percentage = excluded.progress_percentage,
    start_date = excluded.start_date,
    estimated_end_date = excluded.estimated_end_date,
    updated_at = now();

insert into public.project_phases (id, project_id, name, description, status, position)
values
  (
    '33333333-3333-3333-3333-333333333331',
    '22222222-2222-2222-2222-222222222222',
    'Requirements',
    'Confirm scope, users, storage needs, and access rules.',
    'completed'::public.phase_status,
    1
  ),
  (
    '33333333-3333-3333-3333-333333333332',
    '22222222-2222-2222-2222-222222222222',
    'Solution Design',
    'Define server layout, permissions model, backup plan, and delivery criteria.',
    'completed'::public.phase_status,
    2
  ),
  (
    '33333333-3333-3333-3333-333333333333',
    '22222222-2222-2222-2222-222222222222',
    'Implementation',
    'Configure server, shared folders, users, permissions, and backup jobs.',
    'active'::public.phase_status,
    3
  ),
  (
    '33333333-3333-3333-3333-333333333334',
    '22222222-2222-2222-2222-222222222222',
    'Testing',
    'Validate permissions, restore procedure, network access, and user flows.',
    'pending'::public.phase_status,
    4
  ),
  (
    '33333333-3333-3333-3333-333333333335',
    '22222222-2222-2222-2222-222222222222',
    'Delivery',
    'Final handoff, documentation, and project closure.',
    'pending'::public.phase_status,
    5
  )
on conflict (id) do update
set name = excluded.name,
    description = excluded.description,
    status = excluded.status,
    position = excluded.position,
    updated_at = now();

update public.projects
set current_phase_id = '33333333-3333-3333-3333-333333333333',
    updated_at = now()
where id = '22222222-2222-2222-2222-222222222222';

insert into public.project_updates (id, project_id, created_by, title, message, created_at)
values
  (
    '44444444-4444-4444-4444-444444444441',
    '22222222-2222-2222-2222-222222222222',
    '00000000-0000-0000-0000-000000000001',
    'Initial configuration',
    'Initial server configuration completed.',
    '2026-09-17 09:00:00-05'::timestamptz
  ),
  (
    '44444444-4444-4444-4444-444444444442',
    '22222222-2222-2222-2222-222222222222',
    '00000000-0000-0000-0000-000000000001',
    'Implementation in progress',
    'User permissions and backup configuration currently in progress.',
    '2026-09-17 15:00:00-05'::timestamptz
  )
on conflict (id) do update
set title = excluded.title,
    message = excluded.message,
    updated_at = now();

insert into public.payments (id, project_id, description, amount, status, due_date)
values
  (
    '55555555-5555-5555-5555-555555555551',
    '22222222-2222-2222-2222-222222222222',
    'Initial payment',
    600000,
    'paid'::public.payment_status,
    '2026-09-01'
  ),
  (
    '55555555-5555-5555-5555-555555555552',
    '22222222-2222-2222-2222-222222222222',
    'Final payment',
    600000,
    'pending'::public.payment_status,
    '2026-10-15'
  )
on conflict (id) do update
set description = excluded.description,
    amount = excluded.amount,
    status = excluded.status,
    due_date = excluded.due_date,
    updated_at = now();

insert into public.comments (id, project_id, user_id, message)
values (
  '66666666-6666-6666-6666-666666666661',
  '22222222-2222-2222-2222-222222222222',
  '00000000-0000-0000-0000-000000000001',
  'Let me know if you have any questions about the current progress.'
)
on conflict (id) do nothing;

commit;
