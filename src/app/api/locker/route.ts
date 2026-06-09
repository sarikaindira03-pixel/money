import { head_user_id } from "@/src/lib/server-config";
import { badRequest, serverError } from "@/src/lib/response";
import supabase from "@/src/lib/supabase/postgrest";
import { NextResponse } from "next/server";

export async function GET() {
  try {
    const userId = await head_user_id();
    if (!userId) {
      return badRequest("Unauthorized action token context.");
    }

    const { data: lockerData, error: dbError } = await supabase
      .from("v_vault_balances")
      .select("*")
      .eq("user_id", userId)
      .eq("is_month_open", true);

    if (dbError) {
      return NextResponse.json(
        {
          error: dbError,
        },
        { status: 500 },
      );
    }

    return NextResponse.json(lockerData);
  } catch (e) {
    return serverError(e);
  }
}
