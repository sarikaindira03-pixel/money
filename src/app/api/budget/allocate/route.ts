import {
  badRequest,
  created,
  handleProcedureError,
} from "@/src/lib/apiResponse";
import { head_user_id } from "@/src/lib/server-config";
import supabase from "@/src/lib/supabase/postgrest";

export async function POST(req: Request) {
  try {
    const userId = await head_user_id();
    if (!userId) return badRequest("Unauthorized action token context.");

    const { procedure, bucket_id, month, amount } = await req.json();

    if (!procedure || !bucket_id || !month || !amount) {
      return badRequest("Missing fields");
    }

    const { error } = await supabase.rpc(procedure, {
      p_user_id: userId,
      p_month: month,
      p_bucket_id: parseInt(bucket_id),
      p_allocated: parseFloat(amount),
    });

    if (error) throw error; // ✅ moved before return

    return created({ message: "Bucket allocated successfully." });
  } catch (e: any) {
    return handleProcedureError(e);
  }
}
