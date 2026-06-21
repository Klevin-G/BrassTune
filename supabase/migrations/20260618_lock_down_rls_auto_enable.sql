-- Lock down a drifted helper RPC that Supabase advisors reported as public
-- SECURITY DEFINER surface. The app does not call this function at runtime.

do $$
declare
  helper regprocedure;
begin
  for helper in
    select p.oid::regprocedure
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'rls_auto_enable'
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', helper);
  end loop;
end $$;
