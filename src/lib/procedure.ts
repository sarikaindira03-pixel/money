// lib/procedure.ts
import pool from "./pgPool";

export class ProcedureError extends Error {
  constructor(
    message: string,
    public readonly pgCode: string, // "P0001", "P0002", "23505" etc.
    public readonly procedure: string,
  ) {
    super(message);
    this.name = "ProcedureError";
  }
}

export async function callProcedure(
  name: string,
  args: unknown[],
): Promise<void> {
  const placeholders = args.map((_, i) => `$${i + 1}`).join(", ");
  const client = await pool.connect();
  try {
    await client.query(`CALL public.${name}(${placeholders})`, args);
  } catch (e: any) {
    throw new ProcedureError(e.message, e.code ?? e.routine ?? "UNKNOWN", name);
  } finally {
    client.release();
  }
}
