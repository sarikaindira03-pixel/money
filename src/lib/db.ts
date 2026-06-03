// /**
//  * db.ts — unified fetch layer
//  *
//  * Dev  → postgREST  (NEXT_PUBLIC_POSTGREST_URL)
//  * Prod → Supabase   (NEXT_PUBLIC_SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY)
//  *
//  * Both speak the same PostgREST HTTP dialect, so the same helpers work
//  * for every environment — just point the env vars at the right host.
//  */

// const IS_PROD = process.env.NODE_ENV === "production";

// export function baseUrl(): string {
//   if (IS_PROD) {
//     const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
//     if (!url) throw new Error("NEXT_PUBLIC_SUPABASE_URL is not set");
//     return `${url}`;
//   }
//   const url = process.env.NEXT_PUBLIC_POSTGREST_URL ?? "http://localhost:3000";
//   return url;
// }

// function authHeaders(): Record<string, string> {
//   if (IS_PROD) {
//     const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
//     if (!key) throw new Error("SUPABASE_SERVICE_ROLE_KEY is not set");
//     return {
//       apikey: key,
//       Authorization: `Bearer ${key}`,
//     };
//   }
//   // DEV: Use JWT from environment
//   // const jwt = process.env.POSTGREST_JWT_TOKEN;
//   const jwt = process.env.POSTGREST_JWT_TOKEN?.trim();
//   if (jwt) {
//     return {
//       Authorization: `Bearer ${jwt}`,
//     };
//   }
//   return {};
// }

// export type HttpMethod = "GET" | "POST" | "PATCH" | "DELETE";

// export interface QueryOptions {
//   /** PostgREST filter params e.g. { bucket_id: "eq.3" } */
//   params?: Record<string, string>;
//   /** Extra headers (e.g. Prefer: return=representation) */
//   headers?: Record<string, string>;
//   next?: NextFetchRequestConfig;
// }

// /**
//  * Core fetch wrapper. All route handlers call this.
//  */
// export async function dbFetch<T = unknown>(
//   table: string,
//   method: HttpMethod = "GET",
//   body?: unknown,
//   options: QueryOptions = {},
// ): Promise<T> {
//   const url = new URL(`${baseUrl()}/${table}`);

//   if (options.params) {
//     for (const [k, v] of Object.entries(options.params)) {
//       url.searchParams.set(k, v);
//     }
//   }

//   const res = await fetch(url.toString(), {
//     method,
//     headers: {
//       "Content-Type": "application/json",
//       Accept: "application/json",
//       // Return the mutated row(s) after INSERT / PATCH / DELETE
//       Prefer: "return=representation",
//       ...authHeaders(),
//       ...options.headers,
//     },
//     body: body !== undefined ? JSON.stringify(body) : undefined,
//     // Next.js cache: don't cache DB reads by default
//     ...(method === "GET"
//       ? { next: options.next ?? { revalidate: 0 } }
//       : { cache: "no-store" }),
//   });
//   if (!res.ok) {
//     const err = await res.json().catch(() => ({ message: res.statusText }));
//     const error = new Error(err.message || res.statusText) as any;
//     error.code = err.code; // e.g. "23505"
//     error.details = err.details;
//     error.hint = err.hint;
//     throw error;
//   }

//   // 204 No Content
//   if (res.status === 204) return undefined as T;

//   return res.json() as Promise<T>;
// }

// /** Convenience wrappers */
// export const db = {
//   get: <T>(table: string, opts?: QueryOptions) =>
//     dbFetch<T>(table, "GET", undefined, opts),

//   post: <T>(table: string, body: unknown, opts?: QueryOptions) =>
//     dbFetch<T>(table, "POST", body, opts),

//   patch: <T>(table: string, body: unknown, opts?: QueryOptions) =>
//     dbFetch<T>(table, "PATCH", body, opts),

//   delete: <T>(table: string, opts?: QueryOptions) =>
//     dbFetch<T>(table, "DELETE", undefined, opts),

//   rpc: <T>(
//     functionName: string,
//     body?: Record<string, unknown>,
//     opts?: QueryOptions,
//   ) => dbFetch<T>(`rpc/${functionName}`, "POST", body, opts),
// };
