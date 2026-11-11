-- Distribute each finalized auction's discount plus the fixed 4% commission
-- equally across the full active roster, then apply the credit to that month's
-- installment. Any indivisible paise are assigned in member-number order.

create or replace function public.prevent_finalizing_after_monthly_payment()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if old.status <> 'finalized' and new.status = 'finalized' then
    perform 1
    from public.installments i
    join public.chit_members cm on cm.id = i.chit_member_id
    where cm.group_id = new.group_id and i.month_number = new.month_number
    for update of i;

    if exists (
      select 1
      from public.installments i
      join public.chit_members cm on cm.id = i.chit_member_id
      join public.payments p on p.installment_id = i.id
      where cm.group_id = new.group_id and i.month_number = new.month_number
    ) then
      raise exception using errcode = 'P0001', message = 'MONTH_ALREADY_HAS_PAYMENTS_CANNOT_DISTRIBUTE_DIVIDEND';
    end if;
  end if;
  return new;
end;
$$;

create trigger auctions_prevent_paid_month_finalization
  before update of status on public.auctions
  for each row execute function public.prevent_finalizing_after_monthly_payment();

create or replace function public.distribute_finalized_auction_dividends()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  group_row public.chit_groups%rowtype;
  commission_amount bigint;
  distribution_pool bigint;
  member_total integer;
  numbered_member_total integer;
  base_share bigint;
  maximum_share bigint;
  remainder_paise integer;
  actor uuid;
begin
  if old.status = 'finalized' or new.status <> 'finalized' then
    return new;
  end if;

  select * into group_row from public.chit_groups where id = new.group_id;
  if not found then raise exception using errcode = 'P0001', message = 'GROUP_NOT_FOUND'; end if;

  if new.commission_paise is not null then
    commission_amount := new.commission_paise;
  else
    if mod(group_row.chit_value_paise, 25) <> 0 then
      raise exception using errcode = 'P0001', message = 'FOUR_PERCENT_COMMISSION_REQUIRES_SUB_PAISE_ROUNDING';
    end if;
    commission_amount := group_row.chit_value_paise / 25;
  end if;
  distribution_pool := new.winning_discount_paise + commission_amount;

  select count(*) into member_total
  from public.chit_members cm
  where cm.group_id = new.group_id and cm.status = 'active';
  select count(*) into numbered_member_total
  from public.chit_members cm
  where cm.group_id = new.group_id and cm.status = 'active' and cm.member_number is not null;
  if member_total <> group_row.member_capacity or numbered_member_total <> member_total or member_total = 0 then
    raise exception using errcode = 'P0001', message = 'GROUP_ROSTER_INCOMPLETE';
  end if;

  base_share := distribution_pool / member_total;
  remainder_paise := mod(distribution_pool, member_total)::integer;
  maximum_share := base_share;
  if remainder_paise > 0 then
    maximum_share := base_share + 1;
  end if;
  if maximum_share > group_row.monthly_installment_paise then
    raise exception using errcode = 'P0001', message = 'DIVIDEND_EXCEEDS_MONTHLY_INSTALLMENT';
  end if;
  actor := coalesce((select auth.uid()), new.finalized_by);

  insert into public.dividends (auction_id, member_id, dividend_amount_paise, created_by)
  select new.id, cm.member_id,
    base_share + case when cm.member_number <= remainder_paise then 1 else 0 end,
    actor
  from public.chit_members cm
  where cm.group_id = new.group_id and cm.status = 'active'
  order by cm.member_number;

  update public.installments i
  set dividend_credit_paise = d.dividend_amount_paise,
      net_due_paise = i.gross_amount_paise - d.dividend_amount_paise,
      status = case when i.gross_amount_paise = d.dividend_amount_paise then 'settled' else 'due' end
  from public.chit_members cm
  join public.dividends d on d.member_id = cm.member_id
  where cm.id = i.chit_member_id and cm.group_id = new.group_id
    and i.month_number = new.month_number and d.auction_id = new.id;

  return new;
end;
$$;

create trigger auctions_distribute_dividends
  after update of status on public.auctions
  for each row execute function public.distribute_finalized_auction_dividends();

revoke insert, update, delete on public.dividends from authenticated;

create or replace function public.generate_group_installments(
  target_group uuid,
  target_month integer,
  installment_due_date date
)
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  group_row public.chit_groups%rowtype;
  active_count integer;
  numbered_member_count integer;
  inserted_count integer;
begin
  if not public.is_active_owner() then
    raise exception using errcode = '42501', message = 'OWNER_REQUIRED';
  end if;
  select * into group_row from public.chit_groups where id = target_group for update;
  if not found then raise exception using errcode = 'P0001', message = 'GROUP_NOT_FOUND'; end if;
  if group_row.status <> 'active' then
    raise exception using errcode = 'P0001', message = 'GROUP_NOT_ACTIVE';
  end if;
  if target_month < 1 or target_month > group_row.duration_months then
    raise exception using errcode = 'P0001', message = 'INVALID_INSTALLMENT_MONTH';
  end if;
  if installment_due_date is null then
    raise exception using errcode = 'P0001', message = 'INSTALLMENT_DUE_DATE_REQUIRED';
  end if;

  select count(*) into active_count from public.chit_members
  where group_id = target_group and status = 'active';
  select count(*) into numbered_member_count from public.chit_members
  where group_id = target_group and status = 'active' and member_number is not null;
  if active_count <> group_row.member_capacity or numbered_member_count <> active_count then
    raise exception using errcode = 'P0001', message = 'GROUP_ROSTER_INCOMPLETE';
  end if;
  if exists (
    select 1 from public.installments i
    join public.chit_members cm on cm.id = i.chit_member_id
    where cm.group_id = target_group and i.month_number = target_month
  ) then
    raise exception using errcode = 'P0001', message = 'INSTALLMENTS_ALREADY_GENERATED';
  end if;

  insert into public.installments (
    chit_member_id, month_number, due_date, gross_amount_paise,
    dividend_credit_paise, net_due_paise, status, created_by
  )
  select cm.id, target_month, installment_due_date, group_row.monthly_installment_paise,
    coalesce(d.dividend_amount_paise, 0),
    group_row.monthly_installment_paise - coalesce(d.dividend_amount_paise, 0),
    case when coalesce(d.dividend_amount_paise, 0) = group_row.monthly_installment_paise then 'settled' else 'due' end,
    (select auth.uid())
  from public.chit_members cm
  left join public.auctions a on a.group_id = cm.group_id
    and a.month_number = target_month and a.status = 'finalized'
  left join public.dividends d on d.auction_id = a.id and d.member_id = cm.member_id
  where cm.group_id = target_group and cm.status = 'active';
  get diagnostics inserted_count = row_count;
  return inserted_count;
end;
$$;

revoke all on function public.generate_group_installments(uuid, integer, date) from public;
grant execute on function public.generate_group_installments(uuid, integer, date) to authenticated;
