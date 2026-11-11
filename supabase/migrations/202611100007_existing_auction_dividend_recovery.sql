-- Safe recovery for months finalized before automatic dividend distribution
-- was installed. The owner can distribute once, only before payments exist.

create or replace function public.apply_auction_dividends(target_auction uuid, actor_id uuid)
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  auction_row public.auctions%rowtype;
  group_row public.chit_groups%rowtype;
  commission_amount bigint;
  distribution_pool bigint;
  member_total integer;
  numbered_member_total integer;
  base_share bigint;
  maximum_share bigint;
  remainder_paise integer;
  inserted_count integer;
begin
  select * into auction_row from public.auctions where id = target_auction for update;
  if not found or auction_row.status <> 'finalized' then
    raise exception using errcode = 'P0001', message = 'FINALIZED_AUCTION_REQUIRED';
  end if;
  if exists (select 1 from public.dividends d where d.auction_id = target_auction) then
    raise exception using errcode = 'P0001', message = 'AUCTION_DIVIDENDS_ALREADY_DISTRIBUTED';
  end if;

  perform 1 from public.installments i
  join public.chit_members cm on cm.id = i.chit_member_id
  where cm.group_id = auction_row.group_id and i.month_number = auction_row.month_number
  for update of i;
  if exists (
    select 1 from public.installments i
    join public.chit_members cm on cm.id = i.chit_member_id
    join public.payments p on p.installment_id = i.id
    where cm.group_id = auction_row.group_id and i.month_number = auction_row.month_number
  ) then
    raise exception using errcode = 'P0001', message = 'MONTH_ALREADY_HAS_PAYMENTS_CANNOT_DISTRIBUTE_DIVIDEND';
  end if;

  select * into group_row from public.chit_groups where id = auction_row.group_id for update;
  if auction_row.commission_paise is not null then
    commission_amount := auction_row.commission_paise;
  else
    if mod(group_row.chit_value_paise, 25) <> 0 then
      raise exception using errcode = 'P0001', message = 'FOUR_PERCENT_COMMISSION_REQUIRES_SUB_PAISE_ROUNDING';
    end if;
    commission_amount := group_row.chit_value_paise / 25;
  end if;
  distribution_pool := auction_row.winning_discount_paise + commission_amount;

  select count(*) into member_total from public.chit_members cm
  where cm.group_id = auction_row.group_id and cm.status = 'active';
  select count(*) into numbered_member_total from public.chit_members cm
  where cm.group_id = auction_row.group_id and cm.status = 'active' and cm.member_number is not null;
  if member_total <> group_row.member_capacity or numbered_member_total <> member_total or member_total = 0 then
    raise exception using errcode = 'P0001', message = 'GROUP_ROSTER_INCOMPLETE';
  end if;

  base_share := distribution_pool / member_total;
  remainder_paise := mod(distribution_pool, member_total)::integer;
  maximum_share := base_share;
  if remainder_paise > 0 then maximum_share := base_share + 1; end if;
  if maximum_share > group_row.monthly_installment_paise then
    raise exception using errcode = 'P0001', message = 'DIVIDEND_EXCEEDS_MONTHLY_INSTALLMENT';
  end if;

  insert into public.dividends (auction_id, member_id, dividend_amount_paise, created_by)
  select auction_row.id, cm.member_id,
    base_share + case when cm.member_number <= remainder_paise then 1 else 0 end,
    actor_id
  from public.chit_members cm
  where cm.group_id = auction_row.group_id and cm.status = 'active'
  order by cm.member_number;
  get diagnostics inserted_count = row_count;

  update public.installments i
  set dividend_credit_paise = d.dividend_amount_paise,
      net_due_paise = i.gross_amount_paise - d.dividend_amount_paise,
      status = case when i.gross_amount_paise = d.dividend_amount_paise then 'settled' else 'due' end
  from public.chit_members cm
  join public.dividends d on d.member_id = cm.member_id
  where cm.id = i.chit_member_id and cm.group_id = auction_row.group_id
    and i.month_number = auction_row.month_number and d.auction_id = auction_row.id;
  return inserted_count;
end;
$$;

create or replace function public.distribute_finalized_auction_dividends()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if old.status = 'finalized' or new.status <> 'finalized' then return new; end if;
  perform public.apply_auction_dividends(new.id, coalesce((select auth.uid()), new.finalized_by));
  return new;
end;
$$;

create or replace function public.backfill_finalized_auction_dividends(target_auction uuid)
returns integer language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_active_owner() then
    raise exception using errcode = '42501', message = 'OWNER_REQUIRED';
  end if;
  return public.apply_auction_dividends(target_auction, (select auth.uid()));
end;
$$;

revoke all on function public.apply_auction_dividends(uuid, uuid) from public, authenticated;
revoke all on function public.backfill_finalized_auction_dividends(uuid) from public;
grant execute on function public.backfill_finalized_auction_dividends(uuid) to authenticated;
