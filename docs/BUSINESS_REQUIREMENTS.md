# Business Requirements

## Status and interpretation

Phase 1 draft for product-owner review. Requirements below describe requested outcomes, not architecture. Financial examples in the source brief are illustrative and must not be treated as approved policy. Unresolved decisions are tracked in [OPEN_BUSINESS_RULES.md](OPEN_BUSINESS_RULES.md).

## Business context and initial configuration

The business currently operates manually. Initial scheme examples:

| Scheme | Chit value | Duration | Members | Monthly instalment | Commission per monthly auction |
|---|---:|---:|---:|---:|---:|
| A | ₹2,00,000 | 20 months | 20 | ₹10,000 | Configured fixed amount |
| B | ₹3,00,000 | 20 months | 20 | ₹15,000 | Configured fixed amount |
| C | ₹5,00,000 | 20 months | 20 | ₹25,000 | Configured fixed amount |

These values are configurable starting examples. The product must support other scheme/group configurations. A group configuration must be validated before activation; exact validation rules need owner confirmation where not explicit.

## Roles and access

**Owner / Administrator** has full business access: group and member management, auctions, payments, prize approvals and reports. **Staff / Operator** can see assigned groups, register payments, view member information, assist with auction operations and access permitted reports. The system must enforce authorization beyond the UI. No member login is in initial scope. Staff assignment lifecycle, sensitive action approval boundaries and whether multiple owners are supported require clarification.

## Functional requirements

### BR-GRP: Scheme and group management

- Define reusable, configurable scheme terms; do not hardcode the three examples.
- Create groups with value, duration, member capacity, derived monthly instalment, fixed commission amount and lifecycle status.
- Validate group configuration before activation; track active/completed groups and monthly progress.
- View group roster and group-level financial/operational status.
- Group and scheme changes affecting an active financial plan must be controlled and auditable; effective-date and amendment policy is unresolved.

### BR-MEM: Member management

- Register members and maintain contact information.
- Enroll a member into one or more groups.
- Search by name or phone number; view group roster, member payment history, win status and outstanding balance.
- Keep each member's financial history distinguishable by group. Enrollment changes and identity/duplicate matching policy need definition.

### BR-AUC: Auctions

- Create/track one monthly auction for each group and period; show eligible members and record bids.
- Allow review of recorded bids before finalization and record the selected winner and actual winning discount.
- Prevent a member from winning more than once in a group.
- Show historical auction outcomes.
- Calculate prize, commission, dividend pool and dividend/member only under an approved calculation policy. The engine is independent of the frontend; its inputs, outputs and rounding behavior must be recorded.
- Preserve auction state and prohibit invalid transitions; transaction and correction rules must be specified in architecture/design.

### BR-PAY: Dues and collections

- Show monthly gross instalment due per enrolled member and track unpaid dues.
- Record full or partial payments and payment date/method; supported methods are cash, UPI and bank transfer.
- Record dividend credits separately from collected money. A dividend credit alone must not be represented as a cash payment.
- View payment history, filter collections by date/method and generate receipts.
- Support correction history, duplicate prevention and allocation across dues only after policies are established.

### BR-PRZ: Prize distribution

- Show amount payable from a finalized auction; keep auction award separate from actual disbursement.
- Record partial/full disbursements, date and transaction reference and show pending amount.
- Show the winner's remaining installment obligations; winning does not stop future installments.
- Approval, guarantee requirements, split payment treatment and correction/refund processes need confirmation.

### BR-RPT: Reports and dashboard

- Dashboard includes active groups, registered members, upcoming auctions, monthly collections, pending payments, outstanding balances, prizes pending disbursement and recent transactions.
- Provide monthly collections, pending payments, member statements, group summaries, auction history/discounts, commission earned and exportable reports.
- Clearly distinguish cash collected, outstanding, dividend credits, prize payable, prize disbursed and commission earned. Reporting periods, as-of rules, permissions and export formats need confirmation.
- Derive figures from recorded business data; do not use placeholder/manual totals as actuals.

### BR-SEC: Security, audit and operational integrity

- Authenticate internal users; authorize owner and staff actions server-side and through database access controls.
- Target Supabase Auth and PostgreSQL RLS; never expose service-role credentials to clients.
- Financial operations require server-side validation, durable transaction semantics and rollback on failure.
- Maintain audit history for member/group create/update, auction create/finalize, payment create/correction, prize disbursement and financial adjustments. Each entry identifies actor, time, operation and changed values.
- Prevent duplicate payments/wins, invalid state transitions and broken references; preserve immutable/correction-based financial history.
- Define error handling, logs, backups and recovery procedures before production use.

### BR-USABILITY: Usability and localization

- Responsive, mobile-friendly workflows, especially payment entry.
- Simple navigation, clear financial summaries, Indian currency formatting and date formatting suitable for Indian users.

## Business invariants stated in the brief

1. A group has 20 members and runs 20 months in the current operating model; configuration is explicitly required, so these are defaults/examples rather than immutable system-wide limits.
2. One auction occurs monthly for a group.
3. A member wins at most once within a group.
4. Auction discount is variable and each actual winning discount is stored.
5. A winner continues paying installments.
6. A won auction and a paid prize are separate events.
7. Dividend credits and money collected are separate records and measures.
8. Group-scoped financial history remains distinct when a member belongs to multiple groups.

## Monthly chit calculation rules

- Base installment per member is `individual chit value / configured duration`. It is derived when the group is created.
- The group stores a fixed monetary commission amount per auction. No percentage is assumed. Every auction snapshots that configured amount; a different amount requires owner authorization and an audit record.
- The auction discount is entered manually. No automatic discount formula is used for bidding or Lucky Draw selection.
- Gross monthly collection is `member count × base installment`.
- Total deduction is `auction discount + commission`.
- Dividend pool is the auction discount only. Commission is retained by Balaji Agencies and is excluded from the dividend pool.
- All group members receive an equal dividend, including the winner. Each share is `auction discount / member count` and applies to that same month's installment.
- Net installment per member is `base installment − dividend credit`.
- Winner payout is `gross monthly collection − auction discount − commission`.
- Before finalization, validate `gross collection = total net installment collection + dividend pool` and `total net installment collection = winner payout + commission`.
- Use integer paise for stored money. If the discount does not divide evenly by member count, assign remaining paise in member-number order.
- Preserve finalized calculation snapshots when future group commission settings change. Actual payments and prize disbursements remain separate transactions.

The worked example in the monthly calculation specification uses chit value ₹1,20,000, 12 members, 12 months, ₹10,000 base installment, ₹19,200 discount and ₹4,000 commission. This produces ₹1,600 dividend/member, ₹8,400 net installment/member and ₹96,800 winner payout.

## Quality requirements

- Exact currency arithmetic; defined scale/rounding and no floating-point money calculations.
- Validate invalid, negative, out-of-range or inconsistent amounts before durable financial changes.
- Preserve original inputs, outputs, timestamps, actor and correction linkage.
- Apply consistent Indian formatting while preserving unrounded source values in records.
- Validate requirements against actual historical records before real financial deployment.

## Out of scope for initial MVP

- Member-facing login/portal.
- Deployment for real financial operation before historical validation.
- Unapproved business rules or automatic financial behavior inferred from examples.
- Any technology implementation during requirements phase.
