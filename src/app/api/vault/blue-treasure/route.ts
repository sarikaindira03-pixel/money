import { NextRequest, NextResponse } from "next/server";
import { badRequest } from "@/src/lib/response";
import { handleProcedureError } from "@/src/lib/apiResponse";
import { head_user_id } from "@/src/lib/server-config";
import { getSupabase } from "@/src/lib/supabase/postgrest";

export async function GET(req: NextRequest) {
  const supabase = getSupabase();
  try {
    const userId = await head_user_id();
    if (!userId) return badRequest("Unauthorized action token context.");

    const { searchParams } = new URL(req.url);
    const bucket_id = searchParams.get("bucket_id");
    const month = searchParams.get("month");

    const [{ data: cashOut, error: e1 }, { data: cashIn, error: e2 }] =
      await Promise.all([
        supabase
          .from("cash_out_blue_treasure")
          .select("*")
          .eq("bucket_id", bucket_id)
          .eq("month", month)
          .eq("user_id", userId),
        supabase
          .from("cash_in_blue_treasure")
          .select("*")
          .eq("bucket_id", bucket_id)
          .eq("month", month)
          .eq("user_id", userId),
      ]);

    if (e1) throw e1;
    if (e2) throw e2;

    return NextResponse.json({ cashOut, cashIn });
  } catch (e: any) {
    return handleProcedureError(e);
  }
}
