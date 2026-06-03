// src/lib/withAuth.ts
import { createClient } from "@supabase/supabase-js"; // adjust path to your supabase config
import { badRequest, unauthorized } from "@/src/lib/apiResponse";

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;

// Define a type for your authenticated handler
type AuthenticatedHandler = (
  req: Request,
  context: { userId: string; [key: string]: any },
) => Promise<Response>;

export function withAuth(handler: AuthenticatedHandler) {
  return async (req: Request, routeContext: any) => {
    try {
      // 1. Initialize Supabase client using headers from the current request
      // This is crucial so Supabase can read the incoming session cookies/auth tokens
      const supabase = createClient(supabaseUrl, supabaseAnonKey, {
        auth: {
          persistSession: false,
        },
      });

      // Alternatively, if you use @supabase/ssr, initialize your server client here

      // 2. Fetch and verify the session securely on the server
      const {
        data: { session },
        error: authError,
      } = await supabase.auth.getSession();

      if (authError || !session?.user) {
        console.error("User not authenticated:", authError?.message);
        return unauthorized("User not authenticated");
      }

      // 3. Forward the request to the handler, appending the secure userId
      return await handler(req, { ...routeContext, userId: session.user.id });
    } catch (error) {
      console.error("Auth Guard critical error:", error);
      return badRequest("Internal authentication routing failure");
    }
  };
}
