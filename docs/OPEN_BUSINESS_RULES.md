# Open Business Rules and Decisions

These questions affect financial correctness or operational authorization. Resolved rules are listed with their implementation behavior; remaining questions need owner decisions before the related workflows are treated as production-ready.

## Remaining financial calculation and dividend policy questions

| ID | Rule to decide | Why it matters / edge cases |
|---|---|---|
| BR-16 | Are there any dividend eligibility exceptions for inactive/defaulting members? | Current implementation credits every active group member, including the auction winner. |
| BR-17 | Are there any additional deductions from the winner payout beyond the manually entered discount and configured commission? | The current monthly formula includes only those two deductions. |
| BR-18 | How should corrections or reversals work after dividends or installment payments have been posted? | Finalized auctions are immutable; corrections currently require an operational database process. |
| BR-19 | What precise rounding policy applies to values that cannot be represented in paise, including chit value divided by duration? | Dividends use integer paise and assign remainder paise in member-number order; group base installments currently round to the nearest paise. |
| BR-20 | How are late, advance, overpaid or reversed payments allocated across periods? | Current payment flow only accepts amounts up to the current installment balance. |
| BR-21 | What installment is due when payments/credits are partial, late, overpaid or advance? How are payments allocated among periods? | Needed for consistent outstanding balance and statement reconciliation. |
| BR-22 | What payment fields, references, receipt numbering, void/reissue rules and duplicate detection are required by method? | Prevents duplicate receipts and supports cash/UPI/bank reconciliation. |
| BR-23 | What approval/security/guarantee is required before prize disbursement? Which role approves, and can approver also record disbursement? | High-value control and separation of duties. |
| BR-24 | Can prizes be partially disbursed, in multiple methods, or netted against dues? How are cancelled/failed/reversed transfers represented? | Determines payable balance and ledger postings. |
| BR-25 | What is the allowed disbursement timing, and what happens if a finalized prize is never disbursed or the member declines it? | Defines aging, status and reporting obligations. |

## Critical: auction operation

| ID | Rule to decide | Why it matters / edge cases |
|---|---|---|
| BR-12 | What auction date/schedule defines a month? Can auctions be postponed, cancelled, repeated or reopened? What is the no-valid-bid outcome? | Avoids duplicate/missing period outcomes. |
| BR-13 | What bid bounds and format are valid? Is a bid a discount amount, percentage or another offer? Can bids be withdrawn/edited, and until when? | Ensures bids and winning discount are comparable and valid. |
| BR-14 | How are ties resolved? What are eligibility restrictions beyond prior group win (e.g. arrears, suspension, incomplete enrollment)? | Avoids discretionary or inconsistent winner selection. |
| BR-15 | Who selects/approves winner if bid order conflicts with selected winner? Can owner override the highest/lowest bid, with what reason and audit? | Controls outcome authority and dispute evidence. |
| BR-26 | What happens if a member exits, dies, transfers membership, or is replaced after winning/without winning? Can a membership be suspended? | Impacts capacity, eligibility, future dues, prize liability and audit. |

## Critical: group and member policy

| ID | Rule to decide | Why it matters / edge cases |
|---|---|---|
| BR-01 | Are there any group types where base installment is not chit value divided by duration? | Current group setup derives it from that formula. |
| BR-02 | What values/ranges/precision are allowed for value, duration, member count, installment and commission? | Enables meaningful validation before activation. |
| BR-03 | Can schemes be edited after groups use them? Are group terms snapshotted at creation/activation? | Prevents historical figures changing after amendments. |
| BR-04 | When can members join/leave; can a group start partially filled; what confirms readiness to activate? | Defines activation and capacity rules. |
| BR-05 | Can an active group be paused, cancelled, completed early, or have terms changed? Who approves and how do changes apply to prior periods? | Prevents silent changes to financial obligations. |
| BR-06 | Which personal details are required, and how is member identity verified? | Data minimization, duplicate handling and operations depend on this. |
| BR-07 | Are phone numbers unique? How to handle shared/changed numbers, duplicate people and merges? | Search and payment attribution risks. |
| BR-08 | Is enrollment exclusive to one slot/member per group? Can joint members/nominees or transfers be recorded? | Defines roster and winner identity. |
| BR-09 | How are balances treated when membership transfers, exits or is replaced? | Prevents financial history being assigned to the wrong person. |
| BR-10 | What is due date, grace period, late fee/penalty (if any), and are rules different after winning? | Drives dues, notices and outstanding calculations. |
| BR-11 | Can overpayments be carried, refunded or allocated across future installments? | Determines member credit balance and refunds. |

## Cross-cutting policy

| ID | Rule to decide | Why it matters / edge cases |
|---|---|---|
| BR-27 | Which timezone/date convention applies to auctions, payments, due periods and reports? | Prevents day-boundary differences in receipts and totals. |
| BR-28 | What exact permissions distinguish owner and staff? Can staff see member balances, enter bids, finalize auctions or handle prizes? How are assignments granted/revoked? | Required to define role enforcement and separation of duties. |
| BR-29 | What audit retention, export formats, report date cutoffs and historical migration needs apply? | Needed for reporting and transition from manual records. |
| BR-30 | Which backup, recovery point/time objectives, logging and incident processes are acceptable? | Reliability requirements need measurable targets before production. |
| BR-31 | What historical records will be imported, who validates them, and how are opening balances evidenced? | Bad opening data undermines all later reports. |
| BR-32 | What languages, accessibility expectations, and exact Indian date/currency display conventions are required? | Supports usable records for staff and members. |

## Edge-case checklist for owner review

- No bids, invalid bids, equal bids, withdrawn bids, winner unable to accept, auction rescheduled or entered twice.
- A bidder already won in the group; bidder has arrears; member status changes during an open auction.
- Zero/negative/over-maximum discount; discount exceeding gross collection; indivisible dividend remainder.
- Partial, duplicate, backdated, misattributed, reversed, cash-without-reference or overpaid installment.
- Dividend credited to the wrong period/member; dividend exceeds due; member is excluded/eligible after status change.
- Prize approved but never paid; partial/duplicate/failed/reversed payment; transfer reference reused; prize offset against dues.
- Group terms change after launch; group is cancelled or member leaves; same member in multiple groups.
- Concurrent users submit/finalize the same auction or payment; retry after timeout; interrupted transaction.
- Report spans month boundary/timezone, includes corrected entries, or is exported by a staff member with limited scope.

## Recommended owner review order

1. BR-01–05 group configuration and lifecycle.
2. BR-12–20 auction and core financial calculation/dividend behavior.
3. BR-10–11 and BR-21–22 payment, due, correction and receipt behavior.
4. BR-23–25 prize approval/disbursement.
5. BR-06–09 member identity/enrollment and BR-26 member lifecycle.
6. BR-27–32 access, reporting, migration and reliability.
