import { NextRequest, NextResponse } from "next/server";
import { handleProcedureError } from "@/src/lib/apiResponse";
import { badRequest, created } from "@/src/lib/response";

import { head_user_id } from "@/src/lib/server-config";
import supabase from "@/src/lib/supabase/postgrest";

// GET /api/ledger?bucket_id=2&month=2026-01
export async function GET(req: NextRequest) {
  try {
    const userId = await head_user_id();
    if (!userId) return badRequest("Unauthorized action token context.");

    const { searchParams } = new URL(req.url);
    const bucketIdRaw = searchParams.get("bucket_id");
    const monthRaw = searchParams.get("month");

    const { data, error } = await supabase
      .from("ledger_by_bucket_month")
      .select("*")
      .eq("bucket_id", bucketIdRaw)
      .eq("month", monthRaw)
      .eq("user_id", userId);

    if (error) throw error;

    return NextResponse.json({ entries: data });
  } catch (e: any) {
    return handleProcedureError(e);
  }
}

export async function POST(req: Request) {
  try {
    const userId = await head_user_id();
    if (!userId) return badRequest("Unauthorized action token context.");

    const { bucket_id, month, amount_spent, note, procedure, date_of_entry } =
      await req.json();

    if (!bucket_id || !month || !amount_spent)
      return badRequest("Missing fields");

    // const { error } = await supabase.rpc(procedure, {
    //   p_user_id: userId,
    //   p_bucket_id: parseInt(bucket_id),
    //   p_amount_spent: parseFloat(amount_spent),
    //   p_month: month,
    //   p_date_of_entry: date_of_entry,
    //   p_note: note,
    // });

    const { error } = await supabase.rpc(procedure, {
      p_user_id: userId,
      p_bucket_id: parseInt(bucket_id),
      p_amount: parseFloat(amount_spent), // was p_amount_spent
      p_month: month,
      p_date: date_of_entry, // was p_date_of_entry
      p_note: note ?? null,
    });
    if (error) throw error;

    return created({ message: "Bucket allocated." });
  } catch (e: any) {
    console.error("❌ Error name:", e.name);
    console.error("❌ Error message:", e.message);
    console.error("❌ Error code:", e.pgCode);
    console.error("❌ Full error:", e);
    return handleProcedureError(e);
  }
}
