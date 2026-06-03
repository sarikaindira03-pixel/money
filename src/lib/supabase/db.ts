/**
 * lib/supabase/db.ts
 *
 * Raw PostgREST HTTP fetch layer — no supabase-js client overhead.
 * Useful for: server-side bulk reads, cron jobs, custom headers, streaming.
 *
 * Dev  → local PostgREST  (NEXT_PUBLIC_POSTGREST_URL)
 * Prod → Supabase REST    (NEXT_PUBLIC_SUPABASE_URL/rest/v1)
 *
 * Both speak the same PostgREST dialect — helpers work identically in both envs.
 * For most use cases, prefer the supabase-js clients (better DX, type inference).
 * Use this layer when you need fine-grained control over fetch options (e.g. next.revalidate).
 */

import { dbBaseUrl, adminAuthHeaders } from "../config";

export type HttpMethod = "GET" | "POST" | "PATCH" | "DELETE";

export interface QueryOptions {
  /** PostgREST filter params e.g. { status: "eq.active", user_id: "eq.123" } */
  params?: Record<string, string>;
  /** Extra headers (e.g. { Prefer: "count=exact" }) */
  headers?: Record<string, string>;
  /** Next.js fetch cache config */
  next?: NextFetchRequestConfig;
}

/**
 * Core fetch wrapper. Throws on non-2xx responses with PostgREST error details.
 */
export async function dbFetch<T = unknown>(
  table: string,
  method: HttpMethod = "GET",
  body?: unknown,
  options: QueryOptions = {},
): Promise<T> {
  const url = new URL(`${dbBaseUrl()}/${table}`);
  if (options.params) {
    for (const [k, v] of Object.entries(options.params)) {
      url.searchParams.set(k, v);
    }
  }

  const res = await fetch(url.toString(), {
    method,
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      Prefer: "return=representation",
      ...adminAuthHeaders(),
      ...options.headers,
    },
    body: body !== undefined ? JSON.stringify(body) : undefined,
    ...(method === "GET"
      ? { next: options.next ?? { revalidate: 0 } }
      : { cache: "no-store" }),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({ message: res.statusText }));
    const error = new Error(err.message || res.statusText) as Error & {
      code?: string;
      details?: string;
      hint?: string;
    };
    error.code = err.code;
    error.details = err.details;
    error.hint = err.hint;
    throw error;
  }

  if (res.status === 204) return undefined as T;

  return res.json() as Promise<T>;
}

/** Convenience wrappers */
export const db = {
  get: <T>(table: string, opts?: QueryOptions) =>
    dbFetch<T>(table, "GET", undefined, opts),

  post: <T>(table: string, body: unknown, opts?: QueryOptions) =>
    dbFetch<T>(table, "POST", body, opts),

  patch: <T>(table: string, body: unknown, opts?: QueryOptions) =>
    dbFetch<T>(table, "PATCH", body, opts),

  delete: <T>(table: string, opts?: QueryOptions) =>
    dbFetch<T>(table, "DELETE", undefined, opts),

  rpc: <T>(
    functionName: string,
    body?: Record<string, unknown>,
    opts?: QueryOptions,
  ) => dbFetch<T>(`rpc/${functionName}`, "POST", body, opts),
};
