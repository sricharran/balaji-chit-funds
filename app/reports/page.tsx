import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { signOut } from "../dashboard/actions";

const money = (paise: number) => new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 2 }).format(paise / 100);
const dateLabel = (value: string) => new Intl.DateTimeFormat("en-IN", { dateStyle: "medium", timeZone: "Asia/Kolkata" }).format(new Date(`${value}T00:00:00+05:30`));

export default async function ReportsPage({ searchParams }: { searchParams: Promise<{ group?: string; month?: string }> }) {
  const query = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: profile } = await supabase.from("profiles").select("role,full_name,active").eq("id", user.id).maybeSingle();
  if (!profile?.active || !["owner", "staff"].includes(profile.role)) redirect("/login?error=unauthorized");

  const [{ data: groups }, { data: installments }, { data: auctions }, { data: roster }, { data: prizeDisbursements }] = await Promise.all([
    supabase.from("chit_groups").select("id,name,group_code,duration_months").order("group_code"),
    supabase.from("installments").select("id,chit_member_id,month_number,due_date,gross_amount_paise,dividend_credit_paise,net_due_paise,status,chit_members(group_id,member_id,member_number,members(full_name)),payments(amount_paise,payment_date)"),
    supabase.from("auctions").select("id,group_id,month_number,auction_date,winning_discount_paise,commission_paise,prize_amount_paise,winner_member_id,status").eq("status", "finalized").order("auction_date", { ascending: false }),
    supabase.from("chit_members").select("group_id,member_id,member_number,members(full_name)"),
    supabase.from("prize_disbursements").select("auction_id,amount_paise"),
  ]);

  const groupIds = new Set((groups ?? []).map((group) => group.id));
  const selectedGroup = (groups ?? []).find((group) => group.id === query.group);
  const rawMonth = String(query.month ?? "");
  const selectedMonth = /^\d{1,3}$/.test(rawMonth) && Number(rawMonth) >= 1 && Number(rawMonth) <= 120 ? Number(rawMonth) : null;
  const reportInstallments = (installments ?? []).filter((row) => {
    const link = Array.isArray(row.chit_members) ? row.chit_members[0] : row.chit_members;
    return !!link && groupIds.has(link.group_id) && (!selectedGroup || link.group_id === selectedGroup.id) && (!selectedMonth || row.month_number === selectedMonth);
  });
  const reportAuctions = (auctions ?? []).filter((auction) =>
    groupIds.has(auction.group_id) && (!selectedGroup || auction.group_id === selectedGroup.id) && (!selectedMonth || auction.month_number === selectedMonth)
  );
  const paidAmount = (row: (typeof reportInstallments)[number]) => {
    const payments = Array.isArray(row.payments) ? row.payments : [];
    return payments.reduce((sum, payment) => sum + payment.amount_paise, 0);
  };
  const totalCollected = reportInstallments.reduce((sum, row) => sum + paidAmount(row), 0);
  const totalOutstanding = reportInstallments.reduce((sum, row) => sum + Math.max(0, row.net_due_paise - paidAmount(row)), 0);
  const totalDividends = reportInstallments.reduce((sum, row) => sum + row.dividend_credit_paise, 0);
  const totalCommission = reportAuctions.reduce((sum, auction) => sum + (auction.commission_paise ?? 0), 0);
  const disbursedByAuction = new Map<string, number>();
  const reportAuctionIds = new Set(reportAuctions.map((auction) => auction.id));
  for (const row of prizeDisbursements ?? []) if (reportAuctionIds.has(row.auction_id)) disbursedByAuction.set(row.auction_id, (disbursedByAuction.get(row.auction_id) ?? 0) + row.amount_paise);
  const totalPrizeDisbursed = [...disbursedByAuction.values()].reduce((sum, amount) => sum + amount, 0);
  const totalPrizeOutstanding = reportAuctions.reduce((sum, auction) => sum + Math.max(0, (auction.prize_amount_paise ?? 0) - (disbursedByAuction.get(auction.id) ?? 0)), 0);
  const displayName = profile.full_name || user.email || "Team member";
  const initials = displayName.slice(0, 1).toUpperCase();
  const memberName = (memberId: string, groupId: string) => {
    const entry = (roster ?? []).find((item) => item.member_id === memberId && item.group_id === groupId);
    const detail = entry && (Array.isArray(entry.members) ? entry.members[0] : entry.members);
    return detail?.full_name ?? "Member";
  };
  const groupName = (groupId: string) => (groups ?? []).find((item) => item.id === groupId)?.group_code ?? "Group";

  return <div className="dashboard-shell">
    <aside className="sidebar"><div className="brand-logo"><span className="brand-mark">B</span><span>BALAJI <span style={{fontWeight:500,opacity:.7}}>CHIT FUNDS</span></span></div><div className="side-label">Workspace</div><Link href="/dashboard" className="nav-link"><span className="nav-icon">01</span>Dashboard</Link><div className="side-label">Management</div><Link href="/groups" className="nav-link"><span className="nav-icon">02</span>Chit groups</Link><Link href="/members" className="nav-link"><span className="nav-icon">03</span>Members</Link><Link href="/auctions" className="nav-link"><span className="nav-icon">04</span>Auctions</Link><Link href="/installments" className="nav-link"><span className="nav-icon">05</span>Installments</Link><Link href="/prizes" className="nav-link"><span className="nav-icon">06</span>Prize payments</Link><div className="side-label">Insights</div><Link href="/reports" className="nav-link active"><span className="nav-icon">07</span>Reports</Link><div className="sidebar-bottom"><div className="user-mini"><div className="avatar">{initials}</div><div><div className="user-name">{displayName}</div><div className="user-role">{profile.role === "owner" ? "Owner / Administrator" : "Staff / Operator"}</div></div></div><form action={signOut}><button className="signout">Sign out</button></form></div></aside>
    <main className="main-area"><header className="topbar"><div className="breadcrumb">Insights&nbsp; / &nbsp;<b>Reports</b></div></header><div className="content">
      <div className="page-heading"><div><div className="eyebrow">FINANCIAL REPORTING</div><h1>Reports</h1><p>Review installment collections, dividends, commissions, and auction payouts.</p></div></div>
      <section className="panel form-panel"><form method="get" className="data-form report-filters"><label>Chit group<select name="group" defaultValue={selectedGroup?.id ?? "all"}><option value="all">All accessible groups</option>{groups?.map((group) => <option value={group.id} key={group.id}>{group.group_code} · {group.name}</option>)}</select></label><label>Month number<input name="month" type="number" min="1" max="120" placeholder="All months" defaultValue={selectedMonth ?? ""}/></label><button className="primary-button" type="submit">View report</button></form></section>
      <section className="stats-grid report-stats"><article className="stat-card"><div className="stat-head">Collected<span className="stat-icon">01</span></div><div className="stat-value stat-money">{money(totalCollected)}</div><div className="stat-foot">Recorded installment payments</div></article><article className="stat-card"><div className="stat-head">Outstanding installments<span className="stat-icon">02</span></div><div className="stat-value stat-money">{money(totalOutstanding)}</div><div className="stat-foot">Remaining net installment balances</div></article><article className="stat-card"><div className="stat-head">Dividends credited<span className="stat-icon">03</span></div><div className="stat-value stat-money">{money(totalDividends)}</div><div className="stat-foot">Member credits in this report</div></article><article className="stat-card"><div className="stat-head">Commission earned<span className="stat-icon">04</span></div><div className="stat-value stat-money">{money(totalCommission)}</div><div className="stat-foot">{reportAuctions.length} finalized auctions</div></article><article className="stat-card"><div className="stat-head">Prize disbursed<span className="stat-icon">05</span></div><div className="stat-value stat-money">{money(totalPrizeDisbursed)}</div><div className="stat-foot">Actual recorded winner payments</div></article><article className="stat-card"><div className="stat-head">Prize outstanding<span className="stat-icon">06</span></div><div className="stat-value stat-money">{money(totalPrizeOutstanding)}</div><div className="stat-foot">Finalized payout less disbursements</div></article></section>
      <section className="panel table-panel"><div className="panel-heading"><div><h2>Member installment report</h2><div className="row-sub">{selectedGroup?.group_code ?? "All groups"}{selectedMonth ? ` · Month ${selectedMonth}` : " · All months"}</div></div><span className="row-sub">{reportInstallments.length} records</span></div><div className="table-scroll"><table><thead><tr><th>Group</th><th>Month</th><th>Member</th><th>Due date</th><th>Gross</th><th>Dividend</th><th>Net due</th><th>Paid</th><th>Balance</th><th>Status</th></tr></thead><tbody>{reportInstallments.map((row) => { const link = Array.isArray(row.chit_members) ? row.chit_members[0] : row.chit_members; const detail = link && (Array.isArray(link.members) ? link.members[0] : link.members); const paid = paidAmount(row); return <tr key={row.id}><td>{link ? groupName(link.group_id) : "—"}</td><td>{row.month_number}</td><td>{detail?.full_name ?? "Member"}<small>#{link?.member_number ?? "—"}</small></td><td>{dateLabel(row.due_date)}</td><td>{money(row.gross_amount_paise)}</td><td>{money(row.dividend_credit_paise)}</td><td>{money(row.net_due_paise)}</td><td>{money(paid)}</td><td><strong>{money(Math.max(0, row.net_due_paise - paid))}</strong></td><td><span className={`status-pill ${row.status}`}>{row.status.replace("_", " ")}</span></td></tr>; })}</tbody></table>{reportInstallments.length === 0 && <div className="empty-state">No installment records match these filters.</div>}</div></section>
      <section className="panel table-panel"><div className="panel-heading"><div><h2>Finalized auction report</h2><div className="row-sub">Discounts are distributed as dividends; commissions are retained.</div></div><span className="row-sub">{reportAuctions.length} auctions</span></div><div className="table-scroll"><table><thead><tr><th>Group</th><th>Month</th><th>Date</th><th>Winner</th><th>Discount</th><th>Commission</th><th>Winner payout</th><th>Disbursed</th><th>Remaining</th></tr></thead><tbody>{reportAuctions.map((auction) => { const disbursed = disbursedByAuction.get(auction.id) ?? 0; return <tr key={auction.id}><td>{groupName(auction.group_id)}</td><td>{auction.month_number}</td><td>{dateLabel(auction.auction_date)}</td><td>{auction.winner_member_id ? memberName(auction.winner_member_id, auction.group_id) : "—"}</td><td>{money(auction.winning_discount_paise ?? 0)}</td><td>{money(auction.commission_paise ?? 0)}</td><td>{money(auction.prize_amount_paise ?? 0)}</td><td>{money(disbursed)}</td><td><strong>{money(Math.max(0, (auction.prize_amount_paise ?? 0) - disbursed))}</strong></td></tr>; })}</tbody></table>{reportAuctions.length === 0 && <div className="empty-state">No finalized auctions match these filters.</div>}</div></section>
    </div></main>
  </div>;
}
