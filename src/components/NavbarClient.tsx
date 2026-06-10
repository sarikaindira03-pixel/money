// components/NavbarClient.tsx
"use client";
import { fmt } from "../lib/formats";
import NavButton from "./ui/NavButton";
import { useLockerQuery } from "../hooks/lockers/useLockerQuery";
import { create_client } from "../lib/supabase/client";
import { useRouter } from "next/navigation";

export function NavbarClient() {
  const { data } = useLockerQuery();

  const router = useRouter();
  const supabase = create_client();
  const vb = data?.main_vault_balance ?? 0;
  const bvb = data?.blue_vault_balance ?? 0;
  const handleLogout = async () => {
    await supabase.auth.signOut();
    router.push("/login");
  };
  return (
    <div className="nav-bar">
      <div className="nav-title">Bill Book</div>
      <div className="nav-right">
        <NavButton
          className="cursor-not-allowed ml-1"
          variant={vb > 0 ? "yellow" : "ghost"}
        >
          Vault {fmt(vb)}
        </NavButton>
        <NavButton
          className="cursor-not-allowed"
          variant={bvb > 0 ? "blue" : "ghost"}
        >
          Blue Vault{fmt(bvb)}
        </NavButton>
        <NavButton variant="danger" onClick={handleLogout}>
          Logout
        </NavButton>
      </div>
    </div>
  );
}
