# Acceptance Criteria

Draft, implementation-independent outcomes. Each criterion is associated with a story in [USER_STORIES.md](USER_STORIES.md). Rules marked unresolved must be decided before the related financial behavior can be accepted as production-ready.

## E1 — Dashboard

### AC-001 (US-001)
- Dashboard shows active group count, registered member count, upcoming auctions, collection total for a stated period, pending member payments, outstanding balances, prize payable pending disbursement and recent transactions.
- Every figure is derived from recorded records and indicates its time period/as-of context.
- Collections, dividend credits, receivables, prize payable and prize disbursed are not combined into a single unlabeled measure.
- A user without permission cannot see data outside their authorized scope.

### AC-002 (US-002)
- Upcoming auction entries identify group and scheduled period/date; recent activity identifies event type, date and relevant group/member where permitted.
- Lists reflect persisted records and respect role/group access.
- Missing schedule or transaction data is presented as missing, not fabricated.

## E2 — Groups

### AC-003 (US-003)
- Owner can define and save scheme value, duration, member capacity and a fixed monetary commission per auction; base installment is derived as chit value divided by duration.
- A changed group commission requires an active owner and stores its before/after amounts, actor and timestamp.
- The three initial examples can be represented as configurations and are not fixed system constants.
- Invalid or incomplete values are rejected with field-specific explanation; currency/rate precision policy is explicit before activation.
- Scheme changes do not silently rewrite terms already used by a group.

### AC-004 (US-004)
- Owner can create a group with a unique business identifier and selected/configured terms.
- Group remains inactive/draft until all required configuration and activation checks pass.
- Activation records effective terms and actor/time; failed validation identifies each unmet condition.
- A group cannot be activated beyond its configured member capacity or with an invalid duration/financial configuration, once limits are approved.

### AC-005 (US-005)
- Authorized user can view group status, roster, current period and completed auction/month progress.
- Member and financial details are scoped to the group and permission.
- Progress is derived from recorded enrollment and auction records; incomplete periods are visibly incomplete.

### AC-006 (US-006)
- Owner can distinguish active and completed groups and see lifecycle changes.
- Changes to terms/status retain prior values, actor and timestamp.
- Whether and how active terms can be amended is not assumed; amendment is unavailable or blocked pending an approved policy.

## E3 — Members

### AC-007 (US-007)
- Owner can create a member with required approved identity/contact fields and later update allowed fields.
- Searchable name and phone fields are retained; validation and duplicate warnings follow an approved matching policy.
- Creation and updates retain actor, timestamp and changed fields.
- Unprivileged users cannot modify member records.

### AC-008 (US-008)
- Owner can enroll a registered member in a group and view enrollment status.
- A member may hold enrollments in multiple groups; group balances and payment histories remain separate.
- Enrollment cannot exceed group capacity or violate approved timing/status rules.
- Enrollment changes retain effective date and audit information.

### AC-009 (US-009)
- Statement is selectable by member and group and shows period-by-period gross due, dividend credits, actual payments, balance, auction win and prize-disbursement information as separate entries.
- Totals reconcile to the displayed entries under the approved posting/allocation policy.
- Statements do not combine a credit with cash collected and do not imply prize award means disbursement.
- Access follows group permissions.

### AC-010 (US-010)
- Authorized user can search by name or phone and see matching member records.
- Search results honor group/data permissions and do not reveal unauthorized enrollments or balances.
- No-match and ambiguous-match outcomes are clearly represented; duplicate resolution follows approved policy.

## E4 — Auctions

### AC-011 (US-011)
- Authorized user can create an auction associated with exactly one group and scheduled period.
- The same group-period cannot have multiple active/finalized auctions unless an approved exception rule allows it.
- Auction has visible lifecycle state and cannot be finalized without required outcome fields.
- Date, schedule and no-auction/reschedule policies are enforced once approved.

### AC-012 (US-012)
- Eligible list includes only enrolled members meeting the approved eligibility policy.
- A prior winner in the same group is excluded from winning again; a win in a different group does not automatically exclude them.
- Eligibility explanation is available to operator; unpaid/default status does not affect eligibility until policy is approved.

### AC-013 (US-013)
- Authorized operator can record a bid against an open auction and enrolled bidder, retaining bid amount and submission record.
- Invalid, negative or out-of-policy bid values are rejected according to approved bid bounds.
- Before finalization, authorized user can review the complete persisted bid set and identify edits/corrections.
- Bid corrections are auditable; bid ordering/tie rules are applied only after approved.

### AC-014 (US-014)
- Only an owner can finalize an open auction after selecting an eligible winner and manually entering the monthly discount and commission.
- Bid winner selection and Lucky Draw select a winner only; neither calculates the monthly discount.
- Finalization is atomic: winner, discount, commission snapshot, payout, member dividends, net installments and state are all recorded, or none are.
- Commission defaults from group configuration; any override is owner-authorized and audited.
- A second winner for the same group is rejected; repeated submission cannot create duplicate results.
- Finalized outcome cannot be silently overwritten; correction/reopening policy and audit requirements apply.
- No-bid, tie and invalid-bid cases follow explicitly approved rules.

### AC-015 (US-015)
- Calculation accepts validated exact currency inputs and uses no binary floating-point money arithmetic.
- Dividend pool equals auction discount only; commission is retained and excluded from member dividends.
- Every member, including the winner, receives an equal same-month dividend credit. Paise remainders are assigned by member number.
- Net installment is base installment minus dividend credit; winner payout is gross collection minus discount and commission.
- Both monthly reconciliation equations pass before finalization.
- Negative, inconsistent or out-of-range results are rejected or require an explicitly approved exception flow.
- Business owner validates results against historical examples before production use.

### AC-016 (US-016)
- Authorized user can inspect finalized auction history by group/period with actual discount, winner and saved calculation snapshot.
- Historical results remain stable when future scheme settings change.
- Unfinalized/corrected records are visibly labeled and audit history is available to authorized users.

## E5 — Payments

### AC-017 (US-017)
- Due view lists member, group and period and distinguishes gross installment, discount-only dividend credit, net payable, actual cash paid and remaining due.
- Winners continue to have installments generated/visible after winning.
- Balance calculation and credit timing follow approved policy; no unapproved offset is applied.

### AC-018 (US-018)
- Authorized user can record full or partial payment with member, group, period/allocation, amount, date and method.
- Payment method supports cash, UPI and bank transfer; applicable transaction/reference details can be recorded.
- Invalid amount, invalid allocation, unauthorized group, or duplicate submission is rejected without partial persistence.
- Successful entry updates payment history and balance atomically and retains actor/time.
- Actual payment is recorded separately from dividend credits.

### AC-019 (US-019)
- Only authorized role can correct a payment and must provide a reason.
- Original payment remains visible and linked to its correction/reversal; audit record identifies before/after values, actor and time.
- Corrected balances and reports reconcile without erasing collection history.

### AC-020 (US-020)
- Dividend credit is recorded as a distinct financial event with source auction, member/group, amount and applicable period.
- Credit eligibility, timing, amount and allocation conform to approved policy.
- Credit alone never increases actual cash-collected totals or marks a cash payment as received.
- Credit history and remaining due reconcile under the approved rounding/rollover rules.

### AC-021 (US-021)
- Receipt is generated only for a persisted payment and identifies payment, payer/member, group, amount, date and method.
- Reprinting a receipt references the same payment and does not create another transaction.
- Corrections/reversals are reflected or linked so an obsolete receipt cannot misrepresent the current record.

### AC-022 (US-022)
- Authorized user can filter payment collections by date range and method.
- Result totals include actual payment records only; dividend credits are separately identifiable.
- Filters and totals use consistent date/time and currency rules and honor access permissions.

## E6 — Prize distribution

### AC-023 (US-023)
- A prize payable is available only for a finalized auction outcome under the approved calculation policy.
- View separates gross award/payable, approved amount, disbursed amount and remaining payable.
- Calculation inputs and approval state are visible to authorized owner.
- Winning does not automatically create a disbursement record.

### AC-024 (US-024)
- Authorized approver records approval and one or more disbursements with amount, date, method and transaction reference as applicable.
- Disbursement cannot exceed remaining approved payable absent an approved exception.
- Partial payments update remaining payable atomically; duplicate submission does not double-disburse.
- Each approval/disbursement/correction has actor, time and audit history.

### AC-025 (US-025)
- Winner's future installments remain due after auction win and are shown by group and period.
- Prize disbursement does not erase, net, or mark installments paid unless a separate approved transaction/policy says so.

## E7 — Reporting, authorization and audit

### AC-026 (US-026)
- Report supports a stated date range and group/period scope for payments and pending dues.
- Actual cash/bank/UPI collections, dividend credits and outstanding dues have separate columns/labels and reconciliation totals.
- Totals are derived from posted records and show as-of/period context.

### AC-027 (US-027)
- Owner can view member statements and group summaries with group-scoped figures.
- Reports distinguish collected, outstanding, dividend credit, prize payable, prize actually disbursed and commission earned.
- Totals reconcile to underlying records under approved recognition/allocation rules.

### AC-028 (US-028)
- Auction report shows actual recorded winning discounts by group and period.
- Commission earned uses approved calculation and recognition rules and is separately labeled from discount and collection.
- Report can be traced to finalized auction/calculation records.

### AC-029 (US-029)
- Owner can export an authorized report with selected filters, period and generation time.
- Export preserves currency precision and labels distinct measures so they cannot be mistaken for one another.
- Unauthorized users cannot export records outside permitted scope.

### AC-030 (US-030)
- Owner can perform all authorized business operations; staff can access only assigned groups and permitted functions.
- Authorization is checked on protected operations/data access, not only in navigation or UI visibility.
- Direct requests outside permission are denied and do not change data.
- Member-facing login is not required for MVP.

### AC-031 (US-031)
- Audit log covers group/member create and update, auction create/finalize, payment create/correct, prize disbursement and financial adjustment.
- Each entry records actor, action, timestamp, target record and before/after details appropriate to the action.
- Users cannot silently edit/delete audit history; corrections are linked to original records.
- Audit visibility follows owner/staff permissions and supports investigation by record.
