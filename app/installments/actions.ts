"use server";

import { randomUUID } from "node:crypto";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

async function getActiveUser() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: profile } = await supabase.from("profiles").select("role,active").eq("id", user.id).maybeSingle();
  if (!profile?.active || !["owner", "staff"].includes(profile.role)) redirect("/login?error=unauthorized");
  return { supabase, user, role: profile.role as string };
}

export async function generateInstallments(formData: FormData) {
  const { supabase, role } = await getActiveUser();
  const groupId = String(formData.get("group_id") ?? "");
  const month = Number(formData.get("month_number"));
  const dueDate = String(formData.get("due_date") ?? "");
  if (role !== "owner") redirect("/installments?error=owner");
  if (!/^[0-9a-f-]{36}$/i.test(groupId) || !Number.isInteger(month) || month < 1 || month > 120 || !/^\d{4}-\d{2}-\d{2}$/.test(dueDate)) redirect("/installments?error=invalid");
  const date = new Date(`${dueDate}T00:00:00.000Z`);
  if (Number.isNaN(date.valueOf()) || date.toISOString().slice(0, 10) !== dueDate) redirect(`/installments?group_id=${groupId}&month=${month}&error=invalid`);

  const { data: count, error } = await supabase.rpc("generate_group_installments", { target_group: groupId, target_month: month, installment_due_date: dueDate });
  if (error) {
    const code = error.message.includes("ALREADY_GENERATED") ? "exists"
      : error.message.includes("NOT_ACTIVE") ? "inactive"
      : error.message.includes("INVALID_INSTALLMENT_MONTH") ? "month"
      : error.message.includes("ROSTER_INCOMPLETE") ? "roster" : "generate";
    redirect(`/installments?group_id=${groupId}&month=${month}&error=${code}`);
  }
  redirect(`/installments?group_id=${groupId}&month=${month}&generated=${count}`);
}

export async function recordInstallmentPayment(formData: FormData) {
  const { supabase } = await getActiveUser();
  const installmentId = String(formData.get("installment_id") ?? "");
  const groupId = String(formData.get("group_id") ?? "");
  const month = Number(formData.get("month_number"));
  const rawAmount = String(formData.get("amount") ?? "").trim();
  const method = String(formData.get("payment_method") ?? "");
  const paidOn = String(formData.get("payment_date") ?? "");
  const reference = String(formData.get("reference") ?? "").trim();
  if (!/^[0-9a-f-]{36}$/i.test(installmentId) || !/^[0-9a-f-]{36}$/i.test(groupId) || !Number.isInteger(month)) redirect("/installments?error=invalid");
  if (!/^\d+(\.\d{1,2})?$/.test(rawAmount) || !["cash", "upi", "bank_transfer"].includes(method) || !/^\d{4}-\d{2}-\d{2}$/.test(paidOn) || reference.length > 120) redirect(`/installments?group_id=${groupId}&month=${month}&error=invalid`);
  const [rupees, fraction = ""] = rawAmount.split(".");
  const amountPaise = Number(rupees) * 100 + Number(fraction.padEnd(2, "0"));
  const paidDate = new Date(`${paidOn}T00:00:00.000Z`);
  if (!Number.isSafeInteger(amountPaise) || amountPaise <= 0 || Number.isNaN(paidDate.valueOf()) || paidDate.toISOString().slice(0, 10) !== paidOn) redirect(`/installments?group_id=${groupId}&month=${month}&error=invalid`);

  const { error } = await supabase.rpc("record_payment", {
    target_installment: installmentId,
    payment_amount_paise: amountPaise,
    payment_method_value: method,
    payment_date_value: paidOn,
    transaction_reference_value: reference || null,
    request_key: String(formData.get("request_key") ?? "") || randomUUID(),
  });
  if (error) {
    const code = error.message.includes("EXCEEDS_INSTALLMENT_BALANCE") ? "exceeds"
      : error.message.includes("NOT_AUTHORIZED") ? "unauthorized" : "payment";
    redirect(`/installments?group_id=${groupId}&month=${month}&error=${code}`);
  }
  redirect(`/installments?group_id=${groupId}&month=${month}&paid=1`);
}
