-- A user has at most one lifecycle row per class. Fail closed if historical
-- duplicates exist so an operator can review them instead of deleting data
-- automatically during a production migration.
do $$
begin
  if to_regclass('public.group_members') is null then
    raise exception 'public.group_members does not exist';
  end if;

  if exists (
    select 1
    from public.group_members
    group by group_id, user_id
    having count(*) > 1
  ) then
    raise exception 'duplicate public.group_members rows must be resolved before adding uq_group_members_group_user'
      using errcode = '23505';
  end if;

  -- Accept the baseline's generated constraint name (or any later exact,
  -- unconditional unique index) instead of adding a redundant constraint.
  if not exists (
    select 1
    from pg_index i
    where i.indrelid = 'public.group_members'::regclass
      and i.indisunique
      and i.indisvalid
      and i.indpred is null
      and i.indexprs is null
      and i.indnkeyatts = 2
      and pg_get_indexdef(i.indexrelid, 1, true) = 'group_id'
      and pg_get_indexdef(i.indexrelid, 2, true) = 'user_id'
  ) then
    alter table public.group_members
      add constraint uq_group_members_group_user unique (group_id, user_id);
  end if;
end
$$;
