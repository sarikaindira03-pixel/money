/**
 * /api/paychecks
 *
 * GET    → list all paychecks (latest first)
 * POST   → create a paycheck for a new month
 *
 */
import { NextResponse } from "next/server";
import { badRequest, created, serverError } from "../../../lib/response";
import { handleProcedureError } from "../../../lib/apiResponse";
import { createClient } from "@supabase/supabase-js";
import { headers } from "next/headers";
import { supabaseServiceKey, supabaseUrl } from "@/src/lib/config";
const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!,
);
export async function GET(req: Request) {
  const month = new URL(req.url).searchParams.get("month");

  try {
    const headerList = await headers();
    const userId = headerList.get("x-user-id");

    if (!userId) {
      return badRequest("Unauthorized");
    }

    let query = supabase
      .from("paychecks")
      .select("*")
      .eq("user_id", userId) // ✅ filter by user
      .order("month", { ascending: false });

    if (month) {
      query = query.eq("month", month);
    }

    const { data, error } = await query;

    if (error) throw error;

    if (month) {
      return NextResponse.json(data?.[0] ?? { salary: 0 });
    }

    return NextResponse.json({ data });
  } catch (e) {
    return serverError(e);
  }
}
export async function POST(req: Request) {
  const supabase = createClient(supabaseUrl(), supabaseServiceKey());

  try {
    // 1. Read the user ID straight out of the verified proxy headers
    const headerList = await headers();
    const userId = headerList.get("x-user-id");

    if (!userId) {
      return badRequest("Unauthorized action token context.");
    }
    const { month, salary } = await req.json();
    if (!userId || !month || !salary) return badRequest("Missing fields");
    const { error } = await supabase.rpc("record_paycheck", {
      p_user_id: userId,
      p_month: month,
      p_salary: Number(salary),
    });
    if (error) throw error;
    return created({ message: "Paycheck recorded." });
  } catch (e) {
    console.error("❌ Error name:", e.name);
    console.error("❌ Error message:", e.message);
    console.error("❌ Error code:", e.pgCode);
    console.error("❌ Full error:", e);
    return handleProcedureError(e);
  }
}
