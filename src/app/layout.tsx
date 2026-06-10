import StackProvider from "../lib/tanstack/StackProvider";
import "./styles/global.css";
// src/app/layout.tsx
export const metadata = {
  title: "Vault",
  description: "Web site created with Next.js for personal use.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>
        <div id="root">
          <div className="app">
            <StackProvider>{children}</StackProvider>
          </div>
        </div>
      </body>
    </html>
  );
}
