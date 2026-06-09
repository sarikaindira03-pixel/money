// lib/postgrest.ts
import { createClient } from "@supabase/supabase-js";
import { IS_PROD } from "../config";
// ✅ Fully safe — only runs on actual request
export const getSupabase = () => {
  return createClient(
    IS_PROD ? process.env.NEXT_PUBLIC_SUPABASE_URL! : "http://localhost:3000",
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    {
      auth: { persistSession: false, autoRefreshToken: false },
      global: !IS_PROD
        ? {
            fetch: (url: RequestInfo | URL, options?: RequestInit) => {
              const fixed = url.toString().replace("/rest/v1", "");
              return fetch(fixed, options);
            },
          }
        : {},
    },
  );
};
