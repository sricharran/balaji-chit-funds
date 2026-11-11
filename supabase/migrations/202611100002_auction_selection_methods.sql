create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

alter table public.auctions
  add column selection_method text not null default 'auction'
  check (selection_method in ('auction', 'lucky_draw'));

alter table public.auctions drop constraint auctions_check;
alter table public.auctions add constraint auctions_finalized_winner_check
  check (status <> 'finalized' or (
    winner_member_id is not null and
    (selection_method = 'lucky_draw' or winning_discount_paise is not null)
  ));

create table public.lucky_draw_results (
  id uuid primary key default gen_random_uuid(),
  auction_id uuid not null unique,
  group_id uuid not null,
  winner_member_id uuid not null,
  eligible_member_ids uuid[] not null check (cardinality(eligible_member_ids) > 0),
  selected_index integer not null check (selected_index > 0),
  random_token bytea not null check (octet_length(random_token) = 8),
  drawn_by uuid not null references public.profiles(id),
  drawn_at timestamptz not null default now(),
  foreign key (auction_id, group_id) references public.auctions(id, group_id) on delete restrict,
  foreign key (group_id, winner_member_id) references public.chit_members(group_id, member_id) on delete restrict,
  check (selected_index <= cardinality(eligible_member_ids))
);

alter table public.lucky_draw_results enable row level security;
create policy "Users read accessible lucky draw results" on public.lucky_draw_results
  for select to authenticated using (public.can_access_group(group_id));
revoke all on public.lucky_draw_results from anon, authenticated;
grant select on public.lucky_draw_results to authenticated;

create or replace function public.validate_auction_period()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.chit_groups g
    where g.id = new.group_id and g.status = 'active' and new.month_number <= g.duration_months
  ) then
    raise exception using errcode = 'P0001', message = 'AUCTION_REQUIRES_ACTIVE_GROUP_AND_VALID_MONTH';
  end if;
  return new;
end;
$$;

create or replace function public.validate_auction_bid()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.auctions a
    join public.chit_members cm on cm.group_id = a.group_id and cm.member_id = new.member_id
    where a.id = new.auction_id and a.group_id = new.group_id
      and a.status = 'open' and a.selection_method = 'auction'
      and cm.has_won = false and cm.status = 'active'
      and not exists (
        select 1 from public.auctions past
        where past.group_id = a.group_id and past.status = 'finalized'
          and past.winner_member_id = cm.member_id
      )
  ) then
    raise exception using errcode = 'P0001', message = 'BIDDER_NOT_ELIGIBLE_FOR_AUCTION';
  end if;
  return new;
end;
$$;

create or replace function public.validate_lucky_draw_result()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  expected_eligible uuid[];
  sample_value numeric := 0;
  sample_limit numeric;
  i integer;
  candidate_count integer;
begin
  if not exists (
    select 1 from public.auctions a
    where a.id = new.auction_id and a.group_id = new.group_id
      and a.status = 'open' and a.selection_method = 'lucky_draw'
  ) then
    raise exception using errcode = 'P0001', message = 'LUCKY_DRAW_AUCTION_NOT_OPEN';
  end if;

  select array_agg(cm.member_id order by cm.member_number) into expected_eligible
  from public.chit_members cm
  where cm.group_id = new.group_id and cm.status = 'active' and cm.has_won = false
    and not exists (
      select 1 from public.auctions past
      where past.group_id = cm.group_id and past.status = 'finalized'
        and past.winner_member_id = cm.member_id
    );

  if expected_eligible is null or expected_eligible is distinct from new.eligible_member_ids then
    raise exception using errcode = 'P0001', message = 'LUCKY_DRAW_ELIGIBILITY_CHANGED';
  end if;
  candidate_count := cardinality(expected_eligible);
  if new.winner_member_id <> expected_eligible[new.selected_index] then
    raise exception using errcode = 'P0001', message = 'LUCKY_DRAW_WINNER_DOES_NOT_MATCH_SELECTION';
  end if;

  for i in 0..7 loop
    sample_value := sample_value * 256 + get_byte(new.random_token, i);
  end loop;
  sample_limit := trunc(power(2::numeric, 64) / candidate_count) * candidate_count;
  if sample_value >= sample_limit then
    raise exception using errcode = 'P0001', message = 'LUCKY_DRAW_RANDOM_TOKEN_OUT_OF_RANGE';
  end if;
  if mod(sample_value, candidate_count) + 1 <> new.selected_index then
    raise exception using errcode = 'P0001', message = 'LUCKY_DRAW_INDEX_DOES_NOT_MATCH_TOKEN';
  end if;
  return new;
end;
$$;

create trigger lucky_draw_results_validate
  before insert on public.lucky_draw_results
  for each row execute function public.validate_lucky_draw_result();

create or replace function public.guard_auction_changes()
returns trigger language plpgsql set search_path = ''
as $$
declare
  submitted_discount bigint;
begin
  if tg_op = 'DELETE' then
    if old.status = 'finalized' then
      raise exception 'Finalized auctions are immutable';
    end if;
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
    elsif new.selection_method = 'lucky_draw' then
      if new.winning_discount_paise is not null or not exists (
        select 1 from public.lucky_draw_results d
        where d.auction_id = new.id and d.winner_member_id = new.winner_member_id
      ) then
        raise exception using errcode = 'P0001', message = 'LUCKY_DRAW_RESULT_REQUIRED';
      end if;
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

create or replace function public.finalize_auction_winner(target_auction uuid, target_member uuid)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare
  auction_row public.auctions%rowtype;
  bid_amount bigint;
begin
  if not public.is_active_owner() then
    raise exception using errcode = '42501', message = 'OWNER_REQUIRED';
  end if;
  select * into auction_row from public.auctions where id = target_auction for update;
  if not found then raise exception using errcode = 'P0001', message = 'AUCTION_NOT_FOUND'; end if;
  if auction_row.status <> 'open' or auction_row.selection_method <> 'auction' then
    raise exception using errcode = 'P0001', message = 'AUCTION_NOT_OPEN_FOR_BID_WINNER';
  end if;
  perform 1 from public.chit_groups where id = auction_row.group_id for update;

  select b.bid_discount_paise into bid_amount
  from public.auction_bids b where b.auction_id = target_auction and b.member_id = target_member;
  if not found then raise exception using errcode = 'P0001', message = 'WINNER_MUST_HAVE_RECORDED_BID'; end if;
  if not exists (
    select 1 from public.chit_members cm
    where cm.group_id = auction_row.group_id and cm.member_id = target_member
      and cm.status = 'active' and cm.has_won = false
      and not exists (
        select 1 from public.auctions past where past.group_id = cm.group_id
          and past.status = 'finalized' and past.winner_member_id = cm.member_id
      )
  ) then
    raise exception using errcode = 'P0001', message = 'MEMBER_ALREADY_WON_IN_GROUP';
  end if;
  update public.auctions
  set winner_member_id = target_member, winning_discount_paise = bid_amount, status = 'finalized'
  where id = target_auction;
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
  if not public.is_active_owner() then
    raise exception using errcode = '42501', message = 'OWNER_REQUIRED';
  end if;
  select * into auction_row from public.auctions where id = target_auction for update;
  if not found then raise exception using errcode = 'P0001', message = 'AUCTION_NOT_FOUND'; end if;
  if auction_row.status <> 'open' or auction_row.selection_method <> 'lucky_draw' then
    raise exception using errcode = 'P0001', message = 'AUCTION_NOT_OPEN_FOR_LUCKY_DRAW';
  end if;
  perform 1 from public.chit_groups where id = auction_row.group_id for update;

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
  set winner_member_id = chosen_member, status = 'finalized'
  where id = target_auction;

  return query select chosen_member, chosen_number, eligible_total;
end;
$$;

revoke all on function public.finalize_auction_winner(uuid, uuid) from public;
revoke all on function public.run_lucky_draw(uuid) from public;
grant execute on function public.finalize_auction_winner(uuid, uuid) to authenticated;
grant execute on function public.run_lucky_draw(uuid) to authenticated;
