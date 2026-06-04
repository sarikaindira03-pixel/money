export const runtime = "edge";

export async function GET(req: Request) {
  // Protect the endpoint
  const authHeader = req.headers.get("authorization");
  if (authHeader !== `Bearer ${process.env.CRON_SECRET}`) {
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const response = await fetch(
      `${process.env.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/`,
      {
        headers: {
          apikey: process.env.SUPABASE_SERVICE_ROLE_KEY!,
          Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY!}`,
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
      message: "Keepalive ping successful",
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    return Response.json(
      { error: "Keepalive ping failed", detail: String(error) },
      { status: 500 },
    );
  }
}
