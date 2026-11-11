# Monthly calculation database design

## Monetary representation

All operational monetary values are stored as integer paise in PostgreSQL `bigint` columns. Application input is parsed from decimal rupees into paise; financial calculations use integer arithmetic. A group base installment is derived from chit value divided by configured duration and rounded to the nearest paise.

## Group configuration

`public.chit_groups` stores the individual chit value, member capacity, duration, derived base monthly installment and a fixed `commission_amount_paise`. The legacy `commission_bps` column remains only for migration compatibility and is not used for new calculations. Changes to the fixed group commission are written to `public.chit_group_commission_audit` with before/after amounts, actor and timestamp.

## Monthly auctions

`public.auctions` stores the group, month, auction date, selection method, selected winner, manually entered winning discount, commission snapshot, calculated winner payout and finalization actor/time. At auction creation, commission defaults from the group's fixed commission. An owner may override it during finalization; `public.auction_commission_overrides` records the configured and applied values.

Bid submission and Lucky Draw are winner-selection mechanisms. Neither computes an auction discount. Lucky Draw stores its candidate snapshot and random proof in `public.lucky_draw_results`, selects a winner, and leaves discount and commission entry for owner review before finalization.

## Dividends, installments and payments

For each finalized auction, `public.dividends` stores one member credit per active group member. Each credit is the manually entered discount divided equally among the full roster, including the winner. Any remaining paise are assigned by member number. Commission is excluded from the dividend pool.

`public.installments` stores each member's gross base installment, dividend credit, net due, period and due date. Finalizing an auction applies that period's credits to already generated installments; later generated installments read the saved dividend rows. `public.payments` records actual receipts separately and payment insertion requires a finalized monthly auction. A payment does not get inferred from a dividend credit.

`public.ledger_entries` records payment and dividend credits, plus balancing entries for permitted financial corrections. Prize disbursement remains separate from the calculated winner payout.

## Atomic finalization and authorization

The owner-only `public.finalize_monthly_auction` operation locks the auction and group, validates discount, commission, roster and payout bounds, checks the two monthly reconciliation equations, snapshots any commission override, then finalizes the auction. Database triggers distribute the dividend and update installment records in the same transaction. Existing finalized auction outcomes remain immutable.

RLS continues to scope business data to active owners or assigned staff. Financial writes that span multiple records are performed by security-definer functions with a pinned empty `search_path`; authenticated direct writes to derived dividend and installment records are restricted.
