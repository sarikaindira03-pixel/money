// File: src/app/api/bucket_configs/route.ts
import { createClient } from "@supabase/supabase-js";
import { headers } from "next/headers";
import { NextResponse } from "next/server";
import { badRequest, handleProcedureError } from "@/src/lib/apiResponse"; // or your uniform response helpers

// Initialize the standard server-side Supabase client with the Service Role key
const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!,
);

export async function GET() {
  try {
    // 1. Fetch active configs using Supabase's native filtering syntax
    const { data, error } = await supabase
      .from("bucket_configs")
      .select("*")
      .eq("is_active", true)
      .not("display_type", "in", "(RESERVE)"); // Replaces "not.in.(RESERVE)"

    if (error) throw error;

    return NextResponse.json(data);
  } catch (error: any) {
    console.error("API GET Error:", error.message);
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}

export async function POST(req: Request) {
  try {
    // 2. Extract the tamper-proof user ID from the proxy headers
    const headerList = await headers();
    const userId = headerList.get("x-user-id");

    if (!userId) {
      return NextResponse.json(
        { error: "Unauthorized ctx context." },
        { status: 401 },
      );
    }

    // 3. Parse the body payload (Notice: no user_id passed from frontend client)
    const { bucket_name, display_type, is_active } = await req.json();

    if (!bucket_name || !display_type) {
      return badRequest("Missing required fields");
    }

    // 4. Securely insert the data with the proxy-verified userId
    const { data, error } = await supabase
      .from("bucket_configs")
      .insert([
        {
          user_id: userId, // Securely assigned on the server side
          bucket_name,
          display_type,
          is_active: is_active ?? true,
        },
      ])
      .select()
      .single(); // Returns the created object instead of an array wrapper

    if (error) throw error;

    return NextResponse.json(data, { status: 201 });
  } catch (error: any) {
    console.error("API POST Error:", error.message);
    // If you have a global error handler for DB constraints:
    if (typeof handleProcedureError === "function") {
      return handleProcedureError(error);
    }
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
