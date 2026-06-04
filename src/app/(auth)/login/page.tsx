"use client";
import { useState } from "react";
import { toast } from "sonner";
import { IconLoader2, IconBrandGoogle } from "@tabler/icons-react";
import { create_client } from "@/src/lib/supabase/client";

export default function LoginPage() {
  const [googleLoading, setGoogleLoading] = useState(false);

  // async function handleGoogleLogin() {
  //   const next = new URLSearchParams(window.location.search).get("next") ?? "/";
  //   setGoogleLoading(true);
  //   const supabase = create_client();
  //   const { error } = await supabase.auth.signInWithOAuth({
  //     provider: "google",
  //     options: {
  //       redirectTo: `${window.location.origin}/auth/callback?next=${next}`,
  //     },
  //   });
  //   if (error) {
  //     toast.error(error.message);
  //     setGoogleLoading(false);
  //   }
  // }

  async function handleGoogleLogin() {
    setGoogleLoading(true);
    const supabase = create_client();

    const redirectTo = `${window.location.origin}/auth/callback?next=/`;

    const { error } = await supabase.auth.signInWithOAuth({
      provider: "google",
      options: {
        redirectTo,
      },
    });

    if (error) {
      toast.error(error.message);
      setGoogleLoading(false);
    }
  }
  return (
    <div className="min-h-screen flex items-center justify-center">
      <div
        style={{
          background: "var(--bg1)",
          border: "1px solid var(--border2)",
          padding: 20,
          width: 320, // optional
        }}
      >
        <button
          className="btn btn-ghost"
          onClick={handleGoogleLogin}
          disabled={googleLoading}
          style={{
            width: "100%",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            gap: 10,
            opacity: googleLoading ? 0.5 : 1,
            cursor: googleLoading ? "not-allowed" : "pointer",
          }}
        >
          {googleLoading ? (
            <IconLoader2
              size={13}
              style={{ animation: "spin 0.7s linear infinite" }}
            />
          ) : (
            <IconBrandGoogle size={13} />
          )}
          Continue with Google
        </button>
      </div>
    </div>
  );
}
