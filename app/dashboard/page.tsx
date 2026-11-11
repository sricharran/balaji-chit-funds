import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { signOut } from "./actions";

export default async function DashboardPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const { data: profile } = await supabase.from("profiles").select("role, full_name, active").eq("id", user.id).maybeSingle();
  if (!profile?.active || !["owner", "staff"].includes(profile.role)) redirect("/login?error=unauthorized");
  const [{ count: groupCount }, { count: memberCount }, { data: installments }, { data: payments }, { data: finalizedAuctions }, { data: prizeDisbursements }, { data: upcomingAuctions }] = await Promise.all([
    supabase.from("chit_groups").select("id", { count: "exact", head: true }).eq("status", "active"),
    supabase.from("members").select("id", { count: "exact", head: true }),
    supabase.from("installments").select("id,net_due_paise"),
    supabase.from("payments").select("installment_id,amount_paise,payment_date"),
    supabase.from("auctions").select("id,group_id,month_number,auction_date,commission_paise,prize_amount_paise,chit_groups(name,group_code)").eq("status", "finalized").order("auction_date", { ascending: false }),
    supabase.from("prize_disbursements").select("auction_id,amount_paise"),
    supabase.from("auctions").select("id,group_id,month_number,auction_date,status,chit_groups(name,group_code)").in("status", ["draft", "open"]).order("auction_date", { ascending: true }).limit(6),
  ]);

  const indiaToday = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Kolkata", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date());
  const monthStart = `${indiaToday.slice(0, 7)}-01`;
  const nextMonth = new Date(`${monthStart}T00:00:00+05:30`);
  nextMonth.setMonth(nextMonth.getMonth() + 1);
  const monthEnd = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Kolkata", year: "numeric", month: "2-digit", day: "2-digit" }).format(nextMonth);
  const paymentsThisMonth = (payments ?? []).filter((payment) => payment.payment_date >= monthStart && payment.payment_date < monthEnd);
  const collectedThisMonth = paymentsThisMonth.reduce((sum, payment) => sum + payment.amount_paise, 0);
  const paidByInstallment = new Map<string, number>();
  for (const payment of payments ?? []) paidByInstallment.set(payment.installment_id, (paidByInstallment.get(payment.installment_id) ?? 0) + payment.amount_paise);
  const pendingInstallments = (installments ?? []).reduce((sum, installment) => sum + Math.max(0, installment.net_due_paise - (paidByInstallment.get(installment.id) ?? 0)), 0);
  const totalCommission = (finalizedAuctions ?? []).reduce((sum, auction) => sum + (auction.commission_paise ?? 0), 0);
  const totalPrizeOutstanding = Math.max(0, (finalizedAuctions ?? []).reduce((sum, auction) => sum + (auction.prize_amount_paise ?? 0), 0) - (prizeDisbursements ?? []).reduce((sum, row) => sum + row.amount_paise, 0));
  const money = (paise: number) => new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 2 }).format(paise / 100);
  const groupInfo = (relation: { name: string; group_code: string } | { name: string; group_code: string }[] | null) => Array.isArray(relation) ? relation[0] : relation;

  const displayName: string = profile.full_name?.trim() || user.email?.split("@")[0] || "Team member";
  const initials = displayName.split(/\s+/).map((part: string) => part[0]).join("").slice(0, 2).toUpperCase();
  const isOwner = profile.role === "owner";
  const stats = [
    { label: "Active chit groups", value: String(groupCount ?? 0), note: "Group overview", icon: "01" },
    { label: "Registered members", value: String(memberCount ?? 0), note: "Across all groups", icon: "02" },
    { label: "Collected this month", value: money(collectedThisMonth), note: `${paymentsThisMonth.length} recorded payments`, icon: "03" },
    { label: "Pending installments", value: money(pendingInstallments), note: "Outstanding across scheduled dues", icon: "04" },
    { label: "Total commission earned", value: money(totalCommission), note: `${finalizedAuctions?.length ?? 0} finalized auctions`, icon: "05" },
    { label: "Prizes pending", value: money(totalPrizeOutstanding), note: "Finalized payouts not yet disbursed", icon: "06" },
  ];
  return <div className="dashboard-shell">
    <aside className="sidebar">
      <div className="brand-logo"><span className="brand-mark">B</span><span>BALAJI <span style={{fontWeight:500,opacity:.7}}>CHIT FUNDS</span></span></div>
      <div className="side-label">Workspace</div><Link href="/dashboard" className="nav-link active"><span className="nav-icon">01</span>Dashboard</Link>
      <div className="side-label">Management</div>
      <Link href="/groups" className="nav-link"><span className="nav-icon">02</span>Chit groups</Link>
      <Link href="/members" className="nav-link"><span className="nav-icon">03</span>Members</Link>
      <Link href="/auctions" className="nav-link"><span className="nav-icon">04</span>Auctions</Link>
      <Link href="/installments" className="nav-link"><span className="nav-icon">05</span>Installments</Link>
      <Link href="/prizes" className="nav-link"><span className="nav-icon">06</span>Prize payments</Link>
      <div className="side-label">Insights</div><Link href="/reports" className="nav-link"><span className="nav-icon">07</span>Reports</Link>
      <div className="sidebar-bottom"><div className="user-mini"><div className="avatar">{initials}</div><div><div className="user-name">{displayName}</div><div className="user-role">{isOwner ? "Owner / Administrator" : "Staff / Operator"}</div></div></div><form action={signOut}><button className="signout">Sign out</button></form></div>
    </aside>
    <main className="main-area">
      <header className="topbar"><div className="breadcrumb">Workspace&nbsp; / &nbsp;<b>Dashboard</b></div><div className="topbar-right"><span className="today">Balaji Chit Funds</span><div className="avatar">{initials}</div></div></header>
      <div className="content">
        <div className="page-heading"><div><div className="eyebrow">OVERVIEW</div><h1>Welcome, {displayName.split(" ")[0]}</h1><p>Here is your business overview.</p></div><div className="welcome-chip">{isOwner ? "Administrator access" : "Staff access"}</div></div>
        <section className="stats-grid">{stats.map((stat) => <article className="stat-card" key={stat.label}><div className="stat-head">{stat.label}<span className="stat-icon">{stat.icon}</span></div><div className="stat-value">{stat.value}</div><div className="stat-foot">{stat.note}</div></article>)}</section>
        <section className="content-grid">
          <article className="panel"><div className="panel-heading"><h2>Upcoming auctions</h2><Link href="/auctions" className="row-sub">View all</Link></div>{upcomingAuctions?.length ? <div className="activity-list">{upcomingAuctions.map((auction) => { const group = groupInfo(auction.chit_groups); return <div className="activity-row" key={auction.id}><div><strong>{group?.group_code ?? "Chit group"} · Month {auction.month_number}</strong><div className="row-sub">{group?.name ?? ""}</div></div><div className="activity-meta"><span className={`status-pill ${auction.status}`}>{auction.status}</span><span className="row-sub">{new Intl.DateTimeFormat("en-IN", { dateStyle: "medium", timeZone: "Asia/Kolkata" }).format(new Date(`${auction.auction_date}T00:00:00+05:30`))}</span></div></div>; })}</div> : <div className="row-sub" style={{padding:"20px 0 7px"}}>No draft or open auctions scheduled.</div>}</article>
          <article className="panel"><div className="panel-heading"><h2>Recently finalized auctions</h2><Link href="/auctions" className="row-sub">View all</Link></div>{finalizedAuctions?.length ? <div className="activity-list">{finalizedAuctions.slice(0, 6).map((auction) => { const group = groupInfo(auction.chit_groups); return <div className="activity-row" key={auction.id}><div><strong>{group?.group_code ?? "Chit group"} · Month {auction.month_number}</strong><div className="row-sub">{group?.name ?? ""} · {new Intl.DateTimeFormat("en-IN", { dateStyle: "medium", timeZone: "Asia/Kolkata" }).format(new Date(`${auction.auction_date}T00:00:00+05:30`))}</div></div><div className="activity-meta"><strong>{money(auction.commission_paise ?? 0)}</strong><span className="row-sub">commission</span></div></div>; })}</div> : <div className="row-sub" style={{padding:"20px 0 7px"}}>No finalized auctions yet.</div>}</article>
        </section>
        <div className="section-label">Quick access</div>
        <section className="quick-grid"><Link className="quick-card" href="/groups"><span className="quick-icon">02</span><div><div className="quick-title">Chit groups</div><div className="quick-sub">Manage group setup</div></div></Link><Link className="quick-card" href="/members"><span className="quick-icon">03</span><div><div className="quick-title">Members</div><div className="quick-sub">Open member directory</div></div></Link></section>
      </div>
    </main>
  </div>;
}
