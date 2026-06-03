import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
import { headers } from "next/headers";
import { badRequest } from "@/src/lib/response";
import { handleProcedureError } from "@/src/lib/apiResponse";

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!,
);

export async function GET(req: NextRequest) {
  try {
    const headerList = await headers();
    const userId = headerList.get("x-user-id");
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
