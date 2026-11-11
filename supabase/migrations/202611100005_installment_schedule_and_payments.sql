alter table public.installments add column created_by uuid references public.profiles(id);

revoke insert on public.installments from authenticated;

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
  where group_id = target_group and status = 'active' and member_number is not null;
  if active_count <> group_row.member_capacity then
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
    0, group_row.monthly_installment_paise, 'due', (select auth.uid())
  from public.chit_members cm
  where cm.group_id = target_group and cm.status = 'active';
  get diagnostics inserted_count = row_count;
  return inserted_count;
end;
$$;

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
  installment_row public.installments%rowtype;
  member_link uuid;
  already_paid bigint;
begin
  perform pg_advisory_xact_lock(hashtext(coalesce(request_key::text, '')));
  if actor is null or not public.can_access_installment(target_installment) then
    raise exception using errcode = '42501', message = 'PAYMENT_NOT_AUTHORIZED';
  end if;
  if payment_amount_paise <= 0 or request_key is null then
    raise exception using errcode = 'P0001', message = 'PAYMENT_AMOUNT_AND_REQUEST_KEY_REQUIRED';
  end if;
  if payment_method_value is null or payment_method_value not in ('cash', 'upi', 'bank_transfer') then
    raise exception using errcode = 'P0001', message = 'UNSUPPORTED_PAYMENT_METHOD';
  end if;

  select * into existing from public.payments where idempotency_key = request_key;
  if found then
    if existing.installment_id <> target_installment
      or existing.amount_paise <> payment_amount_paise
      or existing.payment_method <> payment_method_value
      or existing.payment_date <> payment_date_value
      or existing.transaction_reference is distinct from transaction_reference_value then
      raise exception using errcode = 'P0001', message = 'PAYMENT_REQUEST_KEY_REUSED';
    end if;
    return existing.id;
  end if;

  select * into installment_row from public.installments
  where id = target_installment for update;
  if not found then raise exception using errcode = 'P0001', message = 'INSTALLMENT_NOT_FOUND'; end if;

  select coalesce(sum(p.amount_paise), 0) into already_paid
  from public.payments p where p.installment_id = target_installment;
  if already_paid + payment_amount_paise > installment_row.net_due_paise then
    raise exception using errcode = 'P0001', message = 'PAYMENT_EXCEEDS_INSTALLMENT_BALANCE';
  end if;

  member_link := installment_row.chit_member_id;
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

  update public.installments
  set status = case
    when already_paid + payment_amount_paise = net_due_paise then 'settled'
    else 'partially_paid'
  end
  where id = target_installment;

  return payment_id;
end;
$$;

revoke all on function public.generate_group_installments(uuid, integer, date) from public;
grant execute on function public.generate_group_installments(uuid, integer, date) to authenticated;
