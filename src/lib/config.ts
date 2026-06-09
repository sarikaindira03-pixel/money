// lib/supabase/config.ts

export const IS_PROD = process.env.APP_ENV === "production";

// ─── Supabase ───────────────────────────────────────────────

export const supabaseUrl = IS_PROD
  ? process.env.NEXT_PUBLIC_SUPABASE_URL! // Supabase Cloud
  : process.env.POSTGREST_URL!;
export const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;
export const supabaseAuthKey = process.env.NEXT_PUBLIC_SUPABASE_AUTH_KEY!;
// SERVER ONLY
export const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY!; // ─── PostgREST ──────────────────────────────────────────────

export function adminAuthHeaders(): Record<string, string> {
  const key = supabaseServiceKey;

  return {
    apikey: key,
    Authorization: `Bearer ${key}`,
  };
}

export function anonAuthHeaders(): Record<string, string> {
  const key = supabaseAnonKey;

  return {
    apikey: key,
    Authorization: `Bearer ${key}`,
  };
}
