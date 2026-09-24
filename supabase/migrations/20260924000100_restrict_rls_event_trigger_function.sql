-- The platform event trigger invokes this function internally; browser roles do
-- not need a callable RPC path to its SECURITY DEFINER implementation.
begin;

do $migration$
begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    execute 'revoke execute on function public.rls_auto_enable() from public, anon, authenticated';
  end if;
end
$migration$;

commit;
