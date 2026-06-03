// // src/app/api/ledger/[id]/route.ts
// import { handleProcedureError } from "@/src/lib/apiResponse";
// import { badRequest, deleted } from "@/src/lib/response";
// import { callProcedure } from "@/src/lib/procedure";

// const ALLOWED_PROCEDURES = [
//   "reverse_ledger_entry",
//   "reverse_blue_ledger_entry",
// ] as const;
// type AllowedProcedure = (typeof ALLOWED_PROCEDURES)[number];

// export async function DELETE(
//   req: Request,
//   { params }: { params: Promise<{ id: string }> },
// ) {
//   try {
//     const { id: ledger_id } = await params;
//     const { procedure, user_id, reason } = await req.json();

//     if (!user_id || !ledger_id || !reason) return badRequest("Missing fields");
//     if (!ALLOWED_PROCEDURES.includes(procedure as AllowedProcedure))
//       return badRequest("Invalid procedure");

//     await callProcedure(procedure, [user_id, ledger_id, reason]);

//     return deleted({ message: "Transaction Deleted." });
//   } catch (e: unknown) {
//     const err = e as { name?: string; message?: string; pgCode?: string };
//     console.error("❌ Error name:", err.name);
//     console.error("❌ Error message:", err.message);
//     console.error("❌ Error code:", err.pgCode);
//     console.error("❌ Full error:", e);
//     return handleProcedureError(e);
//   }
// }
import { handleProcedureError } from "@/src/lib/apiResponse";
import { badRequest, deleted } from "@/src/lib/response";
import { createClient } from "@supabase/supabase-js";
import { headers } from "next/headers";

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!,
);

const ALLOWED_PROCEDURES = [
  "reverse_ledger_entry",
  "reverse_blue_ledger_entry",
] as const;
type AllowedProcedure = (typeof ALLOWED_PROCEDURES)[number];

export async function DELETE(
  req: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  try {
    const headerList = await headers();
    const userId = headerList.get("x-user-id");
    if (!userId) return badRequest("Unauthorized action token context.");

    const { id: ledger_id } = await params;
    const { procedure, reason } = await req.json();

    if (!ledger_id || !reason) return badRequest("Missing fields");
    if (!ALLOWED_PROCEDURES.includes(procedure as AllowedProcedure))
      return badRequest("Invalid procedure");

    const { error } = await supabase.rpc(procedure, {
      p_user_id: userId,
      p_ledger_id: ledger_id,
      p_reason: reason,
    });

    if (error) throw error;

    return deleted({ message: "Transaction Deleted." });
  } catch (e: unknown) {
    const err = e as { name?: string; message?: string; pgCode?: string };
    console.error("❌ Error name:", err.name);
    console.error("❌ Error message:", err.message);
    console.error("❌ Error code:", err.pgCode);
    return handleProcedureError(e);
  }
}
