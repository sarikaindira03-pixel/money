import { badRequest } from "@/src/lib/response";
import { createClient } from "@supabase/supabase-js";
import { headers } from "next/headers";
import { NextRequest, NextResponse } from "next/server";

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!,
);

type RouteContext = {
  params: Promise<{ month: string }>;
};

export async function GET(req: NextRequest, context: RouteContext) {
  const { month } = await context.params;

  try {
    const headerList = await headers();
    const userId = headerList.get("x-user-id");

    if (!userId) return badRequest("Unauthorized action token context.");

    const { data, error } = await supabase
      .from("monthly_budget_view")
      .select("*")
      .eq("month", month)
      .eq("user_id", userId);

    if (error) throw error;

    const records = data || [];

    const filtered = records.filter(
      (item) => !(item.display_type === "ORANGE" && item.allocated === 0),
    );

    const grouped = filtered.reduce((acc: any, item) => {
      const type = item.display_type;
      if (!acc[type]) acc[type] = [];
      acc[type].push(item);
      return acc;
    }, {});

    const isRecord = filtered.length > 0;
    const hasOrangeBucket = (grouped.ORANGE ?? []).some(
      (b: any) => b.allocated > 0,
    );
    const isMonthOpen = filtered.length > 0 ? filtered[0].is_month_open : true;
    const orangeBucket = records.find((item) => item.display_type === "ORANGE");

    return NextResponse.json({
      isRecord,
      hasOrangeBucket,
      orange_bucket_id: orangeBucket?.bucket_id ?? null,
      month,
      is_month_open: isMonthOpen,
      total_allocated: filtered.reduce(
        (sum, item) => sum + Number(item.allocated || 0),
        0,
      ),
      total_spent: filtered.reduce(
        (sum, item) => sum + Number(item.spent || 0),
        0,
      ),
      grouped_by_type: grouped,
    });
  } catch (e: any) {
    console.error("Database route error:", e);
    return NextResponse.json(
      { error: e.message || "Internal Server Error" },
      { status: 500 },
    );
  }
}
