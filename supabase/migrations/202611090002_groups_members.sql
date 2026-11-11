create table if not exists public.chit_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  chit_value_paise bigint not null check (chit_value_paise > 0),
  duration_months integer not null check (duration_months > 0),
  member_capacity integer not null check (member_capacity > 0),
  monthly_installment_paise bigint not null check (monthly_installment_paise > 0),
  commission_bps integer not null check (commission_bps >= 0 and commission_bps <= 10000),
  start_date date,
  status text not null default 'draft' check (status in ('draft', 'active', 'completed', 'cancelled')),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.members (
  id uuid primary key default gen_random_uuid(),
  full_name text not null check (length(trim(full_name)) > 0),
  phone text,
  email text,
  notes text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.group_members (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.chit_groups(id) on delete restrict,
  member_id uuid not null references public.members(id) on delete restrict,
  enrolled_at date not null default current_date,
  status text not null default 'active' check (status in ('active', 'exited', 'transferred')),
  created_at timestamptz not null default now(),
  unique (group_id, member_id)
);

create table if not exists public.staff_group_assignments (
  user_id uuid not null references public.profiles(id) on delete cascade,
  group_id uuid not null references public.chit_groups(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, group_id)
);

create index if not exists group_members_group_id_idx on public.group_members(group_id);
create index if not exists group_members_member_id_idx on public.group_members(member_id);
create index if not exists staff_group_assignments_group_id_idx on public.staff_group_assignments(group_id);

create or replace function public.is_active_owner()
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'owner' and p.active) $$;

create or replace function public.can_access_group(target_group uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select public.is_active_owner() or exists (
    select 1 from public.profiles p
    join public.staff_group_assignments a on a.user_id = p.id
    where p.id = (select auth.uid()) and p.role = 'staff' and p.active and a.group_id = target_group
  )
$$;

alter table public.chit_groups enable row level security;
alter table public.members enable row level security;
alter table public.group_members enable row level security;
alter table public.staff_group_assignments enable row level security;

create policy "Assigned users read groups" on public.chit_groups for select to authenticated using (public.can_access_group(id));
create policy "Owners create groups" on public.chit_groups for insert to authenticated with check (public.is_active_owner() and created_by = (select auth.uid()));
create policy "Owners update groups" on public.chit_groups for update to authenticated using (public.is_active_owner()) with check (public.is_active_owner());

create policy "Users read accessible enrollments" on public.group_members for select to authenticated using (public.can_access_group(group_id));
create policy "Owners manage enrollments" on public.group_members for all to authenticated using (public.is_active_owner()) with check (public.is_active_owner());

create policy "Owners manage members" on public.members for all to authenticated using (public.is_active_owner()) with check (public.is_active_owner() and created_by = (select auth.uid()));
create policy "Assigned users read group members" on public.members for select to authenticated using (
  public.is_active_owner() or exists (
    select 1 from public.group_members gm where gm.member_id = members.id and public.can_access_group(gm.group_id)
  )
);

create policy "Owners manage staff assignments" on public.staff_group_assignments for all to authenticated using (public.is_active_owner()) with check (public.is_active_owner());
create policy "Staff read own assignments" on public.staff_group_assignments for select to authenticated using (user_id = (select auth.uid()));

revoke all on public.chit_groups, public.members, public.group_members, public.staff_group_assignments from anon;
grant select, insert, update on public.chit_groups to authenticated;
grant select, insert, update, delete on public.members, public.group_members, public.staff_group_assignments to authenticated;
