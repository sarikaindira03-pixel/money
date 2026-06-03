import { badRequest, serverError } from "@/src/lib/response";
import { createClient } from "@supabase/supabase-js";
// import { CurrentBalance } from "@/src/types/data";
import { headers } from "next/headers";
import { NextResponse } from "next/server";
const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!,
);
export async function GET() {
  try {
    const headerList = await headers();
    const userId = headerList.get("x-user-id");

    if (!userId) {
      return badRequest("Unauthorized action token context.");
    }

    const { data: lockerData, error: dbError } = await supabase
      .from("v_vault_balances")
      .select("*")
      .eq("user_id", userId);

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
