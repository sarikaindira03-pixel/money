// lib/supabase/config.ts

export const IS_PROD = process.env.APP_ENV === "production";

// ─── Supabase ───────────────────────────────────────────────

export const supabaseUrl = () =>
  process.env.NEXT_PUBLIC_SUPABASE_URL! ||
  "https://kqxeiodkqidyqmtmhpjk.supabase.co";

export const supabaseAnonKey = () =>
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY! ||
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtxeGVpb2RrcWlkeXFtdG1ocGprIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAzNjc5MTAsImV4cCI6MjA5NTk0MzkxMH0.avzcz_49WV0Ejr3SzYDM6eKzoOoZK5E36yiULZwGC9w";

// SERVER ONLY
export const supabaseServiceKey = () =>
  process.env.SUPABASE_SERVICE_ROLE_KEY! ||
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtxeGVpb2RrcWlkeXFtdG1ocGprIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4MDM2NzkxMCwiZXhwIjoyMDk1OTQzOTEwfQ.jcq39AJRc7cHpnHRyKI7fN-mWTlWdOULzRIRHe0W_4s";

// ─── PostgREST ──────────────────────────────────────────────

export const postgrestUrl = () =>
  process.env.NEXT_PUBLIC_POSTGREST_URL ?? "http://localhost:8081/rest/v1";

export const postgrestInternalUrl = () =>
  process.env.POSTGREST_INTERNAL_URL ?? "http://localhost:3000";

export const postgrestJwt = () => process.env.POSTGREST_JWT_TOKEN?.trim() ?? "";

export function dbBaseUrl(): string {
  return IS_PROD ? `${supabaseUrl()}/rest/v1` : postgrestInternalUrl();
}

export function adminAuthHeaders(): Record<string, string> {
  const key = supabaseServiceKey();

  return {
    apikey: key,
    Authorization: `Bearer ${key}`,
  };
}

export function anonAuthHeaders(): Record<string, string> {
  const key = supabaseAnonKey();

  return {
    apikey: key,
    Authorization: `Bearer ${key}`,
  };
}
