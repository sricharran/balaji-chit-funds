"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

function toPaise(value: FormDataEntryValue | null): number | null {
  const text = String(value ?? "").trim();
  if (!/^\d+(\.\d{1,2})?$/.test(text)) return null;
  const [whole, fraction = ""] = text.split(".");
  const amount = Number(whole) * 100 + Number(fraction.padEnd(2, "0"));
  return Number.isSafeInteger(amount) ? amount : null;
}

async function currentProfile() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: profile } = await supabase.from("profiles").select("role,active").eq("id", user.id).maybeSingle();
  if (!profile?.active || !["owner", "staff"].includes(profile.role)) redirect("/login?error=unauthorized");
  return { supabase, user, role: profile.role as string };
}

export async function createAuction(formData: FormData) {
  const { supabase, user, role } = await currentProfile();
  if (role !== "owner") redirect("/auctions?error=owner");
  const groupId = String(formData.get("group_id") ?? "");
  const month = Number(formData.get("month_number"));
  const method = String(formData.get("selection_method") ?? "");
  const auctionDate = String(formData.get("auction_date") ?? "");
  if (!/^[0-9a-f-]{36}$/i.test(groupId) || !Number.isInteger(month) || month < 1 || month > 120 || !["auction", "lucky_draw"].includes(method) || !/^\d{4}-\d{2}-\d{2}$/.test(auctionDate)) redirect("/auctions?error=invalid");
  const { data: group } = await supabase.from("chit_groups").select("commission_amount_paise,duration_months,status").eq("id", groupId).maybeSingle();
  if (!group || group.status !== "active" || month > group.duration_months) redirect("/auctions?error=invalid");
  const { error } = await supabase.from("auctions").insert({ group_id: groupId, month_number: month, selection_method: method, auction_date: auctionDate, commission_paise: group.commission_amount_paise, created_by: user.id });
  if (error) redirect(`/auctions?error=${error.message.includes("duplicate key") ? "duplicate" : "save"}`);
  redirect("/auctions?created=1");
}

export async function openAuction(formData: FormData) {
  const { supabase, role } = await currentProfile();
  if (role !== "owner") redirect("/auctions?error=owner");
  const auctionId = String(formData.get("auction_id") ?? "");
  if (!/^[0-9a-f-]{36}$/i.test(auctionId)) redirect("/auctions?error=invalid");
  const { data, error } = await supabase.from("auctions").update({ status: "open" }).eq("id", auctionId).eq("status", "draft").select("id").maybeSingle();
  if (error || !data) redirect(`/auctions/${auctionId}?error=open`);
  redirect(`/auctions/${auctionId}?opened=1`);
}

export async function recordBid(formData: FormData) {
  const { supabase, user } = await currentProfile();
  const auctionId = String(formData.get("auction_id") ?? "");
  const groupId = String(formData.get("group_id") ?? "");
  const memberId = String(formData.get("member_id") ?? "");
  const rawAmount = String(formData.get("bid_discount") ?? "").trim();
  if (![auctionId, groupId, memberId].every((id) => /^[0-9a-f-]{36}$/i.test(id)) || !/^\d+(\.\d{1,2})?$/.test(rawAmount)) redirect(`/auctions/${auctionId}?error=invalidbid`);
  const [rupees, fraction = ""] = rawAmount.split(".");
  const amount = Number(rupees) * 100 + Number(fraction.padEnd(2, "0"));
  if (!Number.isSafeInteger(amount) || amount < 0) redirect(`/auctions/${auctionId}?error=invalidbid`);
  const { error } = await supabase.from("auction_bids").insert({ auction_id: auctionId, group_id: groupId, member_id: memberId, bid_discount_paise: amount, recorded_by: user.id });
  if (error) redirect(`/auctions/${auctionId}?error=${error.message.includes("duplicate key") ? "duplicatebid" : "bid"}`);
  redirect(`/auctions/${auctionId}?bidrecorded=1`);
}

export async function finalizeBidWinner(formData: FormData) {
  const { supabase, role } = await currentProfile();
  if (role !== "owner") redirect("/auctions?error=owner");
  const auctionId = String(formData.get("auction_id") ?? "");
  const memberId = String(formData.get("member_id") ?? "");
  if (![auctionId, memberId].every((id) => /^[0-9a-f-]{36}$/i.test(id))) redirect("/auctions?error=invalid");
  const { error } = await supabase.rpc("finalize_auction_winner", { target_auction: auctionId, target_member: memberId });
  if (error) redirect(`/auctions/${auctionId}?error=${error.message.includes("MEMBER_ALREADY_WON") ? "previouswinner" : "finalize"}`);
  redirect(`/auctions/${auctionId}?winnerselected=1`);
}

export async function finalizeMonthlyAuction(formData: FormData) {
  const { supabase, role } = await currentProfile();
  if (role !== "owner") redirect("/auctions?error=owner");
  const auctionId = String(formData.get("auction_id") ?? "");
  const discount = toPaise(formData.get("discount_amount"));
  const commission = toPaise(formData.get("commission_amount"));
  if (!/^[0-9a-f-]{36}$/i.test(auctionId) || discount === null || commission === null) redirect(`/auctions/${auctionId}?error=financialinput`);
  const { error } = await supabase.rpc("finalize_monthly_auction", {
    target_auction: auctionId,
    discount_amount_paise: discount,
    commission_amount_paise: commission,
  });
  if (error) {
    const code = error.message.includes("DEDUCTIONS_EXCEED") ? "deductionsexceed"
      : error.message.includes("DIVIDEND_EXCEEDS") ? "dividendexceed"
      : error.message.includes("PAYMENTS") ? "monthpaid" : "finalize";
    redirect(`/auctions/${auctionId}?error=${code}`);
  }
  redirect(`/auctions/${auctionId}?finalized=1`);
}

export async function runLuckyDraw(formData: FormData) {
  const { supabase, role } = await currentProfile();
  if (role !== "owner") redirect("/auctions?error=owner");
  const auctionId = String(formData.get("auction_id") ?? "");
  if (!/^[0-9a-f-]{36}$/i.test(auctionId)) redirect("/auctions?error=invalid");
  const { error } = await supabase.rpc("run_lucky_draw", { target_auction: auctionId });
  if (error) {
    const code = error.message.includes("NO_ELIGIBLE") ? "noeligible"
      : error.message.includes("INVALID_MONTH") ? "drawmonth" : "draw";
    redirect(`/auctions/${auctionId}?error=${code}`);
  }
  redirect(`/auctions/${auctionId}?drawn=1`);
}

export async function deleteDraftAuction(formData: FormData) {
  const { supabase, role } = await currentProfile();
  if (role !== "owner") redirect("/auctions?error=owner");
  const auctionId = String(formData.get("auction_id") ?? "");
  const acknowledged = formData.get("confirm_delete_draft") === "yes";
  if (!/^[0-9a-f-]{36}$/i.test(auctionId) || !acknowledged) redirect(`/auctions/${auctionId}?error=deleteconfirm`);

  const { error } = await supabase.rpc("delete_draft_auction", {
    target_auction: auctionId,
    acknowledged,
  });
  if (error) {
    const code = error.code === "PGRST202" || error.message.includes("delete_draft_auction") ? "deletemigration"
      : error.message.includes("ONLY_UNFINALIZED_AUCTIONS_CAN_BE_DELETED") ? "deleteonlyunfinalized"
      : error.message.includes("AUCTION_HAS_FINANCIAL_HISTORY") ? "deletefinancial"
      : error.message.includes("AUCTION_NOT_FOUND") ? "notfound" : "deleteauction";
    redirect(`/auctions/${auctionId}?error=${code}`);
  }
  redirect("/auctions?draftdeleted=1");
}
