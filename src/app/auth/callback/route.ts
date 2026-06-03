import { create_server_client } from "@/src/lib/supabase/server";
import { NextResponse } from "next/server";
//app/auth/callback/route.ts
// handles the callback from Supabase Auth after a user logs in via OAuth (Google, GitHub, etc.).

export async function GET(request: Request) {
  // 1. Parse the URL to get the OAuth code and where to redirect after
  const { searchParams, origin } = new URL(request.url);
  const code = searchParams.get("code"); // The OAuth code from Google/GitHub
  const next = searchParams.get("next") ?? "/"; // Where to go after login (default: home)

  // 2. If we have a code, exchange it for a session
  if (code) {
    const supabase = await create_server_client();
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    // 3. If successful, redirect to the intended page
    if (!error) {
      // Example: If user was trying to go to /account before login,
      // they'll be redirected there after login
      return NextResponse.redirect(`${origin}${next}`);
    }
  }
  // 4. If something failed, redirect to login with error message
  return NextResponse.redirect(`${origin}/login?error=auth_callback_failed`);
}
