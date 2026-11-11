"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export async function createMember(formData: FormData) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: profile } = await supabase.from("profiles").select("role,active").eq("id", user.id).maybeSingle();
  if (profile?.role !== "owner" || !profile.active) redirect("/dashboard");
  const fullName = String(formData.get("full_name") ?? "").trim();
  const phone = String(formData.get("phone") ?? "").trim();
  const email = String(formData.get("email") ?? "").trim();
  if (!fullName || fullName.length > 150 || phone.length > 30 || email.length > 254) redirect("/members?error=invalid");
  const { error } = await supabase.from("members").insert({ full_name: fullName, phone: phone || null, email: email || null, created_by: user.id });
  if (error) redirect("/members?error=save");
  redirect("/members?created=1");
}

export async function updateMemberContact(formData: FormData) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: profile } = await supabase.from("profiles").select("role,active").eq("id", user.id).maybeSingle();
  if (profile?.role !== "owner" || !profile.active) redirect("/dashboard");

  const memberId = String(formData.get("member_id") ?? "");
  const phone = String(formData.get("phone") ?? "").trim();
  const email = String(formData.get("email") ?? "").trim();
  if (!/^[0-9a-f-]{36}$/i.test(memberId) || phone.length > 30 || email.length > 254) redirect("/members?error=invalid");
  if (phone && !/^[+0-9() .-]{5,30}$/.test(phone)) redirect("/members?error=invalid");
  if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) redirect("/members?error=invalid");

  const { data, error } = await supabase.from("members").update({ phone: phone || null, email: email || null }).eq("id", memberId).select("id").maybeSingle();
  if (error || !data) redirect("/members?error=update");
  redirect("/members?updated=1");
}
