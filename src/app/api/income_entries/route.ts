import { head_user_id } from "@/src/lib/server-config";
import { badRequest, serverError } from "@/src/lib/response";
import supabase from "@/src/lib/supabase/postgrest";
import { NextResponse } from "next/server";

export async function GET(req: Request) {
  const month = new URL(req.url).searchParams.get("month");

  try {
    const userId = await head_user_id();
    if (!userId) return badRequest("Unauthorized");

    let query = supabase
      .from("income_entries")
      .select("source_name, amount")
      .eq("user_id", userId)
      .order("created_at", { ascending: true });

    if (month) query = query.eq("month", month);

    const { data, error } = await query;
    if (error) throw error;

    return NextResponse.json({ data });
  } catch (e) {
    return serverError(e);
  }
}

export async function POST(req: Request) {
  try {
    const userId = await head_user_id();
    if (!userId) {
      return badRequest("Unauthorized action token context.");
    }

    const { procedure, month, source_name, amount } = await req.json();

    if (!procedure || !month || !source_name) {
      return badRequest("month and source_name are required.");
    }

    let rpcParams: Record<string, unknown> = {
      p_user_id: userId,
      p_month: month,
      p_source_name: source_name,
    };

    switch (procedure) {
      case "add_income":
        if (amount == null) {
          return badRequest("amount is required.");
        }

        rpcParams.p_amount = amount;
        break;

      case "remove_income":
        break;

      default:
        return badRequest("Invalid procedure.");
    }

    const { error } = await supabase.rpc(procedure, rpcParams);

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }

    return NextResponse.json({ success: true });
  } catch (e) {
    return serverError(e);
  }
}
