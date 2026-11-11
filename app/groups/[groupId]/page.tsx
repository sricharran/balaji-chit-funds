import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { signOut } from "../../dashboard/actions";
import { activateGroup, deleteGroup, enrollMember, saveGroupStartDate } from "./actions";

const money = (paise: number) => new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 2 }).format(paise / 100);
const messages: Record<string, string> = {
  notfound: "That group could not be found or you do not have access to it.",
  locked: "This group is no longer a draft, so its roster cannot be changed.",
  full: "The group has reached its member capacity.",
  duplicate: "This member is already enrolled in the group.",
  member: "The selected member could not be found.",
  save: "Could not enroll the member. Please try again.",
  notfull: "Enroll members into every numbered slot before activating the group.",
  startdate: "Add a planned start date before activating the group.",
  activate: "Could not activate the group. Refresh and try again.",
  dateinvalid: "Enter a valid planned start date.",
  deleteconfirm: "Confirm the checkbox and enter this groupâ€™s exact code to delete it.",
  deletemigration: "The group deletion database function is unavailable. Apply migration 202611110002_delete_chit_group_and_related_data.sql in Supabase, then retry.",
  deleteblocked: "The database still has a related record that prevents deletion. Check the server log for the constraint name.",
  deletefailed: "The group could not be deleted. Refresh and try again.",
};

export default async function GroupDetailPage({ params, searchParams }: { params: Promise<{ groupId: string }>; searchParams: Promise<{ error?: string; enrolled?: string; activated?: string; datesaved?: string }> }) {
  const [{ groupId }, query] = await Promise.all([params, searchParams]);
  if (!/^[0-9a-f-]{36}$/i.test(groupId)) redirect("/groups?error=notfound");

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: profile } = await supabase.from("profiles").select("role, full_name, active").eq("id", user.id).maybeSingle();
  if (!profile?.active || !["owner", "staff"].includes(profile.role)) redirect("/login?error=unauthorized");

  const { data: group } = await supabase.from("chit_groups").select("id,name,group_code,chit_value_paise,duration_months,member_capacity,monthly_installment_paise,commission_amount_paise,start_date,status,activated_at").eq("id", groupId).maybeSingle();
  if (!group) redirect("/groups?error=notfound");

  const { data: roster } = await supabase.from("chit_members")
    .select("id,member_id,member_number,status,has_won,enrolled_at,members(id,full_name,phone,email)")
    .eq("group_id", groupId).order("member_number", { ascending: true });
  const isOwner = profile.role === "owner";
  const { data: allMembers } = isOwner && group.status === "draft"
    ? await supabase.from("members").select("id,full_name,phone").order("full_name")
    : { data: [] };
  const enrolledIds = new Set((roster ?? []).map((row) => row.member_id));
  const availableMembers = (allMembers ?? []).filter((member) => !enrolledIds.has(member.id));
  const activeCount = (roster ?? []).filter((row) => row.status === "active").length;
  const isFull = activeCount === group.member_capacity;
  const displayName = profile.full_name || user.email || "Team member";
  const initials = displayName.slice(0, 1).toUpperCase();

  return <div className="dashboard-shell"><aside className="sidebar">
    <div className="brand-logo"><span className="brand-mark">B</span><span>BALAJI <span style={{fontWeight:500,opacity:.7}}>CHIT FUNDS</span></span></div>
    <div className="side-label">Workspace</div><Link href="/dashboard" className="nav-link"><span className="nav-icon">01</span>Dashboard</Link>
    <div className="side-label">Management</div><Link href="/groups" className="nav-link active"><span className="nav-icon">02</span>Chit groups</Link><Link href="/members" className="nav-link"><span className="nav-icon">03</span>Members</Link><Link href="/auctions" className="nav-link"><span className="nav-icon">04</span>Auctions</Link><Link href="/installments" className="nav-link"><span className="nav-icon">05</span>Installments</Link><Link href="/prizes" className="nav-link"><span className="nav-icon">06</span>Prize payments</Link><div className="side-label">Insights</div><Link href="/reports" className="nav-link"><span className="nav-icon">07</span>Reports</Link>
    <div className="sidebar-bottom"><div className="user-mini"><div className="avatar">{initials}</div><div><div className="user-name">{displayName}</div><div className="user-role">{isOwner ? "Owner / Administrator" : "Staff / Operator"}</div></div></div><form action={signOut}><button className="signout">Sign out</button></form></div>
  </aside><main className="main-area"><header className="topbar"><div className="breadcrumb"><Link href="/groups">Chit groups</Link>&nbsp; / &nbsp;<b>{group.group_code}</b></div></header>
    <div className="content"><div className="page-heading"><div><div className="eyebrow">GROUP SETUP</div><h1>{group.name}</h1><p>{group.group_code} Â· {group.duration_months} months Â· {money(group.chit_value_paise)} chit value</p></div><span className={`status-pill ${group.status}`}>{group.status}</span></div>
      {query.enrolled && <div className="notice success">Member enrolled and assigned member number {query.enrolled}.</div>}
      {query.activated && <div className="notice success">Group activated. Its terms and roster are now locked.</div>}
      {query.datesaved && <div className="notice success">Planned start date saved.</div>}
      {query.error && messages[query.error] && <div className="form-error">{messages[query.error]}</div>}

      <section className="stats-grid group-stats"><article className="stat-card"><div className="stat-head">Enrolled members<span className="stat-icon">01</span></div><div className="stat-value">{activeCount} / {group.member_capacity}</div><div className="stat-foot">Active roster positions</div></article><article className="stat-card"><div className="stat-head">Monthly installment<span className="stat-icon">02</span></div><div className="stat-value stat-money">{money(group.monthly_installment_paise)}</div><div className="stat-foot">Per member, per month</div></article><article className="stat-card"><div className="stat-head">Commission per auction<span className="stat-icon">03</span></div><div className="stat-value stat-money">{money(group.commission_amount_paise)}</div><div className="stat-foot">Fixed configured amount</div></article><article className="stat-card"><div className="stat-head">Planned start<span className="stat-icon">04</span></div><div className="stat-value stat-date">{group.start_date || "Not set"}</div><div className="stat-foot">Group schedule</div></article></section>

      {isOwner && group.status === "draft" && <section className="panel form-panel enrollment-panel"><div className="panel-heading"><div><h2>Enroll a member</h2><div className="row-sub">The next available member number is assigned automatically.</div></div></div>
        {isFull ? <div className="empty-state compact-empty">All {group.member_capacity} member positions are filled.</div> : availableMembers.length > 0 ? <form action={enrollMember} className="inline-enrollment"><input type="hidden" name="group_id" value={group.id}/><label className="member-select-label">Select member<select name="member_id" required defaultValue=""><option value="" disabled>Choose a member</option>{availableMembers.map((member) => <option key={member.id} value={member.id}>{member.full_name}{member.phone ? ` Â· ${member.phone}` : ""}</option>)}</select></label><button className="primary-button" type="submit">Enroll member</button></form> : <div className="empty-state compact-empty">No unassigned members are available. Register a member first, or all registered members may already be enrolled in this group.</div>}
        <form action={saveGroupStartDate} className="start-date-form"><input type="hidden" name="group_id" value={group.id}/><label>Planned start date<input name="start_date" type="date" required defaultValue={group.start_date ?? ""}/></label><button className="secondary-button" type="submit">Save date</button></form>
        <div className="activation-box"><div><strong>Activate this group</strong><p>{!isFull ? `Enroll ${group.member_capacity - activeCount} more member${group.member_capacity - activeCount === 1 ? "" : "s"} to activate.` : !group.start_date ? "Set a planned start date before activation." : "Capacity is filled. Activation locks the roster and group terms."}</p></div><form action={activateGroup}><input type="hidden" name="group_id" value={group.id}/><button className="primary-button" type="submit" disabled={!isFull || !group.start_date}>Activate group</button></form></div>
      </section>}

      {group.status === "active" && <div className="notice success">Activated {group.activated_at ? new Intl.DateTimeFormat("en-IN", {dateStyle:"medium",timeZone:"Asia/Kolkata"}).format(new Date(group.activated_at)) : ""}. Group terms and member roster are locked.</div>}
      <section className="panel table-panel"><div className="panel-heading"><div><h2>Member roster</h2><div className="row-sub">Members retain separate accounts in each group.</div></div><span className="row-sub">{activeCount} / {group.member_capacity}</span></div><div className="table-scroll"><table><thead><tr><th>Number</th><th>Member</th><th>Phone</th><th>Enrolled</th><th>Status</th><th>Chit taken</th></tr></thead><tbody>{roster?.map((row) => { const member = Array.isArray(row.members) ? row.members[0] : row.members; return <tr key={row.id}><td><strong>{row.member_number ?? "â€”"}</strong></td><td>{member?.full_name ?? "Member unavailable"}</td><td>{member?.phone || "â€”"}</td><td>{new Intl.DateTimeFormat("en-IN", {dateStyle:"medium",timeZone:"Asia/Kolkata"}).format(new Date(row.enrolled_at))}</td><td><span className={`status-pill ${row.status}`}>{row.status}</span></td><td>{row.has_won ? "Done" : "â€”"}</td></tr>; })}</tbody></table>{(!roster || roster.length === 0) && <div className="empty-state">No members enrolled yet.</div>}</div></section>
      {isOwner && <details className="panel delete-group-panel"><summary>Delete this chit group</summary><div className="delete-group-warning"><strong>Permanently delete {group.name} and its related data?</strong><p>This removes its auctions, bids, dividends, installment schedules, payments, ledger entries, prize disbursements, and member enrollments. Member directory records are kept if they are still used by another group or have other dividend history.</p><form action={deleteGroup} className="delete-group-form"><input type="hidden" name="group_id" value={group.id}/><label className="delete-confirm-check"><input type="checkbox" name="confirm_deletion" value="yes" required/>I understand this permanently removes this group&apos;s records.</label><label>Type <strong>{group.group_code}</strong> to confirm<input name="confirmation_code" required maxLength={32} autoComplete="off" placeholder={group.group_code}/></label><button className="danger-button" type="submit">Permanently delete group</button></form></div></details>}
    </div></main></div>;
}
