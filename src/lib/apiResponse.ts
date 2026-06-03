// lib/apiResponse.ts
import { NextResponse } from "next/server";
import { ProcedureError } from "./procedure";

export const created = (data: unknown) =>
  NextResponse.json(data, { status: 201 });

export const ok = (data: unknown) => NextResponse.json(data, { status: 200 });

export const badRequest = (message: string) =>
  NextResponse.json({ error: message }, { status: 400 });
export const unauthorized = (message: string) =>
  NextResponse.json({ error: message }, { status: 401 });

export const conflict = (message: string) =>
  NextResponse.json({ error: message }, { status: 409 });

export const serverError = (e: unknown) => {
  console.error(e);
  return NextResponse.json({ error: "Internal server error" }, { status: 500 });
};

// Central place — every route calls this instead of writing if/else
export function handleProcedureError(e: unknown) {
  // Handle raw Supabase/PostgREST errors (not wrapped in ProcedureError)
  const err = e as any;
  const pgCode = err?.code || err?.pgCode;
  const message = err?.message || "Internal server error";

  if (pgCode === "P0001") return conflict(message);
  if (pgCode === "P0002") return badRequest(message);
  if (pgCode === "P0003") return conflict(message);
  if (pgCode === "P0004") return badRequest(message);
  if (pgCode === "P0005") return badRequest(message);
  if (pgCode === "P0006") return badRequest(message);
  if (pgCode === "P0007") return badRequest(message);
  if (pgCode === "P0008") return conflict(message);

  if (e instanceof ProcedureError) {
    const pgCode = e.pgCode;
    const message = e.message;
    if (pgCode === "P0001") return conflict(message);
    if (pgCode === "P0002") return badRequest(message);
    if (pgCode === "P0003") return conflict(message);
    if (pgCode === "P0004") return badRequest(message);
    if (pgCode === "P0005") return badRequest(message);
    if (pgCode === "P0006") return badRequest(message);
    if (pgCode === "P0007") return badRequest(message);
    if (pgCode === "P0008") return conflict(message);
  }

  return serverError(e);
}
