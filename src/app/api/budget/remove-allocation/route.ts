// /api/budget/remove-allocation/route.ts
import { head_user_id } from "@/src/lib/server-config";
import { badRequest, serverError } from "@/src/lib/response";
import supabase from "@/src/lib/supabase/postgrest";
import { NextResponse } from "next/server";
import { handleProcedureError } from "@/src/lib/apiResponse";

export async function POST(req: Request) {
  try {
    const userId = await head_user_id();
    if (!userId) return badRequest("Unauthorized action token context.");

    const { bucket_id, month } = await req.json();
    if (!bucket_id || !month)
      return badRequest("bucket_id and month are required.");

    const { error } = await supabase.rpc("remove_bucket_allocation", {
      p_user_id: userId,
      p_month: month,
      p_bucket_id: bucket_id,
    });

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }

    return NextResponse.json({ success: true });
  } catch (e: any) {
    console.error("❌ Error name:", e.name);
    console.error("❌ Error message:", e.message);
    console.error("❌ Error code:", e.pgCode);
    console.error("❌ Full error:", e);
    return handleProcedureError(e);
  }
}
