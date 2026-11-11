-- Make prize disbursement recording atomic, idempotent, and available only
-- through the owner-checked RPC so each disbursement also reaches the ledger.
alter table public.prize_disbursements add column idempotency_key uuid;
update public.prize_disbursements
set idempotency_key = extensions.gen_random_uuid()
where idempotency_key is null;
alter table public.prize_disbursements alter column idempotency_key set not null;
alter table public.prize_disbursements
  add constraint prize_disbursements_idempotency_key_key unique (idempotency_key);

drop policy if exists "Owners record prize disbursements" on public.prize_disbursements;
revoke insert, update, delete on public.prize_disbursements from authenticated;
grant select on public.prize_disbursements to authenticated;

create or replace function public.record_prize_disbursement(
  target_auction uuid,
  amount_paise bigint,
  disbursement_date_value date,
  payment_method_value text,
  transaction_reference_value text,
  request_key uuid
)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  actor uuid := (select auth.uid());
  auction_row public.auctions%rowtype;
  existing public.prize_disbursements%rowtype;
  member_link uuid;
  already_disbursed bigint;
  disbursement_id uuid;
begin
  if actor is null or not public.is_active_owner() then
    raise exception using errcode = '42501', message = 'OWNER_REQUIRED';
  end if;
  if amount_paise is null or amount_paise <= 0 or request_key is null or disbursement_date_value is null then
    raise exception using errcode = 'P0001', message = 'PRIZE_AMOUNT_DATE_AND_REQUEST_KEY_REQUIRED';
  end if;
  if payment_method_value is null or payment_method_value not in ('cash', 'upi', 'bank_transfer') then
    raise exception using errcode = 'P0001', message = 'UNSUPPORTED_PAYMENT_METHOD';
  end if;
  if length(coalesce(transaction_reference_value, '')) > 120 then
    raise exception using errcode = 'P0001', message = 'PRIZE_REFERENCE_TOO_LONG';
  end if;

  perform pg_advisory_xact_lock(hashtext(request_key::text));
  select * into existing from public.prize_disbursements where idempotency_key = request_key;
  if found then
    if existing.auction_id <> target_auction
      or existing.amount_paise <> amount_paise
      or existing.disbursement_date <> disbursement_date_value
      or existing.payment_method is distinct from payment_method_value
      or existing.transaction_reference is distinct from nullif(transaction_reference_value, '') then
      raise exception using errcode = 'P0001', message = 'PRIZE_REQUEST_KEY_REUSED';
    end if;
    return existing.id;
  end if;

  select * into auction_row from public.auctions where id = target_auction for update;
  if not found then raise exception using errcode = 'P0001', message = 'AUCTION_NOT_FOUND'; end if;
  if auction_row.status <> 'finalized' or auction_row.prize_amount_paise is null then
    raise exception using errcode = 'P0001', message = 'FINALIZED_PRIZE_REQUIRED';
  end if;
  select cm.id into member_link
  from public.chit_members cm
  where cm.group_id = auction_row.group_id and cm.member_id = auction_row.winner_member_id;
  if not found then raise exception using errcode = 'P0001', message = 'PRIZE_WINNER_MEMBERSHIP_NOT_FOUND'; end if;

  select coalesce(sum(pd.amount_paise), 0) into already_disbursed
  from public.prize_disbursements pd where pd.auction_id = target_auction;
  if already_disbursed + amount_paise > auction_row.prize_amount_paise then
    raise exception using errcode = 'P0001', message = 'PRIZE_DISBURSEMENT_EXCEEDS_REMAINING';
  end if;

  insert into public.prize_disbursements (
    auction_id, chit_member_id, amount_paise, disbursement_date,
    payment_method, transaction_reference, recorded_by, idempotency_key
  ) values (
    target_auction, member_link, amount_paise, disbursement_date_value,
    payment_method_value, nullif(transaction_reference_value, ''), actor, request_key
  ) returning id into disbursement_id;

  insert into public.ledger_entries (
    chit_member_id, credit_paise, transaction_type, source_table,
    source_id, description, recorded_by
  ) values (
    member_link, amount_paise, 'prize_disbursement', 'prize_disbursements',
    disbursement_id, 'Prize disbursement', actor
  );
  return disbursement_id;
end;
$$;

revoke all on function public.record_prize_disbursement(uuid, bigint, date, text, text, uuid) from public;
grant execute on function public.record_prize_disbursement(uuid, bigint, date, text, text, uuid) to authenticated;

notify pgrst, 'reload schema';
