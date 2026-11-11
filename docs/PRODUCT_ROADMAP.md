# Product Roadmap

## Status

Requirements-phase recommendation for review. No implementation or technology architecture is authorized by this roadmap. Phase 2 starts after product-owner review and approval of Phase 1 requirements.

## MVP outcome

An internal owner/staff system that can set up groups and members, run monthly auctions with reviewable recorded outcomes, track dues and actual payments, track separately approved dividend credits, manage prize approval/disbursement, and produce reconciled operational reports with enforced permissions and audit history.

The MVP is **not ready for real-money operation** until critical rules are resolved and financial calculations are reconciled against actual historical records.

## Proposed delivery sequence

| Stage | Scope | Stories | Exit condition |
|---|---|---|---|
| Phase 1 — Requirements (current) | Confirm business context, user needs, acceptance criteria, open rules and MVP boundaries. | US-001–US-031 (requirements baseline) | Product owner reviews and approves baseline; critical rules have owners/decisions or are explicitly excluded from initial operation. |
| Phase 2 — Product and architecture design | Translate approved requirements into architecture, entity relationships, PostgreSQL schema/constraints, auth/RLS model, financial workflow, API boundaries, audit/correction model and decision records. | No feature implementation | Design reviewed; all schema-affecting/financial decisions recorded; threat and data-access model reviewed. |
| Phase 3 — Foundation | Project setup, selected frontend, Supabase configuration, Auth, layout/navigation, role management, migrations, audit foundation, environments and operational logging/backup approach. | US-030, US-031 foundations | Owner/staff access is enforced at data boundary; migrations and audit path are reviewable. |
| Phase 4A — Groups and members | Configurable schemes, group creation/activation/lifecycle, member directory, enrollment, group roster and member statements foundation. | US-003–US-010 | Group configuration validated; member/group history remains separate; access and audit criteria met. |
| Phase 4B — Auctions and calculations | Monthly auction lifecycle, eligibility, bids, review, finalization, immutable outcome snapshot, approved financial calculation and auction history. | US-011–US-016 | Calculation fixtures match owner-approved historical cases; one-win and atomic finalization controls pass. |
| Phase 4C — Collections and dividend credits | Dues, full/partial payment entry, correction workflow, dividend credits, receipts and collection filters. | US-017–US-022 | Ledger reconciles; credits are distinct from cash; duplicate/retry behavior is controlled. |
| Phase 4D — Prize and reporting | Prize payable, approval/disbursement, continuing winner dues, dashboard, reports and export. | US-001–US-002, US-023–US-029 | Award/payable/disbursed values reconcile; reports distinguish all required measures. |
| Phase 5 — Readiness and validation | Unit/integration/database/financial/authorization coverage, error handling, backup/restore rehearsal, audit review, historical reconciliation, user acceptance and operating procedures. | All MVP stories | Owner signs off reconciliation and controls; only then consider real financial deployment. |

## Recommended MVP priorities

### Include

- Owner and assigned staff roles with server/data-boundary checks (US-030).
- Scheme/group setup and activation guardrails (US-003–US-006).
- Member records and multiple group enrollments with isolated group histories (US-007–US-010).
- Auction creation, eligible roster, bid capture/review, finalization, actual discount and history (US-011–US-016).
- Centralized exact financial calculation after its rules are approved (US-015).
- Dues, full/partial payment, correction history, separately tracked dividend credits and receipts (US-017–US-022).
- Prize payable distinct from disbursement; approval, partial/full payment tracking and winner's remaining obligations (US-023–US-025).
- Operational dashboard and core reconciled reports (US-001–US-002, US-026–US-028).
- Audit history (US-031), backup/recovery plan and historical reconciliation before live operation.

### Defer until core controls are stable

- Report export (US-029), unless the owner needs it for initial reconciliation.
- Member-facing login/portal (explicitly outside initial MVP).
- Automated default handling, penalties, notifications, advanced analytics, integrations and other features not specified in approved scope.

## Release gates and key dependencies

1. **Requirements gate:** owner approves requirements and explicitly resolves or defers business rules; do not silently substitute assumptions.
2. **Financial gate:** approved discount, commission, dividend, and same-month installment formulas are implemented. Remaining payment corrections, auction tie/no-bid handling, and prize rules are confirmed, and historical sample calculations reconcile.
3. **Security gate:** owner/staff permission matrix and group assignment model approved; direct data access is enforced.
4. **Data gate:** opening balances and any manual-history import are verified and signed off.
5. **Production gate:** backup restoration, correction workflow, audit review, operational support and owner acceptance complete. No real financial deployment before historical validation.

## Risks to schedule

- Remaining payment correction, auction tie/no-bid and prize rules affect installment and reporting workflows.
- Member default, transfer and exit policies affect eligibility, outstanding balance and group capacity.
- Historical record quality and opening-balance reconciliation may take more effort than application setup.
- Staff permissions and prize approvals may require separation-of-duties decisions.
- Rounding/remainder policy can create persistent ledger differences if decided late.
