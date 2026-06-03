import { NextResponse } from "next/server";

export function ok<T>(data: T, status = 200) {
  return NextResponse.json({ data }, { status });
}

export function created<T>(data: T) {
  return NextResponse.json({ data }, { status: 201 });
}
export function deleted<T>(data: T) {
  return NextResponse.json({ data }, { status: 201 });
}

export function noContent() {
  return new NextResponse(null, { status: 204 });
}

export function badRequest(message: string) {
  return NextResponse.json({ error: message }, { status: 400 });
}
export const conflict = (msg: string) =>
  NextResponse.json({ error: msg }, { status: 409 });

export function notFound(message = "Not found") {
  return NextResponse.json({ error: message }, { status: 404 });
}

// Error Handler
export class ApiError extends Error {
  statusCode: number;
  code?: string;

  constructor(statusCode: number, message: string, code?: string) {
    super(message);
    this.name = "ApiError";
    this.statusCode = statusCode;
    this.code = code;
  }
}
export function serverError(error: unknown): NextResponse {
  console.error("API Error:", error);
  // Case 1: Our custom ApiError
  if (error instanceof ApiError) {
    return NextResponse.json(
      {
        success: false,
        error: error.message,
        code: error.code,
      },
      { status: error.statusCode },
    );
  }

  // Case 2: PostgREST / Database Error (from your dbFetch)
  if (error instanceof Error) {
    const err = error as any;

    // Common PostgREST error structure
    return NextResponse.json(
      {
        success: false,
        error: err.message || "Database operation failed",
        code: err.code,
        details: err.details || err.hint,
      },
      { status: 400 }, // or 500 based on error type
    );
  }

  // Case 3: Unknown error
  return NextResponse.json(
    {
      success: false,
      error: "Internal server error",
    },
    { status: 500 },
  );
}
