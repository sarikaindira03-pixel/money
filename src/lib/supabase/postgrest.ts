// lib/postgrest.ts
// lib/postgrest.ts
import { createClient } from "@supabase/supabase-js";
import { IS_PROD, supabaseServiceKey, supabaseUrl } from "../config";

const supabase = createClient(supabaseUrl, supabaseServiceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
  global: IS_PROD
    ? {} // prod uses standard Supabase client — no fetch override needed
    : {
        fetch: (url: RequestInfo | URL, options?: RequestInit) => {
          const fixed = url.toString().replace("/rest/v1", "");
          return fetch(fixed, options);
        },
      },
});

export default supabase;
