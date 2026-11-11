# Balaji Chit Funds

Internal chit fund management application using Next.js, TypeScript and Supabase Auth/Postgres.

## Get started

1. Install Node.js 20.9 or newer.
2. Run `npm install`.
3. Copy `.env.example` to `.env.local` and set the Supabase project URL and anon/publishable key.
4. In Supabase SQL Editor, apply all twelve files in `supabase/migrations/` in filename order.
5. Create the first internal user through Supabase Auth, then promote that user's profile to owner using the SQL below. Replace the email with the account you created:

   ```sql
   insert into public.profiles (id, full_name, role, active)
   select id, coalesce(raw_user_meta_data ->> 'full_name', 'Business Owner'), 'owner', true
   from auth.users
   where email = 'owner@example.com'
   on conflict (id) do update
   set role = 'owner', active = true;
   ```

   New user profiles default to inactive staff. There is no public signup or in-app role editor.
6. Run `npm run dev` and open `http://localhost:3000`.

The app uses Supabase cookie-based SSR auth. The dashboard requires an authenticated user with an active `owner` or `staff` profile. Profile role changes are intentionally not available to users through the application.

Implemented so far: Supabase Auth login/logout, active-role authorization, dashboard, group and member management, group enrollment and activation, bid and Lucky Draw winner selection, fixed group commission configuration, manual monthly discounts, payout and reconciliation checks, monthly installment generation for every active group member, discount-only dividend credits and partial/full installment payments. Lucky Draw selects a winner but does not calculate a discount. Dividend credits apply to that month's installment; remainder paise go to members in member-number order. Migrations define RLS for groups, memberships, auctions, bids, installments, payments, dividends, prizes and ledger entries. Dashboard group/member counts use database records. Prize and activity panels are intentionally empty until those workflows are implemented; no sample financial data is shown.

The group and member forms are owner-only. Staff can view records only for groups assigned in `staff_group_assignments`; assignment management currently requires an owner to update the database. Groups are created as drafts and are not yet activated or used for financial operations.

See `docs/` for the requirements baseline and unresolved financial rules.
