-- Allow an owner to discard an unstarted auction draft and any draft-only
-- selection records. Open and finalized auctions remain protected.
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
  if auction_row.status <> 'draft' then
    raise exception using errcode = 'P0001', message = 'ONLY_DRAFT_AUCTIONS_CAN_BE_DELETED';
  end if;

  delete from public.auction_bids where auction_id = target_auction;
  delete from public.lucky_draw_results where auction_id = target_auction;
  delete from public.auction_commission_overrides where auction_id = target_auction;
  delete from public.auctions where id = target_auction;
end;
$$;

revoke all on function public.delete_draft_auction(uuid, boolean) from public;
grant execute on function public.delete_draft_auction(uuid, boolean) to authenticated;

notify pgrst, 'reload schema';
