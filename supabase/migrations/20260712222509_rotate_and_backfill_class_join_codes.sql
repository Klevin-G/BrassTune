-- Rotate the earlier six-character class codes and backfill any legacy NULLs.
-- The table lock prevents application writes from racing the uniqueness check
-- while this short, one-time migration runs.
do $$
declare
  target record;
  candidate text;
begin
  if to_regclass('public.groups') is null then
    raise exception 'public.groups does not exist';
  end if;

  lock table public.groups in share row exclusive mode;

  for target in
    select id
    from public.groups
    where join_code is null or char_length(join_code) <= 6
    order by id
    for update
  loop
    loop
      -- Ten UUID hex characters provide a 40-bit space while remaining easy to type.
      candidate := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
      exit when not exists (
        select 1
        from public.groups
        where join_code = candidate
          and id <> target.id
      );
    end loop;

    update public.groups
    set join_code = candidate,
        updated_at = now()
    where id = target.id;
  end loop;
end
$$;

create unique index if not exists groups_join_code_key
  on public.groups (join_code)
  where join_code is not null;
