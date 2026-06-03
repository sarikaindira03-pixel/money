import { createClient } from "@supabase/supabase-js";
import {
  badRequest,
  created,
  handleProcedureError,
} from "@/src/lib/apiResponse";
import { supabaseServiceKey, supabaseUrl } from "@/src/lib/config";
import { headers } from "next/headers";

const supabase = createClient(supabaseUrl(), supabaseServiceKey());

export async function POST(req: Request) {
  try {
    const headerList = await headers();
    const userId = headerList.get("x-user-id");

    if (!userId) return badRequest("Unauthorized action token context.");

    const { procedure, bucket_id, month, amount } = await req.json();

    if (!procedure || !bucket_id || !month || !amount) {
      return badRequest("Missing fields");
    }

    const { error } = await supabase.rpc(procedure, {
      p_month: month,
      p_allocated: parseFloat(amount),
      p_bucket_id: parseInt(bucket_id),
      p_user_id: userId,
    });

    if (error) throw error; // ✅ moved before return

    return created({ message: "Bucket allocated successfully." });
  } catch (e: any) {
    return handleProcedureError(e);
  }
}
