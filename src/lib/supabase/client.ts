// /**
//  * lib/supabase/client.ts
//  *
//  * Browser client — use in React Client Components ('use client').
//  *
//  * Prod → @supabase/ssr createBrowserClient (reads auth session from browser cookies)
//  * Dev  → @supabase/supabase-js createClient pointed at local PostgREST
//  *
//  * Call createClient() once per component tree, not per render.
//  * Recommended: create it outside the component or inside useMemo.
//  */

// import {
//   IS_PROD,
//   supabaseUrl,
//   supabaseAnonKey,
//   postgrestUrl,
//   postgrestJwt,
// } from "../config";

// export function createClient() {
//   if (IS_PROD) {
//     // Lazy import keeps this out of server bundles
//     const { createBrowserClient } = require("@supabase/ssr");
//     return createBrowserClient(supabaseUrl(), supabaseAnonKey());
//   }

//   // Dev: plain supabase-js client. The browser doesn't have a PostgREST
//   // cookie-based session — we use the JWT from env instead.
//   const {
//     createClient: createSupabaseClient,
//   } = require("@supabase/supabase-js");
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
//  *   Anon key (safe to expose) + browser cookie session → respects RLS
//  *   User only sees rows their RLS policies allow
//  *
//  * Powers (dev):
//  *   JWT from env → PostgREST RLS policies (if any)
//  *   No real auth flow — assumes you're testing as a single dev user
//  */

/**
 * lib/supabase/client.ts
 *
 * Browser client — use in React Client Components ('use client').
 *
 * Both prod and dev:
 *   Auth  → always real Supabase (Google OAuth, email/password, sessions)
 *   Data  → switches in db.ts via IS_PROD (PostgREST locally, Supabase REST in prod)
 *
 * Call createClient() once per component tree, not per render.
 */

import { createBrowserClient } from "@supabase/ssr";
// import { supabaseUrl, supabaseAnonKey } from "../config";

export function create_client() {
  // Auth is never local — always real Supabase regardless of IS_PROD.
  // PostgREST has no /auth/v1 endpoint; it cannot handle OAuth or sessions.
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  );
}

/*
 * Dev:  NEXT_PUBLIC_SUPABASE_URL + NEXT_PUBLIC_SUPABASE_ANON_KEY must be real.
 *       Data calls go through db.ts → PostgREST (localhost:3000).
 *       JWT for PostgREST comes from POSTGREST_JWT_TOKEN (server-side only).
 *
 * Prod: Same client. Data calls go through db.ts → Supabase REST.
 *       Session token from cookie is used by server.ts / middleware.ts.
 */
