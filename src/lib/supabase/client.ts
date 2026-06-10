import { createBrowserClient } from "@supabase/ssr";

export function create_client() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!, // always use real Supabase for auth
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  );
}
