"use server";

import { randomUUID } from "node:crypto";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

function toPaise(value: FormDataEntryValue | null): number | null {
  const text = String(value ?? "").trim();
  if (!/^\d+(\.\d{1,2})?$/.test(text)) return null;
  const [whole, fraction = ""] = text.split(".");
  const result = Number(whole) * 100 + Number(fraction.padEnd(2, "0"));
  return Number.isSafeInteger(result) && result > 0 ? result : null;
}

export async function recordPrizeDisbursement(formData: FormData) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: profile } = await supabase.from("profiles").select("role,active").eq("id", user.id).maybeSingle();
  if (profile?.role !== "owner" || !profile.active) redirect("/dashboard");

  const auctionId = String(formData.get("auction_id") ?? "");
  const amount = toPaise(formData.get("amount"));
  const date = String(formData.get("disbursement_date") ?? "");
  const method = String(formData.get("payment_method") ?? "");
  const reference = String(formData.get("reference") ?? "").trim();
  const requestKey = String(formData.get("request_key") ?? "");
  if (!/^[0-9a-f-]{36}$/i.test(auctionId) || amount === null || !/^\d{4}-\d{2}-\d{2}$/.test(date) || !["cash", "upi", "bank_transfer"].includes(method) || reference.length > 120 || !/^[0-9a-f-]{36}$/i.test(requestKey)) {
    redirect("/prizes?error=invalid");
  }
  const parsedDate = new Date(`${date}T00:00:00.000Z`);
  if (Number.isNaN(parsedDate.valueOf()) || parsedDate.toISOString().slice(0, 10) !== date) redirect("/prizes?error=invalid");

  const { error } = await supabase.rpc("record_prize_disbursement", {
    target_auction: auctionId,
    amount_paise: amount,
    disbursement_date_value: date,
    payment_method_value: method,
    transaction_reference_value: reference || null,
    request_key: requestKey || randomUUID(),
  });
  if (error) {
    const code = error.message.includes("EXCEEDS_REMAINING") ? "exceeds"
      : error.message.includes("FINALIZED_PRIZE_REQUIRED") ? "notfinalized"
      : error.code === "PGRST202" || error.message.includes("record_prize_disbursement") ? "migration"
      : "save";
    redirect(`/prizes?error=${code}`);
  }
  redirect("/prizes?recorded=1");
}
