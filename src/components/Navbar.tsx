// components/Navbar.tsx — Server Component (no directive needed)
import { Suspense } from "react";
import { NavbarClient } from "./NavbarClient";

// Skeleton lives here — it's only used here
const NavbarSkeleton = () => {
  return (
    <div className="nav-bar">
      <div className="nav-title">Bill Book</div>
      <div className="nav-right">
        <button className="btn btn-ghost btn-sm">Vault Loading...</button>
        <button className="btn btn-ghost btn-sm">Blue Vault Loading...</button>
      </div>
    </div>
  );
};

export default async function Navbar() {
  // ✅ Pass raw data — let the client compute derived values
  return (
    <Suspense fallback={<NavbarSkeleton />}>
      <NavbarClient />
    </Suspense>
  );
}
