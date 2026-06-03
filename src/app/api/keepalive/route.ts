export const runtime = "edge";

export async function GET(req: Request) {
  const token = new URL(req.url).searchParams.get("token");

  if (token !== process.env.KEEPALIVE_SECRET) {
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const response = await fetch(
      `${process.env.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/`,
      {
        headers: {
          apikey: process.env.SUPABASE_SERVICE_ROLE_KEY!,
        },
      },
    );

    if (!response.ok) throw new Error(`Supabase response: ${response.status}`);

    return Response.json({
      success: true,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    console.error("Keepalive failed:", error);
    return Response.json({ error: "Keepalive ping failed" }, { status: 500 });
  }
}
