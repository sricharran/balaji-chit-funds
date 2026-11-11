"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

function rupeesToPaise(value: FormDataEntryValue | null): number | null {
  const text = String(value ?? "").trim();
  if (!/^\d+(\.\d{1,2})?$/.test(text)) return null;
  const [whole, fraction = ""] = text.split(".");
  const paise = Number(whole) * 100 + Number(fraction.padEnd(2, "0"));
  return Number.isSafeInteger(paise) && paise > 0 ? paise : null;
}

function nonnegativeRupeesToPaise(value: FormDataEntryValue | null): number | null {
  const text = String(value ?? "").trim();
  if (!/^\d+(\.\d{1,2})?$/.test(text)) return null;
  const [whole, fraction = ""] = text.split(".");
  const paise = Number(whole) * 100 + Number(fraction.padEnd(2, "0"));
  return Number.isSafeInteger(paise) ? paise : null;
}

export async function createGroup(formData: FormData) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: profile } = await supabase.from("profiles").select("role,active").eq("id", user.id).maybeSingle();
  if (profile?.role !== "owner" || !profile.active) redirect("/dashboard");

  const name = String(formData.get("name") ?? "").trim();
  const chitValue = rupeesToPaise(formData.get("chit_value"));
  const duration = Number(formData.get("duration_months"));
  const capacity = Number(formData.get("member_capacity"));
  const commission = nonnegativeRupeesToPaise(formData.get("commission_amount"));
  const startDate = String(formData.get("start_date") ?? "");

  if (!name || name.length > 100 || !chitValue || commission === null || !Number.isInteger(duration) || duration < 1 || duration > 120 || !Number.isInteger(capacity) || capacity < 1 || capacity > 1000 || !/^\d{4}-\d{2}-\d{2}$/.test(startDate)) {
    redirect("/groups?error=invalid");
  }
  const quotient = Math.floor(chitValue / duration);
  const remainder = chitValue % duration;
  const installment = quotient + (remainder * 2 >= duration ? 1 : 0);
  if (!Number.isSafeInteger(installment) || installment <= 0) redirect("/groups?error=invalid");

  const { error } = await supabase.from("chit_groups").insert({
    name, chit_value_paise: chitValue, monthly_installment_paise: installment,
    duration_months: duration, member_capacity: capacity,
    commission_bps: 0, commission_amount_paise: commission, start_date: startDate, created_by: user.id,
  });
  if (error) redirect("/groups?error=save");
  redirect("/groups?created=1");
}
