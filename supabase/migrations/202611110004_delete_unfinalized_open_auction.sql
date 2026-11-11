-- Permit an owner to discard a draft or open auction. Never remove an auction
-- once its month has financial history; bids and draw proof are removed with
-- the unfinalized auction after explicit confirmation.
create or replace function public.delete_draft_auction(target_auction uuid, acknowledged boolean)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  auction_row public.auctions%rowtype;
begin
  if not public.is_active_owner() then
    raise exception using errcode = '42501', message = 'OWNER_REQUIRED';
  end if;
  if acknowledged is distinct from true then
    raise exception using errcode = 'P0001', message = 'AUCTION_DELETE_ACKNOWLEDGEMENT_REQUIRED';
  end if;

  select * into auction_row from public.auctions where id = target_auction for update;
  if not found then raise exception using errcode = 'P0001', message = 'AUCTION_NOT_FOUND'; end if;
  if auction_row.status not in ('draft', 'open') then
    raise exception using errcode = 'P0001', message = 'ONLY_UNFINALIZED_AUCTIONS_CAN_BE_DELETED';
  end if;

  if exists (
    select 1 from public.installments i
    join public.chit_members cm on cm.id = i.chit_member_id
    join public.payments p on p.installment_id = i.id
    where cm.group_id = auction_row.group_id and i.month_number = auction_row.month_number
  ) or exists (
    select 1 from public.dividends d where d.auction_id = target_auction
  ) or exists (
    select 1 from public.prize_disbursements pd where pd.auction_id = target_auction
  ) then
    raise exception using errcode = 'P0001', message = 'AUCTION_HAS_FINANCIAL_HISTORY_CANNOT_BE_DELETED';
  end if;

  delete from public.auction_bids where auction_id = target_auction;
  delete from public.lucky_draw_results where auction_id = target_auction;
  delete from public.auction_commission_overrides where auction_id = target_auction;
  delete from public.auctions where id = target_auction;
end;
$$;

notify pgrst, 'reload schema';
