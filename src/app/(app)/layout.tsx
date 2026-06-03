// src/app/(app)/layout.tsx
import Navbar from "@/src/components/Navbar";

export default function AppLayout({ children }: { children: React.ReactNode }) {
  return (
    <>
      <Navbar />
      {children}
    </>
  );
}
