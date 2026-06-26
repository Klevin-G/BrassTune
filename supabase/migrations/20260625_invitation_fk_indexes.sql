create index if not exists idx_invitations_invited_user_id
  on public.invitations(invited_user_id);

create index if not exists idx_invitations_invited_by_user_id
  on public.invitations(invited_by_user_id);
