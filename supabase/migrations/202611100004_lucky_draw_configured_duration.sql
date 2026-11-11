-- Lucky Draw remaining months follow each group's configured chit duration.
-- The formula version changes so existing calculation snapshots remain clear.

create or replace function public.calculate_lucky_draw_amounts(
  chit_value_paise bigint,
  winning_month_number integer,
  group_duration_months integer,
  configured_commission_bps integer
)
returns table (
  remaining_months integer,
  winning_discount_paise bigint,
  commission_paise bigint,
  prize_amount_paise bigint
)
language plpgsql immutable set search_path = ''
as $$
declare
  discount_numerator numeric;
  commission_numerator numeric;
begin
  if chit_value_paise <= 0 then
    raise exception using errcode = 'P0001', message = 'LUCKY_DRAW_INVALID_CHIT_VALUE';
  end if;
  if group_duration_months <= 0 or winning_month_number < 1 or winning_month_number > group_duration_months then
    raise exception using errcode = 'P0001', message = 'LUCKY_DRAW_INVALID_MONTH';
  end if;
  if configured_commission_bps <> 400 then
    raise exception using errcode = 'P0001', message = 'LUCKY_DRAW_RULE_REQUIRES_4_PERCENT_COMMISSION';
  end if;

  remaining_months := group_duration_months - winning_month_number;
  discount_numerator := chit_value_paise::numeric * (remaining_months + 4);
  commission_numerator := chit_value_paise::numeric * 4;
  if mod(discount_numerator, 100) <> 0 or mod(commission_numerator, 100) <> 0 then
    raise exception using errcode = 'P0001', message = 'LUCKY_DRAW_AMOUNT_REQUIRES_SUB_PAISE_ROUNDING';
  end if;

  winning_discount_paise := (discount_numerator / 100)::bigint;
  commission_paise := (commission_numerator / 100)::bigint;
  prize_amount_paise := chit_value_paise - winning_discount_paise;
  if winning_discount_paise < commission_paise or prize_amount_paise < 0 then
    raise exception using errcode = 'P0001', message = 'LUCKY_DRAW_CALCULATION_OUT_OF_RANGE';
  end if;
  return next;
end;
$$;

create or replace function public.guard_auction_changes()
returns trigger language plpgsql set search_path = ''
as $$
declare
  submitted_discount bigint;
  chit_value bigint;
  group_duration integer;
  configured_commission integer;
  calculation record;
begin
  if tg_op = 'DELETE' then
    if old.status = 'finalized' then raise exception 'Finalized auctions are immutable'; end if;
    return old;
  end if;
  if tg_op = 'INSERT' and new.status <> 'draft' then
    raise exception using errcode = 'P0001', message = 'AUCTIONS_MUST_START_AS_DRAFTS';
  end if;
  if tg_op = 'UPDATE' and old.status = 'finalized' then
    raise exception 'Finalized auctions are immutable';
  end if;
  if tg_op = 'UPDATE' and old.status <> new.status and not (
    (old.status = 'draft' and new.status = 'open') or
    (old.status = 'open' and new.status in ('finalized', 'cancelled'))
  ) then
    raise exception using errcode = 'P0001', message = 'INVALID_AUCTION_STATUS_TRANSITION';
  end if;
  if tg_op = 'UPDATE' and old.status <> 'draft' and old.selection_method <> new.selection_method then
    raise exception using errcode = 'P0001', message = 'AUCTION_METHOD_LOCKED_AFTER_OPENING';
  end if;

  if new.status = 'finalized' then
    if new.winner_member_id is null then
      raise exception using errcode = 'P0001', message = 'FINALIZED_AUCTION_REQUIRES_WINNER';
    end if;
    if new.selection_method = 'auction' then
      select b.bid_discount_paise into submitted_discount
      from public.auction_bids b
      where b.auction_id = new.id and b.member_id = new.winner_member_id;
      if not found or new.winning_discount_paise is distinct from submitted_discount then
        raise exception using errcode = 'P0001', message = 'AUCTION_WINNER_REQUIRES_RECORDED_BID';
      end if;
      if new.commission_paise is not null or new.prize_amount_paise is not null
        or new.calculation_formula_version is not null
        or new.calculation_chit_value_paise is not null
        or new.calculation_remaining_months is not null
        or new.calculation_commission_bps is not null then
        raise exception using errcode = 'P0001', message = 'AUCTION_FINANCIAL_FORMULA_NOT_CONFIGURED';
      end if;
    elsif new.selection_method = 'lucky_draw' then
      if not exists (
        select 1 from public.lucky_draw_results d
        where d.auction_id = new.id and d.winner_member_id = new.winner_member_id
      ) then
        raise exception using errcode = 'P0001', message = 'LUCKY_DRAW_RESULT_REQUIRED';
      end if;
      select g.chit_value_paise, g.duration_months, g.commission_bps
      into chit_value, group_duration, configured_commission
      from public.chit_groups g where g.id = new.group_id;
      select * into calculation from public.calculate_lucky_draw_amounts(
        chit_value, new.month_number, group_duration, configured_commission
      );
      if new.calculation_formula_version is distinct from 'balaji_lucky_draw_v2'
        or new.calculation_chit_value_paise is distinct from chit_value
        or new.calculation_remaining_months is distinct from calculation.remaining_months
        or new.calculation_commission_bps is distinct from 400
        or new.winning_discount_paise is distinct from calculation.winning_discount_paise
        or new.commission_paise is distinct from calculation.commission_paise
        or new.prize_amount_paise is distinct from calculation.prize_amount_paise then
        raise exception using errcode = 'P0001', message = 'LUCKY_DRAW_CALCULATION_DOES_NOT_MATCH_RULE';
      end if;
    else
      raise exception using errcode = 'P0001', message = 'UNKNOWN_AUCTION_SELECTION_METHOD';
    end if;

    if exists (
      select 1 from public.auctions past
      where past.group_id = new.group_id and past.status = 'finalized'
        and past.winner_member_id = new.winner_member_id
    ) then
      raise exception using errcode = 'P0001', message = 'MEMBER_ALREADY_WON_IN_GROUP';
    end if;
    if not exists (
      select 1 from public.chit_members cm
      where cm.group_id = new.group_id and cm.member_id = new.winner_member_id
        and cm.status = 'active' and cm.has_won = false
    ) then
      raise exception using errcode = 'P0001', message = 'WINNER_NOT_ELIGIBLE';
    end if;
    new.finalized_at := now();
    new.finalized_by := (select auth.uid());
  elsif new.winner_member_id is not null then
    raise exception using errcode = 'P0001', message = 'WINNER_REQUIRES_FINALIZED_AUCTION';
  end if;
  return new;
end;
$$;

create or replace function public.run_lucky_draw(target_auction uuid)
returns table (winner_member_id uuid, member_number integer, eligible_count integer)
language plpgsql security definer set search_path = ''
as $$
declare
  auction_row public.auctions%rowtype;
  group_row public.chit_groups%rowtype;
  eligible uuid[];
  eligible_total integer;
  token bytea;
  sample_value numeric;
  sample_limit numeric;
  chosen_index integer;
  chosen_member uuid;
  chosen_number integer;
  formula record;
  i integer;
begin
  if not public.is_active_owner() then
    raise exception using errcode = '42501', message = 'OWNER_REQUIRED';
  end if;
  select * into auction_row from public.auctions where id = target_auction for update;
  if not found then raise exception using errcode = 'P0001', message = 'AUCTION_NOT_FOUND'; end if;
  if auction_row.status <> 'open' or auction_row.selection_method <> 'lucky_draw' then
    raise exception using errcode = 'P0001', message = 'AUCTION_NOT_OPEN_FOR_LUCKY_DRAW';
  end if;
  select * into group_row from public.chit_groups where id = auction_row.group_id for update;
  select * into formula from public.calculate_lucky_draw_amounts(
    group_row.chit_value_paise, auction_row.month_number,
    group_row.duration_months, group_row.commission_bps
  );

  select array_agg(cm.member_id order by cm.member_number)
  into eligible
  from public.chit_members cm
  where cm.group_id = auction_row.group_id and cm.status = 'active' and cm.has_won = false
    and not exists (
      select 1 from public.auctions past where past.group_id = cm.group_id
        and past.status = 'finalized' and past.winner_member_id = cm.member_id
    );
  eligible_total := coalesce(cardinality(eligible), 0);
  if eligible_total = 0 then raise exception using errcode = 'P0001', message = 'NO_ELIGIBLE_MEMBERS'; end if;

  sample_limit := trunc(power(2::numeric, 64) / eligible_total) * eligible_total;
  loop
    if to_regprocedure('extensions.gen_random_bytes(integer)') is not null then
      execute 'select extensions.gen_random_bytes(8)' into token;
    else
      execute 'select public.gen_random_bytes(8)' into token;
    end if;
    sample_value := 0;
    for i in 0..7 loop
      sample_value := sample_value * 256 + get_byte(token, i);
    end loop;
    exit when sample_value < sample_limit;
  end loop;
  chosen_index := mod(sample_value, eligible_total)::integer + 1;
  chosen_member := eligible[chosen_index];

  select cm.member_number into chosen_number
  from public.chit_members cm
  where cm.group_id = auction_row.group_id and cm.member_id = chosen_member;

  insert into public.lucky_draw_results (
    auction_id, group_id, winner_member_id, eligible_member_ids,
    selected_index, random_token, drawn_by
  ) values (
    target_auction, auction_row.group_id, chosen_member, eligible,
    chosen_index, token, (select auth.uid())
  );
  update public.auctions
  set winner_member_id = chosen_member,
      winning_discount_paise = formula.winning_discount_paise,
      commission_paise = formula.commission_paise,
      prize_amount_paise = formula.prize_amount_paise,
      calculation_formula_version = 'balaji_lucky_draw_v2',
      calculation_chit_value_paise = group_row.chit_value_paise,
      calculation_remaining_months = formula.remaining_months,
      calculation_commission_bps = 400,
      status = 'finalized'
  where id = target_auction;

  return query select chosen_member, chosen_number, eligible_total;
end;
$$;
