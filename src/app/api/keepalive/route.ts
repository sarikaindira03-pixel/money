export const runtime = "edge";

export async function GET(req: Request) {
  const token = new URL(req.url).searchParams.get("token");
  if (token?.trim() !== process.env.KEEPALIVE_SECRET?.trim()) {
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  }

  // Guard against missing env vars
  if (
    !process.env.NEXT_PUBLIC_SUPABASE_URL ||
    !process.env.SUPABASE_SERVICE_ROLE_KEY
  ) {
    return Response.json({ error: "Missing env vars" }, { status: 500 });
  }

  try {
    const response = await fetch(
      `${process.env.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/`,
      {
        headers: {
          apikey: process.env.SUPABASE_SERVICE_ROLE_KEY,
        },
      },
    );

    if (!response.ok) {
      return Response.json(
        { error: `Supabase error: ${response.status}` },
        { status: 502 },
      );
    }

    return Response.json({
      success: true,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    return Response.json(
      { error: "Keepalive ping failed", detail: String(error) },
      { status: 500 },
    );
  }
}
