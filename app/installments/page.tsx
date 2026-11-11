import Link from "next/link";
import { randomUUID } from "node:crypto";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { signOut } from "../dashboard/actions";
import { generateInstallments, recordInstallmentPayment } from "./actions";

const money = (paise: number) => new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 2 }).format(paise / 100);
const todayInIndia = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Kolkata", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date());
type MemberRecord = { full_name: string; phone: string | null };
type ChitMemberRecord = { member_number: number | null; member_id: string; members: MemberRecord | MemberRecord[] | null };
type PaymentRecord = { amount_paise: number; payment_date: string; payment_method: string };
type InstallmentRecord = {
  id: string;
  chit_member_id: string;
  month_number: number;
  due_date: string;
  gross_amount_paise: number;
  dividend_credit_paise: number;
  net_due_paise: number;
  status: string;
  chit_members: ChitMemberRecord | ChitMemberRecord[] | null;
  payments: PaymentRecord[] | null;
};
const errors: Record<string, string> = {
  owner: "Only the owner can generate monthly installments.", invalid: "Check the group, month, date, and payment details.", exists: "Installments have already been generated for this group and month.", inactive: "The group must be active before installments can be generated.", month: "Choose a month within this group's configured duration.", roster: "The group's active member roster is incomplete.", generate: "Could not generate the installment schedule.", exceeds: "Payment exceeds the remaining balance for this installment.", unauthorized: "You do not have access to record a payment for this installment.", payment: "Could not record the payment. Refresh and try again.",
};

export default async function InstallmentsPage({ searchParams }: { searchParams: Promise<{ group_id?: string; month?: string; error?: string; generated?: string; paid?: string }> }) {
  const query = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: profile } = await supabase.from("profiles").select("role,full_name,active").eq("id", user.id).maybeSingle();
  if (!profile?.active || !["owner", "staff"].includes(profile.role)) redirect("/login?error=unauthorized");

  const { data: groups } = await supabase.from("chit_groups").select("id,name,group_code,duration_months,monthly_installment_paise,chit_value_paise,member_capacity,status").order("group_code");
  const selectedGroup = groups?.find((group) => group.id === query.group_id) ?? groups?.[0] ?? null;
  const requestedMonth = Number(query.month ?? "1");
  const month = Number.isInteger(requestedMonth) && requestedMonth >= 1 && requestedMonth <= (selectedGroup?.duration_months ?? 1) ? requestedMonth : 1;
  const { data: monthAuction } = selectedGroup
    ? await supabase.from("auctions").select("id,status,selection_method,winning_discount_paise,commission_paise").eq("group_id", selectedGroup.id).eq("month_number", month).maybeSingle()
    : { data: null };
  const { data: monthDividends } = monthAuction?.status === "finalized"
    ? await supabase.from("dividends").select("id,dividend_amount_paise").eq("auction_id", monthAuction.id)
    : { data: [] };
  const dividendTotal = (monthDividends ?? []).reduce((sum, row) => sum + row.dividend_amount_paise, 0);
  const expectedDividendPool = monthAuction?.status === "finalized" ? monthAuction.winning_discount_paise ?? 0 : 0;
  const historicalDividendMismatch = monthAuction?.status === "finalized"
    && ((monthDividends?.length ?? 0) !== (selectedGroup?.member_capacity ?? 0) || dividendTotal !== expectedDividendPool);
  let installments: InstallmentRecord[] = [];
  if (selectedGroup) {
    const { data: memberships } = await supabase.from("chit_members").select("id").eq("group_id", selectedGroup.id).eq("status", "active");
    const membershipIds = (memberships ?? []).map((membership) => membership.id);
    if (membershipIds.length > 0) {
      const { data } = await supabase.from("installments")
        .select("id,chit_member_id,month_number,due_date,gross_amount_paise,dividend_credit_paise,net_due_paise,status,chit_members(member_number,member_id,members(full_name,phone)),payments(amount_paise,payment_date,payment_method)")
        .in("chit_member_id", membershipIds).eq("month_number", month).order("due_date");
      installments = data ?? [];
    }
  }
  const isOwner = profile.role === "owner";
  const totalGross = installments.reduce((sum, row) => sum + row.gross_amount_paise, 0);
  const totalPaid = installments.reduce((sum, row) => sum + (row.payments ?? []).reduce((paid: number, payment: {amount_paise:number}) => paid + payment.amount_paise, 0), 0);
  const pending = installments.reduce((sum, row) => {
    const paid = (row.payments ?? []).reduce((paid: number, payment: {amount_paise:number}) => paid + payment.amount_paise, 0);
    return sum + Math.max(0, row.net_due_paise - paid);
  }, 0);
  const displayName = profile.full_name || user.email || "Team member";

  return <div className="dashboard-shell"><aside className="sidebar"><div className="brand-logo"><span className="brand-mark">B</span><span>BALAJI <span style={{fontWeight:500,opacity:.7}}>CHIT FUNDS</span></span></div><div className="side-label">Workspace</div><Link href="/dashboard" className="nav-link"><span className="nav-icon">01</span>Dashboard</Link><div className="side-label">Management</div><Link href="/groups" className="nav-link"><span className="nav-icon">02</span>Chit groups</Link><Link href="/members" className="nav-link"><span className="nav-icon">03</span>Members</Link><Link href="/auctions" className="nav-link"><span className="nav-icon">04</span>Auctions</Link><Link href="/installments" className="nav-link active"><span className="nav-icon">05</span>Installments</Link><Link href="/prizes" className="nav-link"><span className="nav-icon">06</span>Prize payments</Link><div className="side-label">Insights</div><Link href="/reports" className="nav-link"><span className="nav-icon">07</span>Reports</Link><div className="sidebar-bottom"><div className="user-mini"><div className="avatar">{displayName.slice(0,1).toUpperCase()}</div><div><div className="user-name">{displayName}</div><div className="user-role">{isOwner ? "Owner / Administrator" : "Staff / Operator"}</div></div></div><form action={signOut}><button className="signout">Sign out</button></form></div></aside>
    <main className="main-area"><header className="topbar"><div className="breadcrumb">Management&nbsp; / &nbsp;<b>Installments</b></div></header><div className="content"><div className="page-heading"><div><div className="eyebrow">MONTHLY COLLECTIONS</div><h1>Installments</h1><p>Monthly gross dues, dividend credits, recorded payments, and balances by member.</p></div></div>
      {query.generated && <div className="notice success">Generated {query.generated} monthly installment records.</div>}{query.paid && <div className="notice success">Payment recorded and member balance updated.</div>}{query.error && errors[query.error] && <div className="form-error">{errors[query.error]}</div>}
      {!groups || groups.length === 0 ? <section className="panel empty-state">No groups are available to this account.</section> : <>
        <section className="panel form-panel"><form method="get" className="data-form selection-form"><label>Chit group<select name="group_id" defaultValue={selectedGroup?.id}>{groups.map((group) => <option key={group.id} value={group.id}>{group.group_code} · {group.name} ({group.status})</option>)}</select></label><label>Month number<input name="month" type="number" min="1" max={selectedGroup?.duration_months} defaultValue={month}/></label><div className="form-actions"><button className="secondary-button" type="submit">View month</button></div></form></section>
        {monthAuction?.status !== "finalized" && <div className="notice">No finalized auction for month {month} yet. Dividend credits will appear after the auction is finalized.</div>}
        {historicalDividendMismatch && monthAuction?.status === "finalized" && <div className="notice">This finalized month differs from the current calculation rule. Its historical auction and dividend records are preserved.</div>}
        {isOwner && selectedGroup?.status === "active" && installments.length === 0 && <section className="panel form-panel"><div className="panel-heading"><div><h2>Generate monthly dues</h2><div className="row-sub">Creates one gross installment for each active member. Choose the due date for this month.</div></div></div><form action={generateInstallments} className="data-form selection-form"><input type="hidden" name="group_id" value={selectedGroup.id}/><input type="hidden" name="month_number" value={month}/><label>Due date<input name="due_date" type="date" required/></label><label>Gross amount per member<input value={money(selectedGroup.monthly_installment_paise)} readOnly/></label><div className="form-actions"><button className="primary-button" type="submit">Generate {month === 1 ? "month 1" : `month ${month}`} dues</button></div></form></section>}
        <section className="stats-grid installment-stats"><article className="stat-card"><div className="stat-head">Members with dues<span className="stat-icon">01</span></div><div className="stat-value">{installments.length}</div><div className="stat-foot">{selectedGroup?.group_code} · Month {month}</div></article><article className="stat-card"><div className="stat-head">Gross installments<span className="stat-icon">02</span></div><div className="stat-value stat-money">{money(totalGross)}</div><div className="stat-foot">Scheduled amount</div></article><article className="stat-card"><div className="stat-head">Payments collected<span className="stat-icon">03</span></div><div className="stat-value stat-money">{money(totalPaid)}</div><div className="stat-foot">Actual recorded payments</div></article><article className="stat-card"><div className="stat-head">Balance outstanding<span className="stat-icon">04</span></div><div className="stat-value stat-money">{money(pending)}</div><div className="stat-foot">After recorded payments</div></article></section>
        <section className="panel table-panel"><div className="panel-heading"><div><h2>Member installments</h2><div className="row-sub">Dividend credits are recorded separately from cash collections.</div></div><span className="row-sub">{installments.length} records</span></div><div className="table-scroll"><table><thead><tr><th>Member</th><th>Due date</th><th>Gross due</th><th>Dividend credit</th><th>Net due</th><th>Paid</th><th>Balance</th><th>Status</th>{installments.length > 0 && <th>Record payment</th>}</tr></thead><tbody>{installments.map((row) => { const chitMember = Array.isArray(row.chit_members) ? row.chit_members[0] : row.chit_members; const member = chitMember && (Array.isArray(chitMember.members) ? chitMember.members[0] : chitMember.members); const paid = (row.payments ?? []).reduce((sum: number, payment: {amount_paise:number}) => sum + payment.amount_paise, 0); const balance = Math.max(0, row.net_due_paise - paid); return <tr key={row.id}><td><strong>{member?.full_name ?? "Member"}</strong><small>Member #{chitMember?.member_number ?? "—"}</small></td><td>{new Intl.DateTimeFormat("en-IN", {dateStyle:"medium",timeZone:"Asia/Kolkata"}).format(new Date(row.due_date))}</td><td>{money(row.gross_amount_paise)}</td><td>{money(row.dividend_credit_paise)}</td><td>{money(row.net_due_paise)}</td><td>{money(paid)}</td><td><strong>{money(balance)}</strong></td><td><span className={`status-pill ${row.status}`}>{row.status.replace("_", " ")}</span></td>{balance > 0 && <td><details className="payment-editor"><summary>Record payment</summary><form action={recordInstallmentPayment} className="contact-edit-form"><input type="hidden" name="installment_id" value={row.id}/><input type="hidden" name="group_id" value={selectedGroup?.id}/><input type="hidden" name="month_number" value={month}/><input type="hidden" name="request_key" value={randomUUID()}/><label>Amount (₹)<input name="amount" type="number" min="0.01" max={(balance / 100).toFixed(2)} step="0.01" defaultValue={(balance / 100).toFixed(2)} required/></label><label>Payment method<select name="payment_method" defaultValue="cash"><option value="cash">Cash</option><option value="upi">UPI</option><option value="bank_transfer">Bank transfer</option></select></label><label>Payment date<input name="payment_date" type="date" defaultValue={todayInIndia} required/></label><label>Reference<input name="reference" maxLength={120}/></label><button className="secondary-button" type="submit">Save payment</button></form></details></td>}</tr>; })}</tbody></table>{installments.length === 0 && <div className="empty-state">No installment schedule for this group and month yet.</div>}</div></section>
      </>}
    </div></main></div>;
}
