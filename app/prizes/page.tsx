import Link from "next/link";
import { randomUUID } from "node:crypto";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { signOut } from "../dashboard/actions";
import { recordPrizeDisbursement } from "./actions";

const money = (paise: number) => new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 2 }).format(paise / 100);
const todayInIndia = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Kolkata", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date());
const dateLabel = (value: string) => new Intl.DateTimeFormat("en-IN", { dateStyle: "medium", timeZone: "Asia/Kolkata" }).format(new Date(`${value}T00:00:00+05:30`));

export default async function PrizesPage({ searchParams }: { searchParams: Promise<{ error?: string; recorded?: string }> }) {
  const query = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: profile } = await supabase.from("profiles").select("role,full_name,active").eq("id", user.id).maybeSingle();
  if (!profile?.active || !["owner", "staff"].includes(profile.role)) redirect("/login?error=unauthorized");
  const [{ data: auctions }, { data: disbursements }, { data: roster }] = await Promise.all([
    supabase.from("auctions").select("id,group_id,month_number,auction_date,winner_member_id,prize_amount_paise,chit_groups(name,group_code)").eq("status", "finalized").order("auction_date", { ascending: false }),
    supabase.from("prize_disbursements").select("id,auction_id,chit_member_id,amount_paise,disbursement_date,payment_method,transaction_reference,created_at").order("disbursement_date", { ascending: false }),
    supabase.from("chit_members").select("id,group_id,member_id,member_number,members(full_name)").order("member_number"),
  ]);
  const disbursedByAuction = new Map<string, number>();
  for (const row of disbursements ?? []) disbursedByAuction.set(row.auction_id, (disbursedByAuction.get(row.auction_id) ?? 0) + row.amount_paise);
  const totalPayable = (auctions ?? []).reduce((sum, auction) => sum + (auction.prize_amount_paise ?? 0), 0);
  const totalDisbursed = (disbursements ?? []).reduce((sum, row) => sum + row.amount_paise, 0);
  const outstanding = (auctions ?? []).reduce((sum, auction) => sum + Math.max(0, (auction.prize_amount_paise ?? 0) - (disbursedByAuction.get(auction.id) ?? 0)), 0);
  const displayName = profile.full_name || user.email || "Team member";
  const initials = displayName.slice(0, 1).toUpperCase();
  const groupInfo = (relation: { name: string; group_code: string } | { name: string; group_code: string }[] | null) => Array.isArray(relation) ? relation[0] : relation;
  const winnerInfo = (groupId: string, memberId: string) => {
    const entry = (roster ?? []).find((item) => item.group_id === groupId && item.member_id === memberId);
    const member = entry && (Array.isArray(entry.members) ? entry.members[0] : entry.members);
    return { name: member?.full_name ?? "Member", number: entry?.member_number };
  };
  const errorMessages: Record<string, string> = {
    invalid: "Enter a valid positive amount, date, payment method, and reference.",
    exceeds: "The disbursement is greater than the remaining prize balance.",
    notfinalized: "A prize can only be disbursed for a finalized auction.",
    migration: "Apply migration 202611110005_prize_disbursement_workflow.sql in Supabase first.",
    save: "Could not record the prize disbursement. Refresh and try again.",
  };

  return <div className="dashboard-shell">
    <aside className="sidebar"><div className="brand-logo"><span className="brand-mark">B</span><span>BALAJI <span style={{fontWeight:500,opacity:.7}}>CHIT FUNDS</span></span></div><div className="side-label">Workspace</div><Link href="/dashboard" className="nav-link"><span className="nav-icon">01</span>Dashboard</Link><div className="side-label">Management</div><Link href="/groups" className="nav-link"><span className="nav-icon">02</span>Chit groups</Link><Link href="/members" className="nav-link"><span className="nav-icon">03</span>Members</Link><Link href="/auctions" className="nav-link"><span className="nav-icon">04</span>Auctions</Link><Link href="/installments" className="nav-link"><span className="nav-icon">05</span>Installments</Link><Link href="/prizes" className="nav-link active"><span className="nav-icon">06</span>Prize payments</Link><div className="side-label">Insights</div><Link href="/reports" className="nav-link"><span className="nav-icon">07</span>Reports</Link><div className="sidebar-bottom"><div className="user-mini"><div className="avatar">{initials}</div><div><div className="user-name">{displayName}</div><div className="user-role">{profile.role === "owner" ? "Owner / Administrator" : "Staff / Operator"}</div></div></div><form action={signOut}><button className="signout">Sign out</button></form></div></aside>
    <main className="main-area"><header className="topbar"><div className="breadcrumb">Management&nbsp; / &nbsp;<b>Prize payments</b></div></header><div className="content">
      <div className="page-heading"><div><div className="eyebrow">WINNER PAYOUTS</div><h1>Prize payments</h1><p>Track finalized prize amounts, partial disbursements, and balances still payable.</p></div></div>
      {query.recorded && <div className="notice success">Prize disbursement recorded.</div>}{query.error && errorMessages[query.error] && <div className="form-error">{errorMessages[query.error]}</div>}
      <section className="stats-grid prize-stats"><article className="stat-card"><div className="stat-head">Total prize payable<span className="stat-icon">01</span></div><div className="stat-value stat-money">{money(totalPayable)}</div><div className="stat-foot">Finalized auction payouts</div></article><article className="stat-card"><div className="stat-head">Total disbursed<span className="stat-icon">02</span></div><div className="stat-value stat-money">{money(totalDisbursed)}</div><div className="stat-foot">Recorded prize payments</div></article><article className="stat-card"><div className="stat-head">Remaining payable<span className="stat-icon">03</span></div><div className="stat-value stat-money">{money(outstanding)}</div><div className="stat-foot">Not yet disbursed</div></article></section>
      <section className="panel table-panel"><div className="panel-heading"><div><h2>Finalized prizes</h2><div className="row-sub">An auction win creates a payable. Record each actual transfer here.</div></div><span className="row-sub">{auctions?.length ?? 0} prizes</span></div><div className="table-scroll"><table><thead><tr><th>Group / month</th><th>Auction date</th><th>Winner</th><th>Prize payable</th><th>Disbursed</th><th>Remaining</th>{profile.role === "owner" && <th>Record disbursement</th>}</tr></thead><tbody>{auctions?.map((auction) => { const group = groupInfo(auction.chit_groups); const winner = auction.winner_member_id ? winnerInfo(auction.group_id, auction.winner_member_id) : null; const paid = disbursedByAuction.get(auction.id) ?? 0; const remaining = Math.max(0, (auction.prize_amount_paise ?? 0) - paid); return <tr key={auction.id}><td><Link className="table-primary-link" href={`/auctions/${auction.id}`}><strong>{group?.group_code ?? "Group"} · Month {auction.month_number}</strong></Link><small>{group?.name ?? ""}</small></td><td>{dateLabel(auction.auction_date)}</td><td>{winner?.name ?? "Member"}{winner?.number ? <small>Member #{winner.number}</small> : null}</td><td>{money(auction.prize_amount_paise ?? 0)}</td><td>{money(paid)}</td><td><strong>{money(remaining)}</strong></td>{profile.role === "owner" && <td>{remaining > 0 ? <details className="prize-editor"><summary>Record payment</summary><form action={recordPrizeDisbursement} className="prize-payment-form"><input type="hidden" name="auction_id" value={auction.id}/><input type="hidden" name="request_key" value={randomUUID()}/><label>Amount (₹)<input name="amount" type="number" min="0.01" max={(remaining / 100).toFixed(2)} step="0.01" required/></label><label>Method<select name="payment_method" defaultValue="cash"><option value="cash">Cash</option><option value="upi">UPI</option><option value="bank_transfer">Bank transfer</option></select></label><label>Date<input name="disbursement_date" type="date" defaultValue={todayInIndia} required/></label><label>Reference<input name="reference" maxLength={120} placeholder="Optional"/></label><button className="secondary-button" type="submit">Save disbursement</button></form></details> : <span className="status-pill settled">Paid</span>}</td>}</tr>; })}</tbody></table>{(!auctions || auctions.length === 0) && <div className="empty-state">No finalized prizes are available yet.</div>}</div></section>
      <section className="panel table-panel"><div className="panel-heading"><div><h2>Disbursement history</h2><div className="row-sub">Each row is an actual recorded prize payment.</div></div><span className="row-sub">{disbursements?.length ?? 0} records</span></div><div className="table-scroll"><table><thead><tr><th>Date</th><th>Group / month</th><th>Winner</th><th>Amount</th><th>Method</th><th>Reference</th></tr></thead><tbody>{disbursements?.map((row) => { const auction = auctions?.find((item) => item.id === row.auction_id); const group = auction && groupInfo(auction.chit_groups); const membership = (roster ?? []).find((item) => item.id === row.chit_member_id); const member = membership && (Array.isArray(membership.members) ? membership.members[0] : membership.members); return <tr key={row.id}><td>{dateLabel(row.disbursement_date)}</td><td>{group?.group_code ?? "Group"} · Month {auction?.month_number ?? "—"}</td><td>{member?.full_name ?? "Member"}</td><td>{money(row.amount_paise)}</td><td>{row.payment_method?.replace("_", " ") ?? "—"}</td><td>{row.transaction_reference || "—"}</td></tr>; })}</tbody></table>{(!disbursements || disbursements.length === 0) && <div className="empty-state">No prize disbursements recorded yet.</div>}</div></section>
    </div></main>
  </div>;
}
