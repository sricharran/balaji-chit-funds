import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { signOut } from "../dashboard/actions";
import { createGroup } from "./actions";

const money = (paise: number) => new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 2 }).format(paise / 100);

export default async function GroupsPage({ searchParams }: { searchParams: Promise<{ error?: string; created?: string; deleted?: string }> }) {
  const query = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: profile } = await supabase.from("profiles").select("role, full_name, active").eq("id", user.id).maybeSingle();
  if (!profile?.active || !["owner", "staff"].includes(profile.role)) redirect("/login?error=unauthorized");
  const { data: groups } = await supabase.from("chit_groups").select("id,name,group_code,chit_value_paise,duration_months,member_capacity,monthly_installment_paise,commission_amount_paise,start_date,status,chit_members(member_number,has_won,status,members(full_name))").order("created_at", { ascending: false });
  const isOwner = profile.role === "owner";

  return <div className="dashboard-shell"><aside className="sidebar"><div className="brand-logo"><span className="brand-mark">B</span><span>BALAJI <span style={{fontWeight:500,opacity:.7}}>CHIT FUNDS</span></span></div><div className="side-label">Workspace</div><Link href="/dashboard" className="nav-link"><span className="nav-icon">01</span>Dashboard</Link><div className="side-label">Management</div><Link href="/groups" className="nav-link active"><span className="nav-icon">02</span>Chit groups</Link><Link href="/members" className="nav-link"><span className="nav-icon">03</span>Members</Link><Link href="/auctions" className="nav-link"><span className="nav-icon">04</span>Auctions</Link><Link href="/installments" className="nav-link"><span className="nav-icon">05</span>Installments</Link><Link href="/prizes" className="nav-link"><span className="nav-icon">06</span>Prize payments</Link><div className="side-label">Insights</div><Link href="/reports" className="nav-link"><span className="nav-icon">07</span>Reports</Link><div className="sidebar-bottom"><div className="user-mini"><div className="avatar">{(profile.full_name || user.email || "U").slice(0,1).toUpperCase()}</div><div><div className="user-name">{profile.full_name || user.email}</div><div className="user-role">{isOwner ? "Owner / Administrator" : "Staff / Operator"}</div></div></div><form action={signOut}><button className="signout">Sign out</button></form></div></aside>
    <main className="main-area"><header className="topbar"><div className="breadcrumb">Management&nbsp; / &nbsp;<b>Chit groups</b></div></header><div className="content"><div className="page-heading"><div><div className="eyebrow">GROUP MANAGEMENT</div><h1>Chit groups</h1><p>Configure group terms and track enrollment.</p></div></div>
      {query.created && <div className="notice success">Group created as a draft. It will not be used for financial operations until activated.</div>}
      {query.deleted && <div className="notice success">The chit group and its group-specific records were permanently deleted.</div>}
      {query.error && <div className="form-error">{query.error === "invalid" ? "Check the group details and enter valid positive amounts." : "Could not save this group. Please try again."}</div>}
      {isOwner && <section className="panel form-panel"><div className="panel-heading"><h2>Create a group</h2><span className="row-sub">New groups start as drafts</span></div><form action={createGroup} className="data-form">
        <label>Group name<input name="name" required maxLength={100} placeholder="e.g. Balaji Group 01" /></label>
        <label>Total chit value (₹)<input name="chit_value" type="number" min="0.01" step="0.01" required placeholder="200000" /></label>
        <label>Duration (months)<input name="duration_months" type="number" min="1" max="120" step="1" defaultValue="20" required /></label>
        <label>Member capacity<input name="member_capacity" type="number" min="1" max="1000" step="1" defaultValue="20" required /></label>
        <label>Commission per monthly auction (₹)<input name="commission_amount" type="number" min="0" step="0.01" required placeholder="4000" /></label>
        <p className="row-sub">Base monthly installment is total chit value divided by the configured duration.</p>
        <label>Planned start date<input name="start_date" type="date" required /></label>
        <div className="form-actions"><button className="primary-button" type="submit">Save draft group</button></div>
      </form></section>}
      <section className="panel table-panel"><div className="panel-heading"><h2>All groups</h2><span className="row-sub">{groups?.length ?? 0} groups</span></div><div className="table-scroll"><table><thead><tr><th>Group</th><th>Chit value</th><th>Installment</th><th>Commission / auction</th><th>Members</th><th>Chits taken</th><th>Status</th></tr></thead><tbody>{groups?.map((group) => { const enrolled = group.chit_members?.length ?? 0; const winners = (group.chit_members ?? []).filter((member) => member.has_won); return <tr key={group.id}><td><Link href={`/groups/${group.id}`} className="table-primary-link"><strong>{group.name}</strong></Link><small>{group.group_code} · {group.duration_months} months · starts {group.start_date}</small></td><td>{money(group.chit_value_paise)}</td><td>{money(group.monthly_installment_paise)}</td><td>{money(group.commission_amount_paise)}</td><td>{enrolled} / {group.member_capacity}</td><td><strong>{winners.length} / {group.member_capacity}</strong><small>{winners.length ? winners.map((winner) => { const detail = Array.isArray(winner.members) ? winner.members[0] : winner.members; return `#${winner.member_number} ${detail?.full_name ?? "Member"}`; }).join(", ") : "No member has won yet"}</small></td><td><span className={`status-pill ${group.status}`}>{group.status}</span></td></tr>; })}</tbody></table>{(!groups || groups.length === 0) && <div className="empty-state">No groups yet. Create a draft group to get started.</div>}</div></section>
    </div></main></div>;
}
