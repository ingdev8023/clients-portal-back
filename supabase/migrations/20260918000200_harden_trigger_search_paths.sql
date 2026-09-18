-- Keep trigger functions independent of a caller-controlled search_path.
begin;

alter function public.set_updated_at() set search_path = '';
alter function public.prevent_phase_project_change() set search_path = '';
alter function public.set_project_completion() set search_path = '';
alter function public.validate_project_current_phase() set search_path = '';
alter function public.set_phase_timestamps() set search_path = '';
alter function public.sync_project_current_phase() set search_path = '';
alter function public.set_payment_timestamps() set search_path = '';
alter function public.prevent_comment_identity_changes() set search_path = '';
alter function public.set_comment_insert_fields() set search_path = '';

commit;
