-- Rotate the earlier six-character class codes and backfill any legacy NULLs.
-- The table lock prevents application writes from racing the uniqueness check
-- while this short, one-time migration runs.
do $$
declare
  target record;
  candidate text;
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
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
      -- Match the application's eight-character alphabet and omit 0/O/1/I/L.
      select string_agg(
        substr(alphabet, (floor(random() * length(alphabet)) + 1)::integer, 1),
        ''
      )
      into candidate
      from generate_series(1, 8);
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
