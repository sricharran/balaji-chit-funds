-- Expand the group/member foundation into the structure in the supplied ERD.
-- Money is stored in integer paise. This migration creates storage and access
-- rules only; it does not decide the unresolved auction/dividend formulas.

alter table public.chit_groups add column group_code text;
update public.chit_groups
set group_code = 'GRP-' || upper(substr(replace(id::text, '-', ''), 1, 12))
where group_code is null;
alter table public.chit_groups alter column group_code set not null;
alter table public.chit_groups alter column group_code
  set default ('GRP-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12)));
alter table public.chit_groups add constraint chit_groups_group_code_key unique (group_code);
alter table public.chit_groups add column commission_percentage numeric(5,2)
  generated always as (commission_bps::numeric / 100) stored;

-- Rename the existing group/member join table to match the ERD's CHIT_MEMBERS.
alter table public.group_members rename to chit_members;
alter index if exists public.group_members_group_id_idx rename to chit_members_group_id_idx;
alter index if exists public.group_members_member_id_idx rename to chit_members_member_id_idx;
alter table public.chit_members add column member_number integer check (member_number > 0);
alter table public.chit_members add column has_won boolean not null default false;
create unique index chit_members_group_number_key
  on public.chit_members(group_id, member_number) where member_number is not null;

drop policy if exists "Users read accessible enrollments" on public.chit_members;
drop policy if exists "Owners manage enrollments" on public.chit_members;
create policy "Users read accessible chit memberships" on public.chit_members
  for select to authenticated using (public.can_access_group(group_id));
create policy "Owners create chit memberships" on public.chit_members
  for insert to authenticated with check (public.is_active_owner());
revoke update, delete on public.chit_members from authenticated;
grant select, insert on public.chit_members to authenticated;

drop policy if exists "Assigned users read group members" on public.members;
create policy "Assigned users read group members" on public.members
  for select to authenticated using (
    public.is_active_owner() or exists (
      select 1 from public.chit_members cm
      where cm.member_id = members.id and public.can_access_group(cm.group_id)
    )
  );

create table public.auctions (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.chit_groups(id) on delete restrict,
  month_number integer not null check (month_number > 0),
  winning_discount_paise bigint check (winning_discount_paise >= 0),
  commission_paise bigint check (commission_paise >= 0),
  prize_amount_paise bigint check (prize_amount_paise >= 0),
  winner_member_id uuid,
  status text not null default 'draft' check (status in ('draft', 'open', 'finalized', 'cancelled')),
  finalized_at timestamptz,
  finalized_by uuid references public.profiles(id),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  unique (group_id, month_number),
  unique (id, group_id),
  unique (group_id, winner_member_id),
  foreign key (group_id, winner_member_id)
    references public.chit_members(group_id, member_id) on delete restrict,
  check (status <> 'finalized' or (winner_member_id is not null and winning_discount_paise is not null))
);
create index auctions_winner_idx on public.auctions(winner_member_id) where winner_member_id is not null;

create table public.auction_bids (
  id uuid primary key default gen_random_uuid(),
  auction_id uuid not null,
  group_id uuid not null,
  member_id uuid not null,
  bid_discount_paise bigint not null check (bid_discount_paise >= 0),
  submitted_at timestamptz not null default now(),
  recorded_by uuid not null references public.profiles(id),
  foreign key (auction_id, group_id) references public.auctions(id, group_id) on delete restrict,
  foreign key (group_id, member_id) references public.chit_members(group_id, member_id) on delete restrict,
  unique (auction_id, member_id)
);

create table public.dividends (
  id uuid primary key default gen_random_uuid(),
  auction_id uuid not null references public.auctions(id) on delete restrict,
  member_id uuid not null references public.members(id) on delete restrict,
  dividend_amount_paise bigint not null check (dividend_amount_paise >= 0),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  unique (auction_id, member_id)
);

create table public.installments (
  id uuid primary key default gen_random_uuid(),
  chit_member_id uuid not null references public.chit_members(id) on delete restrict,
  month_number integer not null check (month_number > 0),
  due_date date not null,
  gross_amount_paise bigint not null check (gross_amount_paise >= 0),
  dividend_credit_paise bigint not null default 0 check (dividend_credit_paise >= 0),
  net_due_paise bigint not null check (net_due_paise >= 0),
  status text not null default 'due' check (status in ('due', 'partially_paid', 'settled', 'waived')),
  created_at timestamptz not null default now(),
  unique (chit_member_id, month_number)
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  installment_id uuid not null references public.installments(id) on delete restrict,
  amount_paise bigint not null check (amount_paise > 0),
  payment_method text not null check (payment_method in ('cash', 'upi', 'bank_transfer')),
  payment_date date not null,
  transaction_reference text,
  idempotency_key uuid not null unique,
  recorded_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.prize_disbursements (
  id uuid primary key default gen_random_uuid(),
  auction_id uuid not null references public.auctions(id) on delete restrict,
  chit_member_id uuid not null references public.chit_members(id) on delete restrict,
  amount_paise bigint not null check (amount_paise > 0),
  disbursement_date date not null,
  payment_method text check (payment_method in ('cash', 'upi', 'bank_transfer')),
  transaction_reference text,
  recorded_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.ledger_entries (
  id uuid primary key default gen_random_uuid(),
  chit_member_id uuid not null references public.chit_members(id) on delete restrict,
  debit_paise bigint not null default 0 check (debit_paise >= 0),
  credit_paise bigint not null default 0 check (credit_paise >= 0),
  transaction_type text not null check (transaction_type in ('installment_due', 'payment', 'dividend', 'prize_disbursement', 'adjustment', 'reversal')),
  source_table text not null,
  source_id uuid not null,
  description text,
  recorded_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  check ((debit_paise > 0 and credit_paise = 0) or (credit_paise > 0 and debit_paise = 0)),
  unique (source_table, source_id, transaction_type)
);

create index auctions_group_status_idx on public.auctions(group_id, status);
create index auction_bids_auction_idx on public.auction_bids(auction_id);
create index dividends_member_idx on public.dividends(member_id);
create index installments_due_date_idx on public.installments(due_date, status);
create index payments_installment_date_idx on public.payments(installment_id, payment_date);
create index prize_disbursements_auction_idx on public.prize_disbursements(auction_id);
create index ledger_entries_member_created_idx on public.ledger_entries(chit_member_id, created_at);

create or replace function public.can_access_chit_member(target_chit_member uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.chit_members cm
    where cm.id = target_chit_member and public.can_access_group(cm.group_id)
  )
$$;

create or replace function public.can_access_installment(target_installment uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.installments i
    join public.chit_members cm on cm.id = i.chit_member_id
    where i.id = target_installment and public.can_access_group(cm.group_id)
  )
$$;

create or replace function public.guard_auction_changes()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if old.status = 'finalized' then
      raise exception 'Finalized auctions are immutable';
    end if;
    return old;
  end if;
  if tg_op = 'INSERT' and new.status <> 'draft' then
    raise exception 'Auctions must be created as drafts';
  end if;
  if tg_op = 'UPDATE' and old.status = 'finalized' then
    raise exception 'Finalized auctions are immutable';
  end if;
  if tg_op = 'UPDATE' and old.status <> new.status and not (
    (old.status = 'draft' and new.status in ('open', 'cancelled')) or
    (old.status = 'open' and new.status in ('finalized', 'cancelled'))
  ) then
    raise exception 'Invalid auction status transition';
  end if;
  if new.status = 'finalized' then
    if new.winner_member_id is null or new.winning_discount_paise is null then
      raise exception 'A finalized auction requires a winner and winning discount';
    end if;
    new.finalized_at := now();
    new.finalized_by := (select auth.uid());
  elsif new.winner_member_id is not null then
    raise exception 'A winner can only be recorded when finalizing an auction';
  end if;
  return new;
end;
$$;

create trigger auctions_guard_changes
  before insert or update or delete on public.auctions
  for each row execute function public.guard_auction_changes();

create or replace function public.validate_auction_period()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.chit_groups g
    where g.id = new.group_id and new.month_number <= g.duration_months
  ) then
    raise exception 'Auction month must be within the group duration';
  end if;
  return new;
end;
$$;

create trigger auctions_validate_period
  before insert or update of group_id, month_number on public.auctions
  for each row execute function public.validate_auction_period();

create or replace function public.validate_auction_bid()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.auctions a
    join public.chit_members cm on cm.group_id = a.group_id and cm.member_id = new.member_id
    where a.id = new.auction_id and a.group_id = new.group_id
      and a.status = 'open' and cm.has_won = false and cm.status = 'active'
  ) then
    raise exception 'Bidder must be an active, eligible member in an open auction';
  end if;
  return new;
end;
$$;

create trigger auction_bids_validate
  before insert or update on public.auction_bids
  for each row execute function public.validate_auction_bid();

create or replace function public.validate_dividend_recipient()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.auctions a
    join public.chit_members cm on cm.group_id = a.group_id and cm.member_id = new.member_id
    where a.id = new.auction_id and cm.status = 'active'
  ) then
    raise exception 'Dividend recipient must be an active member of the auction group';
  end if;
  return new;
end;
$$;

create trigger dividends_validate_recipient
  before insert or update on public.dividends
  for each row execute function public.validate_dividend_recipient();

create or replace function public.validate_prize_disbursement()
returns trigger language plpgsql set search_path = ''
as $$
declare
  allowed_amount bigint;
  already_disbursed bigint;
begin
  select a.prize_amount_paise into allowed_amount
  from public.auctions a
  join public.chit_members cm
    on cm.id = new.chit_member_id and cm.group_id = a.group_id and cm.member_id = a.winner_member_id
  where a.id = new.auction_id and a.status = 'finalized'
  for update of a;
  if not found then
    raise exception 'Disbursement must belong to the finalized auction winner';
  end if;
  if allowed_amount is not null then
    select coalesce(sum(pd.amount_paise), 0) into already_disbursed
    from public.prize_disbursements pd where pd.auction_id = new.auction_id;
    if already_disbursed + new.amount_paise > allowed_amount then
      raise exception 'Disbursement exceeds the recorded prize amount';
    end if;
  end if;
  return new;
end;
$$;

create trigger prize_disbursements_validate
  before insert or update on public.prize_disbursements
  for each row execute function public.validate_prize_disbursement();

create or replace function public.record_dividend_ledger_credit()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  member_link uuid;
  actor uuid := (select auth.uid());
begin
  if new.dividend_amount_paise > 0 then
    select cm.id into member_link
    from public.auctions a
    join public.chit_members cm on cm.group_id = a.group_id and cm.member_id = new.member_id
    where a.id = new.auction_id;
    insert into public.ledger_entries (
      chit_member_id, credit_paise, transaction_type, source_table, source_id, recorded_by
    ) values (member_link, new.dividend_amount_paise, 'dividend', 'dividends', new.id, actor);
  end if;
  return new;
end;
$$;

create trigger dividends_record_ledger_credit
  after insert on public.dividends
  for each row execute function public.record_dividend_ledger_credit();

create or replace function public.mark_auction_winner()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.status = 'finalized' and new.winner_member_id is not null then
    update public.chit_members
      set has_won = true
      where group_id = new.group_id and member_id = new.winner_member_id;
  end if;
  return new;
end;
$$;

create trigger auctions_mark_winner
  after insert or update of status, winner_member_id on public.auctions
  for each row execute function public.mark_auction_winner();

alter table public.auctions enable row level security;
alter table public.auction_bids enable row level security;
alter table public.dividends enable row level security;
alter table public.installments enable row level security;
alter table public.payments enable row level security;
alter table public.prize_disbursements enable row level security;
alter table public.ledger_entries enable row level security;

create policy "Users read accessible auctions" on public.auctions
  for select to authenticated using (public.can_access_group(group_id));
create policy "Owners create auctions" on public.auctions
  for insert to authenticated with check (public.is_active_owner() and created_by = (select auth.uid()));
create policy "Owners update auctions" on public.auctions
  for update to authenticated using (public.is_active_owner()) with check (public.is_active_owner());

create policy "Users read accessible bids" on public.auction_bids
  for select to authenticated using (public.can_access_group(group_id));
create policy "Assigned users record bids" on public.auction_bids
  for insert to authenticated with check (public.can_access_group(group_id) and recorded_by = (select auth.uid()));

create policy "Users read accessible dividends" on public.dividends
  for select to authenticated using (exists (
    select 1 from public.auctions a where a.id = auction_id and public.can_access_group(a.group_id)
  ));
create policy "Owners record dividends" on public.dividends
  for insert to authenticated with check (public.is_active_owner() and created_by = (select auth.uid()));

create policy "Users read accessible installments" on public.installments
  for select to authenticated using (public.can_access_chit_member(chit_member_id));
create policy "Owners create installments" on public.installments
  for insert to authenticated with check (public.is_active_owner());

create policy "Users read accessible payments" on public.payments
  for select to authenticated using (public.can_access_installment(installment_id));
create policy "Assigned users record payments" on public.payments
  for insert to authenticated with check (public.can_access_installment(installment_id) and recorded_by = (select auth.uid()));
drop policy "Assigned users record payments" on public.payments;

create policy "Users read accessible prize disbursements" on public.prize_disbursements
  for select to authenticated using (public.can_access_chit_member(chit_member_id));
create policy "Owners record prize disbursements" on public.prize_disbursements
  for insert to authenticated with check (public.is_active_owner() and recorded_by = (select auth.uid()));

create policy "Users read accessible ledger entries" on public.ledger_entries
  for select to authenticated using (public.can_access_chit_member(chit_member_id));

revoke all on public.auctions, public.auction_bids, public.dividends, public.installments,
  public.payments, public.prize_disbursements, public.ledger_entries from anon;
grant select, insert, update on public.auctions to authenticated;
grant select, insert on public.auction_bids, public.dividends, public.installments,
  public.prize_disbursements to authenticated;
grant select on public.payments to authenticated;
grant select on public.ledger_entries to authenticated;

-- Payment plus corresponding member-ledger credit is one database transaction.
create or replace function public.record_payment(
  target_installment uuid,
  payment_amount_paise bigint,
  payment_method_value text,
  payment_date_value date,
  transaction_reference_value text,
  request_key uuid
)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  actor uuid := (select auth.uid());
  payment_id uuid;
  existing public.payments%rowtype;
  member_link uuid;
begin
  perform pg_advisory_xact_lock(hashtext(coalesce(request_key::text, '')));
  if actor is null or not public.can_access_installment(target_installment) then
    raise exception 'Not authorized to record payment for this installment';
  end if;
  if payment_amount_paise <= 0 or request_key is null then
    raise exception 'Payment amount and idempotency key must be valid';
  end if;
  if payment_method_value is null or payment_method_value not in ('cash', 'upi', 'bank_transfer') then
    raise exception 'Unsupported payment method';
  end if;

  select * into existing from public.payments where idempotency_key = request_key;
  if found then
    if existing.installment_id <> target_installment
      or existing.amount_paise <> payment_amount_paise
      or existing.payment_method <> payment_method_value
      or existing.payment_date <> payment_date_value
      or existing.transaction_reference is distinct from transaction_reference_value then
      raise exception 'Idempotency key was already used for a different payment';
    end if;
    return existing.id;
  end if;

  select i.chit_member_id into member_link
  from public.installments i where i.id = target_installment;
  insert into public.payments (
    installment_id, amount_paise, payment_method, payment_date,
    transaction_reference, idempotency_key, recorded_by
  ) values (
    target_installment, payment_amount_paise, payment_method_value, payment_date_value,
    transaction_reference_value, request_key, actor
  ) returning id into payment_id;

  insert into public.ledger_entries (
    chit_member_id, credit_paise, transaction_type, source_table, source_id, recorded_by
  ) values (member_link, payment_amount_paise, 'payment', 'payments', payment_id, actor);
  return payment_id;
end;
$$;

revoke all on function public.record_payment(uuid, bigint, text, date, text, uuid) from public;
grant execute on function public.record_payment(uuid, bigint, text, date, text, uuid) to authenticated;
