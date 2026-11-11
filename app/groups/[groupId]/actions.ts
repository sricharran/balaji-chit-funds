"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

async function requireOwner() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: profile } = await supabase.from("profiles").select("role,active").eq("id", user.id).maybeSingle();
  if (profile?.role !== "owner" || !profile.active) redirect("/dashboard");
  return supabase;
}

function enrollmentError(message: string): string {
  if (message.includes("GROUP_NOT_FOUND")) return "notfound";
  if (message.includes("GROUP_NOT_DRAFT")) return "locked";
  if (message.includes("GROUP_FULL")) return "full";
  if (message.includes("MEMBER_ALREADY_ENROLLED")) return "duplicate";
  if (message.includes("MEMBER_NOT_FOUND")) return "member";
  return "save";
}

export async function enrollMember(formData: FormData) {
  const supabase = await requireOwner();
  const groupId = String(formData.get("group_id") ?? "");
  const memberId = String(formData.get("member_id") ?? "");
  if (!/^[0-9a-f-]{36}$/i.test(groupId) || !/^[0-9a-f-]{36}$/i.test(memberId)) redirect("/groups?error=invalid");

  const { data: number, error } = await supabase.rpc("enroll_member", { target_group: groupId, target_member: memberId });
  if (error) redirect(`/groups/${groupId}?error=${enrollmentError(error.message)}`);
  redirect(`/groups/${groupId}?enrolled=${number}`);
}

export async function activateGroup(formData: FormData) {
  const supabase = await requireOwner();
  const groupId = String(formData.get("group_id") ?? "");
  if (!/^[0-9a-f-]{36}$/i.test(groupId)) redirect("/groups?error=invalid");

  const { error } = await supabase.rpc("activate_chit_group", { target_group: groupId });
  if (error) {
    const code = error.message.includes("GROUP_NOT_FULL") ? "notfull"
      : error.message.includes("GROUP_START_DATE_REQUIRED") ? "startdate"
      : error.message.includes("GROUP_NOT_DRAFT") ? "locked"
      : error.message.includes("GROUP_NOT_FOUND") ? "notfound" : "activate";
    redirect(`/groups/${groupId}?error=${code}`);
  }
  redirect(`/groups/${groupId}?activated=1`);
}

export async function saveGroupStartDate(formData: FormData) {
  const supabase = await requireOwner();
  const groupId = String(formData.get("group_id") ?? "");
  const startDate = String(formData.get("start_date") ?? "");
  if (!/^[0-9a-f-]{36}$/i.test(groupId) || !/^\d{4}-\d{2}-\d{2}$/.test(startDate)) redirect("/groups?error=invalid");
  const date = new Date(`${startDate}T00:00:00.000Z`);
  if (Number.isNaN(date.valueOf()) || date.toISOString().slice(0, 10) !== startDate) redirect(`/groups/${groupId}?error=dateinvalid`);

  const { data, error } = await supabase.from("chit_groups").update({ start_date: startDate }).eq("id", groupId).eq("status", "draft").select("id").maybeSingle();
  if (error || !data) redirect(`/groups/${groupId}?error=locked`);
  redirect(`/groups/${groupId}?datesaved=1`);
}

export async function deleteGroup(formData: FormData) {
  const supabase = await requireOwner();
  const groupId = String(formData.get("group_id") ?? "");
  const confirmationCode = String(formData.get("confirmation_code") ?? "").trim();
  const confirmed = formData.get("confirm_deletion") === "yes";
  if (!/^[0-9a-f-]{36}$/i.test(groupId) || !confirmed || !confirmationCode || confirmationCode.length > 32) {
    redirect(`/groups/${groupId}?error=deleteconfirm`);
  }

  const { error } = await supabase.rpc("delete_chit_group", {
    target_group: groupId,
    confirmation_code: confirmationCode,
    acknowledged: confirmed,
  });
  if (error) {
    console.error("delete_chit_group RPC failed", { code: error.code, message: error.message, details: error.details });
    const code = error.message.includes("GROUP_CODE_CONFIRMATION_MISMATCH") ? "deleteconfirm"
      : error.message.includes("GROUP_NOT_FOUND") ? "notfound"
      : error.code === "PGRST202" || error.message.includes("delete_chit_group") ? "deletemigration"
      : error.code === "23503" ? "deleteblocked" : "deletefailed";
    redirect(`/groups/${groupId}?error=${code}`);
  }
  redirect("/groups?deleted=1");
}
