alter table public.chit_members add column created_by uuid references public.profiles(id);
update public.chit_members cm
set created_by = cg.created_by
from public.chit_groups cg
where cg.id = cm.group_id and cm.created_by is null;
alter table public.chit_members alter column created_by set not null;

alter table public.chit_groups add column activated_at timestamptz;
alter table public.chit_groups add column activated_by uuid references public.profiles(id);

drop policy "Owners create chit memberships" on public.chit_members;
revoke insert on public.chit_members from authenticated;

create or replace function public.enroll_member(target_group uuid, target_member uuid)
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  group_row public.chit_groups%rowtype;
  next_number integer;
begin
  if not public.is_active_owner() then
    raise exception using errcode = '42501', message = 'OWNER_REQUIRED';
  end if;

  select * into group_row
  from public.chit_groups
  where id = target_group
  for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'GROUP_NOT_FOUND';
  end if;
  if group_row.status <> 'draft' then
    raise exception using errcode = 'P0001', message = 'GROUP_NOT_DRAFT';
  end if;
  if not exists (select 1 from public.members where id = target_member) then
    raise exception using errcode = 'P0001', message = 'MEMBER_NOT_FOUND';
  end if;
  if exists (select 1 from public.chit_members where group_id = target_group and member_id = target_member) then
    raise exception using errcode = 'P0001', message = 'MEMBER_ALREADY_ENROLLED';
  end if;

  select slots.slot into next_number
  from generate_series(1, group_row.member_capacity) as slots(slot)
  where not exists (
    select 1 from public.chit_members cm
  where cm.group_id = target_group and cm.member_number = slots.slot
  )
  order by slot
  limit 1;
  if next_number is null then
    raise exception using errcode = 'P0001', message = 'GROUP_FULL';
  end if;

  insert into public.chit_members (group_id, member_id, member_number, created_by)
  values (target_group, target_member, next_number, (select auth.uid()));
  return next_number;
end;
$$;

create or replace function public.guard_group_activation()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  active_count integer;
  numbered_count integer;
begin
  if tg_op = 'INSERT' then
    if new.status <> 'draft' then
      raise exception using errcode = 'P0001', message = 'GROUPS_MUST_START_AS_DRAFTS';
    end if;
    return new;
  end if;
  if old.status <> new.status and not (old.status = 'draft' and new.status = 'active') then
    raise exception using errcode = 'P0001', message = 'INVALID_GROUP_STATUS_TRANSITION';
  end if;
  if old.status = 'active' and (
    new.name is distinct from old.name or
    new.group_code is distinct from old.group_code or
    new.chit_value_paise is distinct from old.chit_value_paise or
    new.duration_months is distinct from old.duration_months or
    new.member_capacity is distinct from old.member_capacity or
    new.monthly_installment_paise is distinct from old.monthly_installment_paise or
    new.commission_bps is distinct from old.commission_bps or
    new.start_date is distinct from old.start_date
  ) then
    raise exception using errcode = 'P0001', message = 'ACTIVE_GROUP_TERMS_LOCKED';
  end if;
  if new.status = 'active' and old.status = 'draft' then
    if new.start_date is null then
      raise exception using errcode = 'P0001', message = 'GROUP_START_DATE_REQUIRED';
    end if;
    select count(*), count(member_number) into active_count, numbered_count
    from public.chit_members cm
    where cm.group_id = new.id and cm.status = 'active';
    if active_count <> new.member_capacity or numbered_count <> new.member_capacity then
      raise exception using errcode = 'P0001', message = 'GROUP_NOT_FULL';
    end if;
    new.activated_at := now();
    new.activated_by := (select auth.uid());
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists chit_groups_guard_activation on public.chit_groups;
create trigger chit_groups_guard_activation
  before insert or update on public.chit_groups
  for each row execute function public.guard_group_activation();

drop policy "Owners create groups" on public.chit_groups;
create policy "Owners create draft groups" on public.chit_groups
  for insert to authenticated
  with check (public.is_active_owner() and created_by = (select auth.uid()) and status = 'draft');

create or replace function public.activate_chit_group(target_group uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  group_row public.chit_groups%rowtype;
  active_count integer;
  numbered_count integer;
begin
  if not public.is_active_owner() then
    raise exception using errcode = '42501', message = 'OWNER_REQUIRED';
  end if;

  select * into group_row
  from public.chit_groups
  where id = target_group
  for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'GROUP_NOT_FOUND';
  end if;
  if group_row.status <> 'draft' then
    raise exception using errcode = 'P0001', message = 'GROUP_NOT_DRAFT';
  end if;
  if group_row.start_date is null then
    raise exception using errcode = 'P0001', message = 'GROUP_START_DATE_REQUIRED';
  end if;

  select count(*), count(member_number) into active_count, numbered_count
  from public.chit_members
  where group_id = target_group and status = 'active';
  if active_count <> group_row.member_capacity or numbered_count <> group_row.member_capacity then
    raise exception using errcode = 'P0001', message = 'GROUP_NOT_FULL';
  end if;

  update public.chit_groups set status = 'active' where id = target_group;
end;
$$;

revoke all on function public.enroll_member(uuid, uuid) from public;
revoke all on function public.activate_chit_group(uuid) from public;
grant execute on function public.enroll_member(uuid, uuid) to authenticated;
grant execute on function public.activate_chit_group(uuid) to authenticated;
