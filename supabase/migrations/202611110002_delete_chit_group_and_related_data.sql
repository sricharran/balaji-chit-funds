-- Owner-only permanent removal of one chit group and its operational history.
-- Auction immutability is bypassed only inside this validated deletion RPC.

create or replace function public.guard_auction_changes()
returns trigger language plpgsql set search_path = ''
as $$
declare
  group_row public.chit_groups%rowtype;
  submitted_discount bigint;
begin
  if tg_op = 'DELETE' then
    if current_setting('app.group_delete_in_progress', true) = old.group_id::text then
      return old;
    end if;
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

create or replace function public.delete_chit_group(target_group uuid, confirmation_code text, acknowledged boolean)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  group_row public.chit_groups%rowtype;
begin
  if not public.is_active_owner() then
    raise exception using errcode = '42501', message = 'OWNER_REQUIRED';
  end if;
  if acknowledged is distinct from true then
    raise exception using errcode = 'P0001', message = 'GROUP_DELETE_ACKNOWLEDGEMENT_REQUIRED';
  end if;

  select * into group_row from public.chit_groups where id = target_group for update;
  if not found then raise exception using errcode = 'P0001', message = 'GROUP_NOT_FOUND'; end if;
  if confirmation_code is distinct from group_row.group_code then
    raise exception using errcode = 'P0001', message = 'GROUP_CODE_CONFIRMATION_MISMATCH';
  end if;

  delete from public.chit_group_commission_audit where group_id = target_group;
  delete from public.auction_commission_overrides
  where auction_id in (select a.id from public.auctions a where a.group_id = target_group);
  delete from public.lucky_draw_results where group_id = target_group;
  delete from public.auction_bids where group_id = target_group;
  delete from public.dividends
  where auction_id in (select a.id from public.auctions a where a.group_id = target_group);
  delete from public.payments p
  using public.installments i, public.chit_members cm
  where p.installment_id = i.id and i.chit_member_id = cm.id and cm.group_id = target_group;
  delete from public.ledger_entries le
  using public.chit_members cm
  where le.chit_member_id = cm.id and cm.group_id = target_group;
  delete from public.prize_disbursements pd
  where pd.auction_id in (select a.id from public.auctions a where a.group_id = target_group)
     or pd.chit_member_id in (select cm.id from public.chit_members cm where cm.group_id = target_group);
  delete from public.installments i
  using public.chit_members cm
  where i.chit_member_id = cm.id and cm.group_id = target_group;

  perform set_config('app.group_delete_in_progress', target_group::text, true);
  delete from public.auctions where group_id = target_group;

  delete from public.chit_members where group_id = target_group;
  delete from public.chit_groups where id = target_group;

  -- Member directory records are shared across groups. Remove only records
  -- that became unassigned and have no remaining dividend history.
  delete from public.members m
  where not exists (select 1 from public.chit_members cm where cm.member_id = m.id)
    and not exists (select 1 from public.dividends d where d.member_id = m.id);
end;
$$;

revoke all on function public.delete_chit_group(uuid, text, boolean) from public;
grant execute on function public.delete_chit_group(uuid, text, boolean) to authenticated;

notify pgrst, 'reload schema';
