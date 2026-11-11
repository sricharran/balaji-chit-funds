# Project Overview

## Purpose

Build a secure, auditable web system for a chit fund business that currently manages groups, members, monthly auctions, collections, dividends, prize payments and reporting manually. The system is intended for real financial operations, so financial accuracy, traceability and access control are core product requirements.

## Current state

Repository inspection on 9 November 2026 found no application source, package manifest, README, database configuration or existing product documentation. The workspace contains only Git metadata. This is therefore a new project. Phase 1 is documentation only; no application stack or architecture has been approved.

## Business at a glance

The initial operating examples are three schemes: chit values ₹2,00,000, ₹3,00,000 and ₹5,00,000; each is shown as a 20-month example with 20 members; monthly instalments are ₹10,000, ₹15,000 and ₹25,000. Commission is configured as a fixed amount for each group, not a percentage. These examples are not constants: each group's configured duration and roster determine its schedule. Owners must be able to define additional schemes. Remaining financial and operational questions are listed in [OPEN_BUSINESS_RULES.md](OPEN_BUSINESS_RULES.md).

Each group holds one auction per month. Members bid; a member may win at most once per group and continues instalments after winning. The winner's prize is calculated with a discount, a commission and a dividend distribution, but the illustrative formula supplied by the business is not approved for implementation. A winning auction does not itself mean the prize was paid.

## Users

- **Owner / Administrator:** full business access; manages groups and members, operates auctions and payments, approves prize distributions, and views reports.
- **Staff / Operator:** views assigned groups, records payments, views member information, assists with auctions and uses permitted reports.
- **Members:** member-facing authentication is outside the initial MVP.

Authorization must be enforced at the data/API boundary, not only by hiding interface controls. Staff assignment and exact permissions remain to be defined.

## Product areas

1. Dashboard and operational overview.
2. Chit schemes and group lifecycle.
3. Member directory, group enrollment and member account history.
4. Monthly auctions, bids, outcomes and financial calculations.
5. Installment dues, payment collection, credits and receipts.
6. Prize approval, payable tracking and disbursement.
7. Financial and operational reporting/export.

## Product principles and constraints

- Keep financial calculations centralized, precise (integer minor units or exact decimal), reproducible, validated and independently testable.
- Do not decide open financial rules by implication. Preserve calculation inputs and outputs and maintain original financial entries through corrections rather than silent edits.
- Use transactional operations for sensitive financial state changes; enforce referential integrity and uniqueness in persistent storage.
- Maintain actor, timestamp, action and change details for auditable operations.
- Distinguish collected money, outstanding dues, dividend credits, prize payable, prize disbursed and commission earned in all summaries.
- Support cash, UPI and bank transfer; provide mobile-friendly collection workflows and Indian currency/date presentation.
- Target Supabase PostgreSQL, Supabase Auth, RLS and migrations as the supplied technology direction. Detailed architecture and schema belong to Phase 2 after review.

## Scope boundary

This document set covers Phase 1 requirements engineering only. It does not select a frontend stack, design a database, define APIs, create migrations, implement calculations or build UI. Phase 2 begins only after product-owner review and approval of requirements.

## Traceability

- [Business requirements](BUSINESS_REQUIREMENTS.md) records capabilities, controls and invariants.
- [User stories](USER_STORIES.md) contains prioritized, uniquely identified stories and dependencies.
- [Acceptance criteria](ACCEPTANCE_CRITERIA.md) provides testable outcomes by story ID.
- [Open business rules](OPEN_BUSINESS_RULES.md) records unresolved policy, edge cases and owner decisions needed.
- [Product roadmap](PRODUCT_ROADMAP.md) recommends an MVP and phased delivery sequence.
