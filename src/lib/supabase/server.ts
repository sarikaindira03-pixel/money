// /**
//  * lib/supabase/server.ts
//  *
//  * Cookie-aware server client.
//  * Use in: Server Components, Server Actions, Route Handlers (API routes).
//  *
//  * Prod → @supabase/ssr createServerClient (reads/writes Next.js cookies)
//  * Dev  → @supabase/supabase-js createClient pointed at local PostgREST
//  *        (PostgREST doesn't need cookie-based auth — JWT from env is enough)
//  */

// import {
//   IS_PROD,
//   supabaseUrl,
//   supabaseAnonKey,
//   postgrestUrl,
//   postgrestJwt,
// } from "../config";

// export async function createClient() {
//   if (IS_PROD) {
//     const { createServerClient } = await import("@supabase/ssr");
//     const { cookies } = await import("next/headers");
//     const cookieStore = await cookies();

//     return createServerClient(supabaseUrl(), supabaseAnonKey(), {
//       cookies: {
//         getAll() {
//           return cookieStore.getAll();
//         },
//         setAll(cookiesToSet) {
//           try {
//             cookiesToSet.forEach(({ name, value, options }) =>
//               cookieStore.set(name, value, options),
//             );
//           } catch {
//             // Called from a Server Component — safe to ignore.
//             // Middleware handles session refresh.
//           }
//         },
//       },
//     });
//   }

//   // Dev: plain supabase-js client pointed at local PostgREST.
//   // No cookie plumbing needed — PostgREST uses the JWT directly.
//   const { createClient: createSupabaseClient } =
//     await import("@supabase/supabase-js");
//   const jwt = postgrestJwt();
//   return createSupabaseClient(postgrestUrl(), "dev-anon-key", {
//     global: {
//       headers: jwt ? { Authorization: `Bearer ${jwt}` } : {},
//     },
//     auth: { persistSession: false, autoRefreshToken: false },
//   });
// }

// /*
//  * Powers (prod):
//  *   Uses Anon Key + user's session cookie → respects RLS
//  *   Reads/writes Next.js cookies → session refreshes correctly
//  *
//  * Powers (dev):
//  *   Uses JWT from POSTGREST_JWT_TOKEN env var
//  *   PostgREST enforces whatever RLS policies you've defined locally
//  */

/**
 * lib/supabase/server.ts
 *
 * Cookie-aware server client.
 * Use in: Server Components, Server Actions, Route Handlers.
 *
 * Auth  → always real Supabase (session, OAuth, cookies)
 * Data  → switches in db.ts (PostgREST in dev, Supabase REST in prod)
 */

import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { supabaseUrl, supabaseAnonKey } from "../config";

export async function create_server_client() {
  const cookieStore = await cookies();

  return createServerClient(supabaseUrl(), supabaseAnonKey(), {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        try {
          cookiesToSet.forEach(({ name, value, options }) =>
            cookieStore.set(name, value, options),
          );
        } catch {
          // Called from a Server Component — safe to ignore.
          // Middleware handles session refresh.
        }
      },
    },
  });
}
