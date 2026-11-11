-- Monthly financial rules: fixed group commission, manually entered auction
-- discount, discount-only dividends, and winner payout reconciliation.

alter table public.chit_groups add column commission_amount_paise bigint;
update public.chit_groups
set commission_amount_paise = round(chit_value_paise::numeric * commission_bps / 10000)::bigint
where commission_amount_paise is null;
alter table public.chit_groups alter column commission_amount_paise set not null;
alter table public.chit_groups add constraint chit_groups_commission_amount_nonnegative
  check (commission_amount_paise >= 0);
update public.chit_groups
set monthly_installment_paise = round(chit_value_paise::numeric / duration_months)::bigint;
alter table public.chit_groups add constraint chit_groups_base_installment_matches_duration
  check (monthly_installment_paise = round(chit_value_paise::numeric / duration_months)::bigint);

alter table public.auctions add column auction_date date;
-- Historical finalized auctions are immutable through the application guard.
-- Disable only that row trigger while backfilling this new metadata column;
-- the migration transaction restores it if any statement fails.
alter table public.auctions disable trigger auctions_guard_changes;
update public.auctions set auction_date = created_at::date where auction_date is null;
alter table public.auctions enable trigger auctions_guard_changes;
alter table public.auctions alter column auction_date set not null;
alter table public.auctions drop constraint if exists auctions_group_id_winner_member_id_key;
create unique index auctions_group_finalized_winner_key
  on public.auctions(group_id, winner_member_id)
  where status = 'finalized' and winner_member_id is not null;

create table public.chit_group_commission_audit (
  id uuid primary key default extensions.gen_random_uuid(),
  group_id uuid not null references public.chit_groups(id) on delete restrict,
  previous_amount_paise bigint not null,
  new_amount_paise bigint not null,
  changed_by uuid not null references public.profiles(id),
  changed_at timestamptz not null default now()
);

create table public.auction_commission_overrides (
  id uuid primary key default extensions.gen_random_uuid(),
  auction_id uuid not null unique references public.auctions(id) on delete restrict,
  configured_amount_paise bigint not null,
  applied_amount_paise bigint not null,
  changed_by uuid not null references public.profiles(id),
  changed_at timestamptz not null default now()
);

alter table public.chit_group_commission_audit enable row level security;
alter table public.auction_commission_overrides enable row level security;
create policy "Owners read group commission audit" on public.chit_group_commission_audit
  for select to authenticated using (public.is_active_owner());
create policy "Owners read auction commission overrides" on public.auction_commission_overrides
  for select to authenticated using (public.is_active_owner());
revoke all on public.chit_group_commission_audit, public.auction_commission_overrides from anon, authenticated;
grant select on public.chit_group_commission_audit, public.auction_commission_overrides to authenticated;

create or replace function public.audit_group_commission_change()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.commission_amount_paise is distinct from old.commission_amount_paise then
    if not public.is_active_owner() then
      raise exception using errcode = '42501', message = 'OWNER_REQUIRED_FOR_COMMISSION_CHANGE';
    end if;
    insert into public.chit_group_commission_audit (
      group_id, previous_amount_paise, new_amount_paise, changed_by
    ) values (new.id, old.commission_amount_paise, new.commission_amount_paise, (select auth.uid()));
  end if;
  return new;
end;
$$;
create trigger chit_groups_audit_commission
  before update of commission_amount_paise on public.chit_groups
  for each row execute function public.audit_group_commission_change();

create or replace function public.require_finalized_month_for_payment()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.installments i
    join public.chit_members cm on cm.id = i.chit_member_id
    join public.auctions a on a.group_id = cm.group_id and a.month_number = i.month_number
    where i.id = new.installment_id and a.status = 'finalized'
  ) then
    raise exception using errcode = 'P0001', message = 'PAYMENTS_REQUIRE_FINALIZED_MONTHLY_AUCTION';
  end if;
  return new;
end;
$$;
create trigger payments_require_finalized_auction
  before insert on public.payments
  for each row execute function public.require_finalized_month_for_payment();

create or replace function public.guard_auction_changes()
returns trigger language plpgsql set search_path = ''
as $$
declare
  group_row public.chit_groups%rowtype;
  submitted_discount bigint;
begin
  if tg_op = 'DELETE' then
    if old.status = 'finalized' then raise exception 'Finalized auctions are immutable'; end if;
    return old;
  end if;
  if tg_op = 'INSERT' then
    if new.status <> 'draft' then
      raise exception using errcode = 'P0001', message = 'AUCTIONS_MUST_START_AS_DRAFTS';
    end if;
    select * into group_row from public.chit_groups where id = new.group_id;
    if not found or group_row.status <> 'active' or new.month_number > group_row.duration_months then
      raise exception using errcode = 'P0001', message = 'AUCTION_REQUIRES_ACTIVE_GROUP_AND_VALID_MONTH';
    end if;
    new.auction_date := coalesce(new.auction_date, (now() at time zone 'Asia/Kolkata')::date);
    new.commission_paise := coalesce(new.commission_paise, group_row.commission_amount_paise);
    return new;
  end if;
  if old.status = 'finalized' then raise exception 'Finalized auctions are immutable'; end if;
  if old.status <> new.status and not (
    (old.status = 'draft' and new.status = 'open') or
    (old.status = 'open' and new.status in ('finalized', 'cancelled'))
  ) then
    raise exception using errcode = 'P0001', message = 'INVALID_AUCTION_STATUS_TRANSITION';
  end if;
  if old.status <> 'draft' and old.selection_method <> new.selection_method then
    raise exception using errcode = 'P0001', message = 'AUCTION_METHOD_LOCKED_AFTER_OPENING';
  end if;
  if old.status = 'open' and new.status = 'open' and (
    new.winning_discount_paise is distinct from old.winning_discount_paise or
    new.commission_paise is distinct from old.commission_paise or
    new.prize_amount_paise is distinct from old.prize_amount_paise
  ) then
    raise exception using errcode = 'P0001', message = 'FINANCIAL_AMOUNTS_REQUIRE_FINALIZATION';
  end if;

  if new.winner_member_id is not null then
    if new.selection_method = 'auction' then
      select b.bid_discount_paise into submitted_discount
      from public.auction_bids b where b.auction_id = new.id and b.member_id = new.winner_member_id;
      if not found then raise exception using errcode = 'P0001', message = 'WINNER_MUST_HAVE_RECORDED_BID'; end if;
    elsif new.selection_method = 'lucky_draw' then
      if not exists (select 1 from public.lucky_draw_results d where d.auction_id = new.id and d.winner_member_id = new.winner_member_id) then
        raise exception using errcode = 'P0001', message = 'LUCKY_DRAW_RESULT_REQUIRED';
      end if;
    else
      raise exception using errcode = 'P0001', message = 'UNKNOWN_AUCTION_SELECTION_METHOD';
    end if;
    if exists (
      select 1 from public.auctions past
      where past.group_id = new.group_id and past.status = 'finalized' and past.winner_member_id = new.winner_member_id
    ) or not exists (
      select 1 from public.chit_members cm
      where cm.group_id = new.group_id and cm.member_id = new.winner_member_id and cm.status = 'active' and cm.has_won = false
    ) then
      raise exception using errcode = 'P0001', message = 'MEMBER_ALREADY_WON_IN_GROUP';
    end if;
  elsif new.status = 'finalized' then
    raise exception using errcode = 'P0001', message = 'FINALIZED_AUCTION_REQUIRES_WINNER';
  end if;

  if new.status = 'finalized' then
    if new.winning_discount_paise is null or new.commission_paise is null or new.auction_date is null then
      raise exception using errcode = 'P0001', message = 'AUCTION_DISCOUNT_COMMISSION_AND_DATE_REQUIRED';
    end if;
    select * into group_row from public.chit_groups where id = new.group_id;
    if new.winning_discount_paise + new.commission_paise > group_row.member_capacity::bigint * group_row.monthly_installment_paise then
      raise exception using errcode = 'P0001', message = 'AUCTION_DEDUCTIONS_EXCEED_GROSS_COLLECTION';
    end if;
    if new.prize_amount_paise is distinct from
      (group_row.member_capacity::bigint * group_row.monthly_installment_paise - new.winning_discount_paise - new.commission_paise) then
      raise exception using errcode = 'P0001', message = 'WINNER_PAYOUT_DOES_NOT_RECONCILE';
    end if;
    if new.winning_discount_paise / group_row.member_capacity > group_row.monthly_installment_paise then
      raise exception using errcode = 'P0001', message = 'DIVIDEND_EXCEEDS_BASE_INSTALLMENT';
    end if;
    new.finalized_at := now();
    new.finalized_by := (select auth.uid());
  end if;
  return new;
end;
$$;

create or replace function public.finalize_auction_winner(target_auction uuid, target_member uuid)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare
  auction_row public.auctions%rowtype;
  bid_amount bigint;
begin
  if not public.is_active_owner() then raise exception using errcode = '42501', message = 'OWNER_REQUIRED'; end if;
  select * into auction_row from public.auctions where id = target_auction for update;
  if not found then raise exception using errcode = 'P0001', message = 'AUCTION_NOT_FOUND'; end if;
  if auction_row.status <> 'open' or auction_row.selection_method <> 'auction' or auction_row.winner_member_id is not null then
    raise exception using errcode = 'P0001', message = 'AUCTION_NOT_OPEN_FOR_WINNER_SELECTION';
  end if;
  select b.bid_discount_paise into bid_amount from public.auction_bids b
  where b.auction_id = target_auction and b.member_id = target_member;
  if not found then raise exception using errcode = 'P0001', message = 'WINNER_MUST_HAVE_RECORDED_BID'; end if;
  update public.auctions set winner_member_id = target_member where id = target_auction;
  return bid_amount;
end;
$$;

create or replace function public.run_lucky_draw(target_auction uuid)
returns table (winner_member_id uuid, member_number integer, eligible_count integer)
language plpgsql security definer set search_path = ''
as $$
declare
  auction_row public.auctions%rowtype;
  eligible uuid[];
  eligible_total integer;
  token bytea;
  sample_value numeric;
  sample_limit numeric;
  chosen_index integer;
  chosen_member uuid;
  chosen_number integer;
  i integer;
begin
  if not public.is_active_owner() then raise exception using errcode = '42501', message = 'OWNER_REQUIRED'; end if;
  select * into auction_row from public.auctions where id = target_auction for update;
  if not found then raise exception using errcode = 'P0001', message = 'AUCTION_NOT_FOUND'; end if;
  if auction_row.status <> 'open' or auction_row.selection_method <> 'lucky_draw' or auction_row.winner_member_id is not null then
    raise exception using errcode = 'P0001', message = 'AUCTION_NOT_OPEN_FOR_LUCKY_DRAW';
  end if;
  perform 1 from public.chit_groups where id = auction_row.group_id for update;
  select array_agg(cm.member_id order by cm.member_number) into eligible
  from public.chit_members cm
  where cm.group_id = auction_row.group_id and cm.status = 'active' and not cm.has_won
    and not exists (select 1 from public.auctions past where past.group_id = cm.group_id and past.status = 'finalized' and past.winner_member_id = cm.member_id);
  eligible_total := coalesce(cardinality(eligible), 0);
  if eligible_total = 0 then raise exception using errcode = 'P0001', message = 'NO_ELIGIBLE_MEMBERS'; end if;
  sample_limit := trunc(power(2::numeric, 64) / eligible_total) * eligible_total;
  loop
    execute 'select extensions.gen_random_bytes(8)' into token;
    sample_value := 0;
    for i in 0..7 loop sample_value := sample_value * 256 + get_byte(token, i); end loop;
    exit when sample_value < sample_limit;
  end loop;
  chosen_index := mod(sample_value, eligible_total)::integer + 1;
  chosen_member := eligible[chosen_index];
  select cm.member_number into chosen_number from public.chit_members cm
  where cm.group_id = auction_row.group_id and cm.member_id = chosen_member;
  insert into public.lucky_draw_results (auction_id, group_id, winner_member_id, eligible_member_ids, selected_index, random_token, drawn_by)
  values (target_auction, auction_row.group_id, chosen_member, eligible, chosen_index, token, (select auth.uid()));
  update public.auctions set winner_member_id = chosen_member where id = target_auction;
  return query select chosen_member, chosen_number, eligible_total;
end;
$$;

create or replace function public.finalize_monthly_auction(
  target_auction uuid,
  discount_amount_paise bigint,
  commission_amount_paise bigint
)
returns table (winner_payout_paise bigint, dividend_per_member_paise bigint, dividend_remainder_paise integer)
language plpgsql security definer set search_path = ''
as $$
declare
  auction_row public.auctions%rowtype;
  group_row public.chit_groups%rowtype;
  gross_collection bigint;
  total_net_collection bigint;
  payout bigint;
  dividend_share bigint;
  dividend_remainder integer;
  maximum_share bigint;
begin
  if not public.is_active_owner() then raise exception using errcode = '42501', message = 'OWNER_REQUIRED'; end if;
  if discount_amount_paise < 0 or commission_amount_paise < 0 then
    raise exception using errcode = 'P0001', message = 'AUCTION_AMOUNTS_MUST_BE_NONNEGATIVE';
  end if;
  select * into auction_row from public.auctions where id = target_auction for update;
  if not found then raise exception using errcode = 'P0001', message = 'AUCTION_NOT_FOUND'; end if;
  if auction_row.status <> 'open' or auction_row.winner_member_id is null then
    raise exception using errcode = 'P0001', message = 'SELECT_WINNER_BEFORE_FINALIZATION';
  end if;
  select * into group_row from public.chit_groups where id = auction_row.group_id for update;
  gross_collection := group_row.member_capacity::bigint * group_row.monthly_installment_paise;
  payout := gross_collection - discount_amount_paise - commission_amount_paise;
  if payout < 0 then raise exception using errcode = 'P0001', message = 'AUCTION_DEDUCTIONS_EXCEED_GROSS_COLLECTION'; end if;
  total_net_collection := gross_collection - discount_amount_paise;
  dividend_share := discount_amount_paise / group_row.member_capacity;
  dividend_remainder := mod(discount_amount_paise, group_row.member_capacity)::integer;
  maximum_share := dividend_share;
  if dividend_remainder > 0 then maximum_share := dividend_share + 1; end if;
  if maximum_share > group_row.monthly_installment_paise then
    raise exception using errcode = 'P0001', message = 'DIVIDEND_EXCEEDS_BASE_INSTALLMENT';
  end if;
  if gross_collection <> total_net_collection + discount_amount_paise then
    raise exception using errcode = 'P0001', message = 'GROSS_COLLECTION_RECONCILIATION_FAILED';
  end if;
  if total_net_collection <> payout + commission_amount_paise then
    raise exception using errcode = 'P0001', message = 'AUCTION_FINANCIAL_RECONCILIATION_FAILED';
  end if;
  if commission_amount_paise <> group_row.commission_amount_paise then
    insert into public.auction_commission_overrides (auction_id, configured_amount_paise, applied_amount_paise, changed_by)
    values (auction_row.id, group_row.commission_amount_paise, commission_amount_paise, (select auth.uid()));
  end if;
  update public.auctions set
    winning_discount_paise = discount_amount_paise,
    commission_paise = commission_amount_paise,
    prize_amount_paise = payout,
    calculation_formula_version = null,
    calculation_chit_value_paise = null,
    calculation_remaining_months = null,
    calculation_commission_bps = null,
    status = 'finalized'
  where id = target_auction;
  return query select payout, dividend_share, dividend_remainder;
end;
$$;

create or replace function public.apply_auction_dividends(target_auction uuid, actor_id uuid)
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  auction_row public.auctions%rowtype;
  group_row public.chit_groups%rowtype;
  member_total integer;
  numbered_member_total integer;
  base_share bigint;
  maximum_share bigint;
  remainder_paise integer;
  inserted_count integer;
begin
  select * into auction_row from public.auctions where id = target_auction for update;
  if not found or auction_row.status <> 'finalized' then raise exception using errcode = 'P0001', message = 'FINALIZED_AUCTION_REQUIRED'; end if;
  if exists (select 1 from public.dividends d where d.auction_id = auction_row.id) then
    raise exception using errcode = 'P0001', message = 'AUCTION_DIVIDENDS_ALREADY_DISTRIBUTED';
  end if;
  select * into group_row from public.chit_groups where id = auction_row.group_id;
  select count(*) into member_total from public.chit_members cm where cm.group_id = auction_row.group_id and cm.status = 'active';
  select count(*) into numbered_member_total from public.chit_members cm where cm.group_id = auction_row.group_id and cm.status = 'active' and cm.member_number is not null;
  if member_total <> group_row.member_capacity or numbered_member_total <> member_total then
    raise exception using errcode = 'P0001', message = 'GROUP_ROSTER_INCOMPLETE';
  end if;
  base_share := auction_row.winning_discount_paise / member_total;
  remainder_paise := mod(auction_row.winning_discount_paise, member_total)::integer;
  maximum_share := base_share;
  if remainder_paise > 0 then maximum_share := base_share + 1; end if;
  if maximum_share > group_row.monthly_installment_paise then
    raise exception using errcode = 'P0001', message = 'DIVIDEND_EXCEEDS_BASE_INSTALLMENT';
  end if;
  insert into public.dividends (auction_id, member_id, dividend_amount_paise, created_by)
  select auction_row.id, cm.member_id,
    base_share + case when cm.member_number <= remainder_paise then 1 else 0 end, actor_id
  from public.chit_members cm where cm.group_id = auction_row.group_id and cm.status = 'active'
  order by cm.member_number;
  get diagnostics inserted_count = row_count;
  update public.installments i
  set dividend_credit_paise = d.dividend_amount_paise,
      net_due_paise = i.gross_amount_paise - d.dividend_amount_paise,
      status = case when i.gross_amount_paise = d.dividend_amount_paise then 'settled' else 'due' end
  from public.chit_members cm join public.dividends d on d.member_id = cm.member_id
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

revoke all on function public.apply_auction_dividends(uuid, uuid) from public, authenticated;
revoke all on function public.backfill_finalized_auction_dividends(uuid) from public, authenticated;
revoke all on function public.calculate_lucky_draw_amounts(bigint, integer, integer, integer) from public, authenticated;
revoke all on function public.finalize_monthly_auction(uuid, bigint, bigint) from public;
grant execute on function public.finalize_monthly_auction(uuid, bigint, bigint) to authenticated;
grant execute on function public.run_lucky_draw(uuid) to authenticated;
grant execute on function public.finalize_auction_winner(uuid, uuid) to authenticated;
