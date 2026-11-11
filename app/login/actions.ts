"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export async function signIn(formData: FormData) {
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");
  if (!email || !password) redirect("/login?error=missing");

  let errorCode: string | null = null;
  let connectionFailed = false;
  try {
    const supabase = await createClient();
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) errorCode = error.code ?? "invalid_credentials";
  } catch (error) {
    connectionFailed = true;
    console.error("Supabase sign-in request failed", error instanceof Error ? error.name : "UnknownError");
  }

  if (connectionFailed) redirect("/login?error=connection");
  if (errorCode === "email_not_confirmed") redirect("/login?error=unconfirmed");
  if (errorCode) redirect("/login?error=invalid");
  redirect("/dashboard");
}
