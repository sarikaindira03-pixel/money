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
import supabase from "@/src/lib/supabase/postgrest";
import { head_user_id } from "@/src/lib/server-config";

export async function GET(req: Request) {
  const month = new URL(req.url).searchParams.get("month");

  try {
    const userId = await head_user_id();

    if (!userId) {
      return badRequest("Unauthorized");
    }
    let query = supabase
      .from("v_paychecks")
      .select("*")
      .eq("user_id", userId)
      .order("month", { ascending: false });

    if (month) {
      query = query.eq("month", month);
    }

    const { data, error } = await query;

    if (error) throw error;

    if (month) {
      return NextResponse.json(data?.[0] ?? { total_income: 0 });
    }

    return NextResponse.json({ data });
  } catch (e) {
    return serverError(e);
  }
}
export async function POST(req: Request) {
  try {
    // 1. Read the user ID straight out of the verified proxy headers

    const userId = await head_user_id();

    if (!userId) {
      return badRequest("Unauthorized action token context.");
    }
    const { month, total_income } = await req.json();
    if (!userId || !month || !total_income) return badRequest("Missing fields");
    const { error } = await supabase.rpc("record_paycheck", {
      p_user_id: userId,
      p_month: month,
      p_total_income: Number(total_income),
    });
    if (error) throw error;
    return created({ message: "Paycheck recorded." });
  } catch (e) {
    console.error("❌ Error name:", e.name);
    console.error("❌ Error message:", e.message);
    console.error("❌ Error code:", e.pgCode);
    console.error("❌ Full error paycheck:", e);
    return handleProcedureError(e);
  }
}
