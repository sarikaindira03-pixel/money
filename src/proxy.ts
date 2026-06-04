// proxy.ts
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { createClient } from "@supabase/supabase-js";

export async function proxy(request: NextRequest) {
  const pathname = request.nextUrl.pathname;

  // Get both cookie chunks and concatenate
  const chunk0 =
    request.cookies.get("sb-kqxeiodkqidyqmtmhpjk-auth-token.0")?.value ?? "";
  const chunk1 =
    request.cookies.get("sb-kqxeiodkqidyqmtmhpjk-auth-token.1")?.value ?? "";
  const rawCookie = chunk0 + chunk1;

  let accessToken: string | undefined;
  try {
    // Strip the "base64-" prefix, then decode
    const stripped = rawCookie.startsWith("base64-")
      ? rawCookie.slice(7)
      : rawCookie;
    const decoded = Buffer.from(stripped, "base64").toString("utf-8");
    const parsed = JSON.parse(decoded);
    accessToken = parsed?.access_token;
  } catch {
    accessToken = undefined;
  }

  const supabase = createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      global: {
        headers: accessToken ? { Authorization: `Bearer ${accessToken}` } : {},
      },
      auth: {
        persistSession: false, // no localStorage needed
        autoRefreshToken: false, // middleware shouldn't refresh tokens
        detectSessionInUrl: false,
      },
    },
  );

  const {
    data: { user },
  } = await supabase.auth.getUser(accessToken);

  const publicPaths = ["/login", "/guide", "/api/keepalive"];
  const isPublic = publicPaths.some((p) => pathname.startsWith(p));

  if (!isPublic && !user) {
    // API routes → return 401 instead of redirecting
    if (pathname.startsWith("/api/")) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }
    const loginUrl = new URL("/login", request.url);
    loginUrl.searchParams.set("next", pathname);
    return NextResponse.redirect(loginUrl);
  }

  if (pathname === "/login" && user) {
    return NextResponse.redirect(new URL("/", request.url));
  }

  if (user && pathname.startsWith("/api/")) {
    const requestHeaders = new Headers(request.headers);
    requestHeaders.set("x-user-id", user.id);
    return NextResponse.next({
      request: { headers: requestHeaders },
    });
  }

  return NextResponse.next({ request: { headers: request.headers } });
}

export const config = {
  matcher: ["/", "/month/:path*", "/login", "/guide/:path*", "/api/:path*"],
};
