-- Lucky Draw v2 stores its discount field as discount + 4% commission.
-- Do not add the separately stored commission a second time to dividends.
-- Bid auctions continue to use bid discount + 4% commission.

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
  existing_dividend_total integer;
  base_share bigint;
  maximum_share bigint;
  remainder_paise integer;
  inserted_count integer;
  distribution_row record;
  adjustment_amount bigint;
begin
  select * into auction_row from public.auctions where id = target_auction for update;
  if not found then raise exception using errcode = 'P0001', message = 'FINALIZED_AUCTION_REQUIRED'; end if;
  if auction_row.status <> 'finalized' then
    raise exception using errcode = 'P0001', message = 'FINALIZED_AUCTION_REQUIRED';
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

  if auction_row.selection_method = 'lucky_draw' then
    distribution_pool := auction_row.winning_discount_paise;
  else
    distribution_pool := auction_row.winning_discount_paise + commission_amount;
  end if;

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

  select count(*) into existing_dividend_total from public.dividends d where d.auction_id = auction_row.id;
  if existing_dividend_total = 0 then
    insert into public.dividends (auction_id, member_id, dividend_amount_paise, created_by)
    select auction_row.id, cm.member_id,
      base_share + case when cm.member_number <= remainder_paise then 1 else 0 end,
      actor_id
    from public.chit_members cm
    where cm.group_id = auction_row.group_id and cm.status = 'active'
    order by cm.member_number;
    get diagnostics inserted_count = row_count;
  else
    if existing_dividend_total <> member_total then
      raise exception using errcode = 'P0001', message = 'PARTIAL_DIVIDEND_DISTRIBUTION_REQUIRES_REVIEW';
    end if;
    for distribution_row in
      select d.id as dividend_id, d.dividend_amount_paise as previous_amount,
        cm.id as chit_member_id,
        base_share + case when cm.member_number <= remainder_paise then 1 else 0 end as corrected_amount
      from public.dividends d
      join public.chit_members cm on cm.member_id = d.member_id and cm.group_id = auction_row.group_id
      where d.auction_id = auction_row.id and cm.status = 'active'
      order by cm.member_number
    loop
      adjustment_amount := distribution_row.corrected_amount - distribution_row.previous_amount;
      if adjustment_amount <> 0 then
        insert into public.ledger_entries (
          chit_member_id, debit_paise, credit_paise, transaction_type,
          source_table, source_id, description, recorded_by
        ) values (
          distribution_row.chit_member_id,
          greatest(-adjustment_amount, 0), greatest(adjustment_amount, 0),
          'adjustment', 'dividend_corrections', extensions.gen_random_uuid(),
          'Corrected duplicate commission in the Lucky Draw dividend pool', actor_id
        );
        update public.dividends set dividend_amount_paise = distribution_row.corrected_amount
        where id = distribution_row.dividend_id;
      end if;
    end loop;
    inserted_count := existing_dividend_total;
  end if;

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

revoke all on function public.apply_auction_dividends(uuid, uuid) from public, authenticated;
