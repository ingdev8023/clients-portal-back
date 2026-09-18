-- Client Project Portal - Supabase/PostgreSQL backend foundation.
-- This migration creates the MVP data model, authorization helpers,
-- Row Level Security policies, audit triggers, and operational constraints.

begin;

create extension if not exists pgcrypto;

create schema if not exists app;

create type public.app_role as enum ('admin', 'client');
create type public.project_status as enum ('planned', 'active', 'paused', 'completed', 'cancelled');
create type public.phase_status as enum ('pending', 'active', 'completed');
create type public.payment_status as enum ('pending', 'paid', 'overdue', 'cancelled');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  role public.app_role not null default 'client',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.clients (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  contact_name text not null,
  contact_email text not null,
  logo_url text,
  accent_color text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint clients_contact_email_format check (contact_email ~* '^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$'),
  constraint clients_accent_color_format check (accent_color is null or accent_color ~* '^#[0-9A-F]{6}$')
);

create table public.client_users (
  client_id uuid not null references public.clients(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (client_id, user_id)
);

create table public.projects (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete restrict,
  name text not null,
  slug text not null,
  description text,
  status public.project_status not null default 'planned',
  progress_percentage integer not null default 0,
  current_phase_id uuid,
  start_date date,
  estimated_end_date date,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint projects_slug_format check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  constraint projects_progress_range check (progress_percentage between 0 and 100),
  constraint projects_dates_order check (
    start_date is null
    or estimated_end_date is null
    or estimated_end_date >= start_date
  ),
  constraint projects_client_slug_unique unique (client_id, slug)
);

create table public.project_phases (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  name text not null,
  description text,
  status public.phase_status not null default 'pending',
  position integer not null,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint project_phases_position_positive check (position > 0),
  constraint project_phases_project_position_unique unique (project_id, position)
);

alter table public.projects
  add constraint projects_current_phase_fk
  foreign key (current_phase_id) references public.project_phases(id) on delete set null
  deferrable initially immediate;

create table public.project_updates (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete restrict,
  title text,
  message text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  description text not null,
  amount numeric(12,2) not null,
  status public.payment_status not null default 'pending',
  due_date date,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payments_amount_non_negative check (amount >= 0)
);

create table public.comments (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete restrict,
  message text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  deleted_at timestamptz
);

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  project_id uuid,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  old_values jsonb,
  new_values jsonb,
  created_at timestamptz not null default now()
);

create index profiles_role_idx on public.profiles(role);
create index clients_contact_email_idx on public.clients(contact_email);
create index client_users_user_id_idx on public.client_users(user_id);
create index projects_client_id_idx on public.projects(client_id);
create index projects_status_idx on public.projects(status);
create index project_phases_project_id_idx on public.project_phases(project_id);
create unique index project_phases_one_active_per_project_idx
  on public.project_phases(project_id)
  where status = 'active';
create index project_updates_project_created_idx on public.project_updates(project_id, created_at desc);
create index payments_project_status_idx on public.payments(project_id, status);
create index comments_project_created_idx on public.comments(project_id, created_at);
create index comments_user_id_idx on public.comments(user_id);
create index audit_logs_project_created_idx on public.audit_logs(project_id, created_at desc);
create index audit_logs_entity_idx on public.audit_logs(entity_type, entity_id);

create or replace function app.is_admin()
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and role = 'admin'::public.app_role
  );
$$;

create or replace function app.can_access_client(check_client_id uuid)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select app.is_admin()
    or exists (
      select 1
      from public.client_users
      where client_id = check_client_id
        and user_id = auth.uid()
    );
$$;

create or replace function app.can_access_project(check_project_id uuid)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select app.is_admin()
    or exists (
      select 1
      from public.projects p
      join public.client_users cu on cu.client_id = p.client_id
      where p.id = check_project_id
        and cu.user_id = auth.uid()
    );
$$;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function app.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', ''), 'client'::public.app_role);
  return new;
end;
$$;

create or replace function public.prevent_phase_project_change()
returns trigger
language plpgsql
as $$
begin
  if new.project_id is distinct from old.project_id then
    raise exception 'A phase cannot be moved to another project';
  end if;
  return new;
end;
$$;

create or replace function public.set_project_completion()
returns trigger
language plpgsql
as $$
begin
  if new.status = 'completed'::public.project_status then
    new.completed_at = coalesce(new.completed_at, now());
    new.progress_percentage = 100;
  else
    new.completed_at = null;
  end if;

  return new;
end;
$$;

create or replace function public.validate_project_current_phase()
returns trigger
language plpgsql
as $$
begin
  if new.current_phase_id is not null and not exists (
    select 1
    from public.project_phases pp
    where pp.id = new.current_phase_id
      and pp.project_id = new.id
      and pp.status = 'active'::public.phase_status
  ) then
    raise exception 'current_phase_id must reference an active phase in the same project';
  end if;

  return new;
end;
$$;

create or replace function public.set_phase_timestamps()
returns trigger
language plpgsql
as $$
begin
  if new.status = 'active'::public.phase_status then
    new.started_at = coalesce(new.started_at, now());
  end if;

  if new.status = 'completed'::public.phase_status then
    new.completed_at = coalesce(new.completed_at, now());
  else
    new.completed_at = null;
  end if;

  return new;
end;
$$;

create or replace function public.sync_project_current_phase()
returns trigger
language plpgsql
as $$
begin
  if tg_op in ('INSERT', 'UPDATE') and new.status = 'active'::public.phase_status then
    update public.projects
    set current_phase_id = new.id
    where id = new.project_id;
  elsif tg_op = 'UPDATE'
        and old.status = 'active'::public.phase_status
        and new.status is distinct from 'active'::public.phase_status then
    update public.projects
    set current_phase_id = null
    where id = new.project_id
      and current_phase_id = old.id;
  end if;

  return new;
end;
$$;

create or replace function public.set_payment_timestamps()
returns trigger
language plpgsql
as $$
begin
  if new.status = 'paid'::public.payment_status then
    new.paid_at = coalesce(new.paid_at, now());
  else
    new.paid_at = null;
  end if;

  return new;
end;
$$;

create or replace function public.prevent_comment_identity_changes()
returns trigger
language plpgsql
as $$
begin
  if new.project_id is distinct from old.project_id
     or new.user_id is distinct from old.user_id
     or new.created_at is distinct from old.created_at then
    raise exception 'comment project_id, user_id, and created_at are immutable';
  end if;

  if old.deleted_at is not null and not app.is_admin() then
    raise exception 'A deleted comment cannot be edited';
  end if;

  if new.deleted_at is not null and new.deleted_at is distinct from old.deleted_at then
    new.deleted_at = now();
  end if;

  return new;
end;
$$;

create or replace function public.set_comment_insert_fields()
returns trigger
language plpgsql
as $$
begin
  new.created_at = now();
  new.updated_at = null;
  new.deleted_at = null;
  return new;
end;
$$;

create or replace function public.audit_projects()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    insert into public.audit_logs(user_id, project_id, action, entity_type, entity_id, old_values)
    values (auth.uid(), old.id, 'project_deleted', 'project', old.id, to_jsonb(old));
    return old;
  end if;

  if tg_op = 'INSERT' then
    insert into public.audit_logs(user_id, project_id, action, entity_type, entity_id, new_values)
    values (auth.uid(), new.id, 'project_created', 'project', new.id, to_jsonb(new));
    return new;
  end if;

  if old.status is distinct from new.status then
    insert into public.audit_logs(user_id, project_id, action, entity_type, entity_id, old_values, new_values)
    values (
      auth.uid(),
      new.id,
      'project_status_changed',
      'project',
      new.id,
      jsonb_build_object('status', old.status),
      jsonb_build_object('status', new.status)
    );
  end if;

  if old.progress_percentage is distinct from new.progress_percentage then
    insert into public.audit_logs(user_id, project_id, action, entity_type, entity_id, old_values, new_values)
    values (
      auth.uid(),
      new.id,
      'project_progress_changed',
      'project',
      new.id,
      jsonb_build_object('progress_percentage', old.progress_percentage),
      jsonb_build_object('progress_percentage', new.progress_percentage)
    );
  end if;

  if old.status is distinct from 'completed'::public.project_status
     and new.status = 'completed'::public.project_status then
    insert into public.audit_logs(user_id, project_id, action, entity_type, entity_id, old_values, new_values)
    values (auth.uid(), new.id, 'project_completed', 'project', new.id, to_jsonb(old), to_jsonb(new));
  end if;

  if to_jsonb(old) - array['updated_at'] is distinct from to_jsonb(new) - array['updated_at'] then
    insert into public.audit_logs(user_id, project_id, action, entity_type, entity_id, old_values, new_values)
    values (auth.uid(), new.id, 'project_updated', 'project', new.id, to_jsonb(old), to_jsonb(new));
  end if;

  return new;
end;
$$;

create or replace function public.audit_project_phases()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    insert into public.audit_logs(user_id, project_id, action, entity_type, entity_id, old_values)
    values (auth.uid(), old.project_id, 'phase_deleted', 'project_phase', old.id, to_jsonb(old));
    return old;
  end if;

  if tg_op = 'INSERT' then
    insert into public.audit_logs(user_id, project_id, action, entity_type, entity_id, new_values)
    values (auth.uid(), new.project_id, 'phase_created', 'project_phase', new.id, to_jsonb(new));
    return new;
  end if;

  if old.status is distinct from 'completed'::public.phase_status
     and new.status = 'completed'::public.phase_status then
    insert into public.audit_logs(user_id, project_id, action, entity_type, entity_id, old_values, new_values)
    values (auth.uid(), new.project_id, 'phase_completed', 'project_phase', new.id, to_jsonb(old), to_jsonb(new));
  end if;

  if to_jsonb(old) - array['updated_at'] is distinct from to_jsonb(new) - array['updated_at'] then
    insert into public.audit_logs(user_id, project_id, action, entity_type, entity_id, old_values, new_values)
    values (auth.uid(), new.project_id, 'phase_updated', 'project_phase', new.id, to_jsonb(old), to_jsonb(new));
  end if;

  return new;
end;
$$;

create or replace function public.audit_payments()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    insert into public.audit_logs(user_id, project_id, action, entity_type, entity_id, old_values)
    values (auth.uid(), old.project_id, 'payment_deleted', 'payment', old.id, to_jsonb(old));
    return old;
  end if;

  if tg_op = 'INSERT' then
    insert into public.audit_logs(user_id, project_id, action, entity_type, entity_id, new_values)
    values (auth.uid(), new.project_id, 'payment_created', 'payment', new.id, to_jsonb(new));
    return new;
  end if;

  if old.status is distinct from new.status then
    insert into public.audit_logs(user_id, project_id, action, entity_type, entity_id, old_values, new_values)
    values (
      auth.uid(),
      new.project_id,
      'payment_status_changed',
      'payment',
      new.id,
      jsonb_build_object('status', old.status),
      jsonb_build_object('status', new.status)
    );
  end if;

  if to_jsonb(old) - array['updated_at'] is distinct from to_jsonb(new) - array['updated_at'] then
    insert into public.audit_logs(user_id, project_id, action, entity_type, entity_id, old_values, new_values)
    values (auth.uid(), new.project_id, 'payment_updated', 'payment', new.id, to_jsonb(old), to_jsonb(new));
  end if;

  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function app.handle_new_user();

create trigger set_profiles_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create trigger set_clients_updated_at
before update on public.clients
for each row execute function public.set_updated_at();

create trigger set_projects_completion
before insert or update of status, progress_percentage on public.projects
for each row execute function public.set_project_completion();

create trigger validate_projects_current_phase
before insert or update of current_phase_id on public.projects
for each row execute function public.validate_project_current_phase();

create trigger set_projects_updated_at
before update on public.projects
for each row execute function public.set_updated_at();

create trigger audit_projects_after_change
after insert or update or delete on public.projects
for each row execute function public.audit_projects();

create trigger set_project_phases_timestamps
before insert or update of status on public.project_phases
for each row execute function public.set_phase_timestamps();

create trigger set_project_phases_updated_at
before update on public.project_phases
for each row execute function public.set_updated_at();

create trigger prevent_phase_project_change_before_update
before update of project_id on public.project_phases
for each row execute function public.prevent_phase_project_change();

create trigger sync_project_current_phase_after_phase_change
after insert or update of status on public.project_phases
for each row execute function public.sync_project_current_phase();

create trigger audit_project_phases_after_change
after insert or update or delete on public.project_phases
for each row execute function public.audit_project_phases();

create trigger set_project_updates_updated_at
before update on public.project_updates
for each row execute function public.set_updated_at();

create trigger set_payments_timestamps
before insert or update of status on public.payments
for each row execute function public.set_payment_timestamps();

create trigger set_payments_updated_at
before update on public.payments
for each row execute function public.set_updated_at();

create trigger audit_payments_after_change
after insert or update or delete on public.payments
for each row execute function public.audit_payments();

create trigger prevent_comment_identity_changes_before_update
before update on public.comments
for each row execute function public.prevent_comment_identity_changes();

create trigger set_comment_insert_fields_before_insert
before insert on public.comments
for each row execute function public.set_comment_insert_fields();

create trigger set_comments_updated_at
before update on public.comments
for each row execute function public.set_updated_at();

alter table public.profiles enable row level security;
alter table public.clients enable row level security;
alter table public.client_users enable row level security;
alter table public.projects enable row level security;
alter table public.project_phases enable row level security;
alter table public.project_updates enable row level security;
alter table public.payments enable row level security;
alter table public.comments enable row level security;
alter table public.audit_logs enable row level security;

create policy profiles_select_self_or_admin
on public.profiles
for select
to authenticated
using (id = auth.uid() or app.is_admin());

create policy profiles_update_own_or_admin
on public.profiles
for update
to authenticated
using (id = auth.uid() or app.is_admin())
with check (id = auth.uid() or app.is_admin());

create policy clients_admin_select
on public.clients
for select
to authenticated
using (app.is_admin());

create policy clients_admin_insert
on public.clients
for insert
to authenticated
with check (app.is_admin());

create policy clients_admin_update
on public.clients
for update
to authenticated
using (app.is_admin())
with check (app.is_admin());

create policy clients_admin_delete
on public.clients
for delete
to authenticated
using (app.is_admin());

create policy clients_client_select
on public.clients
for select
to authenticated
using (app.can_access_client(id));

create policy client_users_admin_select
on public.client_users
for select
to authenticated
using (app.is_admin());

create policy client_users_admin_insert
on public.client_users
for insert
to authenticated
with check (app.is_admin());

create policy client_users_admin_update
on public.client_users
for update
to authenticated
using (app.is_admin())
with check (app.is_admin());

create policy client_users_admin_delete
on public.client_users
for delete
to authenticated
using (app.is_admin());

create policy client_users_select_own
on public.client_users
for select
to authenticated
using (user_id = auth.uid());

create policy projects_admin_select
on public.projects
for select
to authenticated
using (app.is_admin());

create policy projects_admin_insert
on public.projects
for insert
to authenticated
with check (app.is_admin());

create policy projects_admin_update
on public.projects
for update
to authenticated
using (app.is_admin())
with check (app.is_admin());

create policy projects_admin_delete
on public.projects
for delete
to authenticated
using (app.is_admin());

create policy projects_client_select
on public.projects
for select
to authenticated
using (app.can_access_project(id));

create policy project_phases_admin_select
on public.project_phases
for select
to authenticated
using (app.is_admin());

create policy project_phases_admin_insert
on public.project_phases
for insert
to authenticated
with check (app.is_admin());

create policy project_phases_admin_update
on public.project_phases
for update
to authenticated
using (app.is_admin())
with check (app.is_admin());

create policy project_phases_admin_delete
on public.project_phases
for delete
to authenticated
using (app.is_admin());

create policy project_phases_client_select
on public.project_phases
for select
to authenticated
using (app.can_access_project(project_id));

create policy project_updates_admin_select
on public.project_updates
for select
to authenticated
using (app.is_admin());

create policy project_updates_admin_insert
on public.project_updates
for insert
to authenticated
with check (app.is_admin() and created_by = auth.uid());

create policy project_updates_admin_update
on public.project_updates
for update
to authenticated
using (app.is_admin())
with check (app.is_admin());

create policy project_updates_admin_delete
on public.project_updates
for delete
to authenticated
using (app.is_admin());

create policy project_updates_client_select
on public.project_updates
for select
to authenticated
using (app.can_access_project(project_id));

create policy payments_admin_select
on public.payments
for select
to authenticated
using (app.is_admin());

create policy payments_admin_insert
on public.payments
for insert
to authenticated
with check (app.is_admin());

create policy payments_admin_update
on public.payments
for update
to authenticated
using (app.is_admin())
with check (app.is_admin());

create policy payments_admin_delete
on public.payments
for delete
to authenticated
using (app.is_admin());

create policy payments_client_select
on public.payments
for select
to authenticated
using (app.can_access_project(project_id));

create policy comments_select_accessible
on public.comments
for select
to authenticated
using (
  app.is_admin()
  or (deleted_at is null and app.can_access_project(project_id))
);

create policy comments_insert_accessible
on public.comments
for insert
to authenticated
with check (
  user_id = auth.uid()
  and app.can_access_project(project_id)
  and deleted_at is null
);

create policy comments_admin_update
on public.comments
for update
to authenticated
using (app.is_admin())
with check (app.is_admin());

create policy comments_update_own_recent
on public.comments
for update
to authenticated
using (
  user_id = auth.uid()
  and deleted_at is null
  and created_at > now() - interval '15 minutes'
  and app.can_access_project(project_id)
)
with check (
  user_id = auth.uid()
  and created_at > now() - interval '15 minutes'
  and app.can_access_project(project_id)
);

create policy audit_logs_admin_select
on public.audit_logs
for select
to authenticated
using (app.is_admin());

revoke all on table
  public.profiles,
  public.clients,
  public.client_users,
  public.projects,
  public.project_phases,
  public.project_updates,
  public.payments,
  public.comments,
  public.audit_logs
from anon, authenticated;

grant select on table public.profiles to authenticated;
grant update (full_name) on table public.profiles to authenticated;

grant select, insert, update, delete
on table
  public.clients,
  public.client_users,
  public.projects,
  public.project_phases,
  public.payments
to authenticated;

grant select, insert, delete on table public.project_updates to authenticated;
grant update (title, message) on table public.project_updates to authenticated;

grant select, insert on table public.comments to authenticated;
grant update (message, deleted_at) on table public.comments to authenticated;

grant select
on table public.audit_logs
to authenticated;

revoke execute on all functions in schema app from public, anon, authenticated;
grant usage on schema app to authenticated;
grant execute on function app.is_admin() to authenticated;
grant execute on function app.can_access_client(uuid) to authenticated;
grant execute on function app.can_access_project(uuid) to authenticated;

revoke execute on function public.audit_projects() from public, anon, authenticated;
revoke execute on function public.audit_project_phases() from public, anon, authenticated;
revoke execute on function public.audit_payments() from public, anon, authenticated;

commit;
