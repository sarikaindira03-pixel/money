// "use client";
// import { useState } from "react";
// // import { useRouter } from "next/navigation";
// import Link from "next/link";
// import { toast } from "sonner";
// import {
//   Card,
//   CardContent,
//   CardHeader,
//   CardTitle,
//   CardDescription,
// } from "../../components/ui/table/card";
// import {
//   IconLoader2,
//   // IconEye,
//   // IconEyeOff,
//   IconBrandGoogle,
// } from "@tabler/icons-react";
// import { create_client } from "@/src/lib/supabase/client";
// import { Button } from "@/src/components/ui/button";
// // import { Label } from "@/src/components/ui/label";
// // import { Input } from "@/src/components/ui/input";

// export default function LoginPage() {
//   // const router = useRouter();
//   // const [email, setEmail] = useState("");
//   // const [password, setPassword] = useState("");
//   // const [showPassword, setShowPassword] = useState(false);
//   // const [loading, setLoading] = useState(false);
//   const [googleLoading, setGoogleLoading] = useState(false);

//   // async function handleEmailLogin(e: React.FormEvent) {
//   //   e.preventDefault();
//   //   if (!email || !password) {
//   //     toast.error("Please enter email and password");
//   //     return;
//   //   }
//   //   setLoading(true);
//   //   const supabase = createClient();
//   //   const { error } = await supabase.auth.signInWithPassword({
//   //     email,
//   //     password,
//   //   });
//   //   setLoading(false);
//   //   if (error) {
//   //     toast.error(
//   //       error.message === "Invalid login credentials"
//   //         ? "Incorrect email or password"
//   //         : error.message,
//   //     );
//   //     return;
//   //   }
//   //   toast.success("Signed in successfully!");
//   //   const next = new URLSearchParams(window.location.search).get("next") ?? "/";
//   //   router.push(next);
//   //   router.refresh();
//   // }

//   async function handleGoogleLogin() {
//     const next = new URLSearchParams(window.location.search).get("next") ?? "/";

//     setGoogleLoading(true);
//     const supabase = create_client();
//     const { error } = await supabase.auth.signInWithOAuth({
//       provider: "google",
//       options: {
//         redirectTo: `${window.location.origin}/auth/callback?next=${next}`,
//       },
//     });

//     // here if we have manaual redirect ("/") then it overwrite originalNext ?next= "/admin" (from URL)
//     if (error) {
//       toast.error(error.message);
//       setGoogleLoading(false);
//     }
//     // Page will redirect — no need to setGoogleLoading(false)
//   }

//   return (
//     <div className="min-h-screen flex flex-col">
//       <main className="flex-1 flex items-center justify-center px-4 py-16 bg-linear-to-br from-orange-50/50 to-amber-50/30 dark:from-orange-950/20 dark:to-background">
//         <div className="w-full max-w-md">
//           <div className="text-center mb-8">
//             <div className="h-14 w-14 rounded-2xl bg-linear-to-br from-orange-500 to-amber-400 flex items-center justify-center text-white font-bold text-2xl mx-auto mb-4 shadow-lg">
//               V
//             </div>
//             <h1 className="text-3xl font-bold bg-linear-to-r from-orange-600 to-amber-500 bg-clip-text text-transparent">
//               Welcome Back
//             </h1>
//             <p className="text-muted-foreground mt-2 text-sm">
//               Sign in to your Vijaya account to continue shopping
//             </p>
//           </div>

//           <Card className="shadow-xl border-0 bg-card/80 backdrop-blur">
//             <CardHeader className="pb-4">
//               <CardTitle className="text-xl">Sign In</CardTitle>
//               <CardDescription>
//                 Don&apos;t have an account?{" "}
//                 <Link
//                   href="/register"
//                   className="text-primary font-medium hover:underline"
//                 >
//                   Create one free
//                 </Link>
//               </CardDescription>
//             </CardHeader>
//             <CardContent className="space-y-4">
//               <Button
//                 variant="outline"
//                 className="w-full"
//                 onClick={handleGoogleLogin}
//                 disabled={googleLoading}
//               >
//                 {googleLoading ? (
//                   <IconLoader2 className="mr-2 h-4 w-4 animate-spin" />
//                 ) : (
//                   <IconBrandGoogle className="mr-2 h-4 w-4 text-red-500" />
//                 )}
//                 Continue with Google Login
//               </Button>

//               {/* <div className="relative">
//                 <div className="absolute inset-0 flex items-center">
//                   <span className="w-full border-t" />
//                 </div>
//                 <div className="relative flex justify-center text-xs uppercase">
//                   <span className="bg-card px-2 text-muted-foreground">
//                     or email
//                   </span>
//                 </div>
//               </div>

//               <form onSubmit={handleEmailLogin} className="space-y-4">
//                 <div className="space-y-1.5">
//                   <Label htmlFor="login-email">Email Address</Label>
//                   <Input
//                     id="login-email"
//                     type="email"
//                     placeholder="you@example.com"
//                     value={email}
//                     onChange={(e) => setEmail(e.target.value)}
//                     required
//                     autoComplete="email"
//                     disabled={loading}
//                   />
//                 </div>

//                 <div className="space-y-1.5">
//                   <div className="flex items-center justify-between">
//                     <Label htmlFor="login-password">Password</Label>
//                     <Link
//                       href="/forgot-password"
//                       className="text-xs text-primary hover:underline"
//                     >
//                       Forgot password?
//                     </Link>
//                   </div>
//                   <div className="relative">
//                     <Input
//                       id="login-password"
//                       type={showPassword ? "text" : "password"}
//                       placeholder="Enter your password"
//                       value={password}
//                       onChange={(e) => setPassword(e.target.value)}
//                       required
//                       autoComplete="current-password"
//                       className="pr-10"
//                       disabled={loading}
//                     />
//                     <button
//                       type="button"
//                       onClick={() => setShowPassword((v) => !v)}
//                       className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
//                     >
//                       {showPassword ? (
//                         <IconEyeOff className="h-4 w-4" />
//                       ) : (
//                         <IconEye className="h-4 w-4" />
//                       )}
//                     </button>
//                   </div>
//                 </div>

//                 <Button
//                   type="submit"
//                   className="w-full"
//                   disabled={loading || googleLoading}
//                 >
//                   {loading && (
//                     <IconLoader2 className="mr-2 h-4 w-4 animate-spin" />
//                   )}
//                   Sign In
//                 </Button>
//               </form> */}
//             </CardContent>
//           </Card>
//         </div>
//       </main>
//     </div>
//   );
// }

"use client";
import { useState } from "react";
import { toast } from "sonner";
import { IconLoader2, IconBrandGoogle } from "@tabler/icons-react";
import { create_client } from "@/src/lib/supabase/client";

export default function LoginPage() {
  const [googleLoading, setGoogleLoading] = useState(false);

  async function handleGoogleLogin() {
    const next = new URLSearchParams(window.location.search).get("next") ?? "/";
    setGoogleLoading(true);
    const supabase = create_client();
    const { error } = await supabase.auth.signInWithOAuth({
      provider: "google",
      options: {
        redirectTo: `${window.location.origin}/auth/callback?next=${next}`,
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
