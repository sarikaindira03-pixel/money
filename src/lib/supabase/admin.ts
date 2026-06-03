/**
 * lib/supabase/admin.ts
 *
 * Service-role client — bypasses ALL RLS.
 * ⚠️  NEVER import this in client components. Server/API/webhook use only.
 *
 * Use in: API Routes, Webhooks, Cron Jobs, trusted Server Actions.
 *
 * Prod → @supabase/supabase-js with SUPABASE_SERVICE_ROLE_KEY
 * Dev  → @supabase/supabase-js with POSTGREST_JWT_TOKEN (or unauthenticated)
 *
 * This is a singleton — instantiated once per process, not per request.
 * It has no session and never should: requests run as the service role.
 */

import { createClient } from "@supabase/supabase-js";

const makeAdminClient = () => {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL! ||
      "https://kqxeiodkqidyqmtmhpjk.supabase.co",
    process.env.SUPABASE_SERVICE_ROLE_KEY! ||
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtxeGVpb2RrcWlkeXFtdG1ocGprIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4MDM2NzkxMCwiZXhwIjoyMDk1OTQzOTEwfQ.jcq39AJRc7cHpnHRyKI7fN-mWTlWdOULzRIRHe0W_4s",
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    },
  );

  // Dev: PostgREST with the highest-privilege JWT you have.
  // In local dev, if you're running PostgREST without auth, this is effectively
  // already the admin role — no key needed.
  // const jwt = postgrestJwt();
  // return createClient(postgrestUrl(), "dev-service-key", {
  //   global: {
  //     headers: jwt ? { Authorization: `Bearer ${jwt}` } : {},
  //   },
  //   auth: { persistSession: false, autoRefreshToken: false },
  // });
};

export const supabaseAdmin = makeAdminClient();

/*
 * Powers (prod):
 *   Service Role Key (secret — NEVER expose to browser)
 *   Bypasses ALL RLS — full database access
 *   Can create users, delete any row, modify any table
 *   ⚠️  One leaked key = full DB access
 *
 * Powers (dev):
 *   PostgREST with JWT (or open access if PostgREST has no auth configured)
 *   Effectively equivalent to admin in a local dev setup
 *
 * Typical usage:
 *   // In an API route or webhook:
 *   const { data } = await supabaseAdmin
 *     .from("orders")
 *     .update({ status: "fulfilled" })
 *     .eq("id", orderId);
 */
