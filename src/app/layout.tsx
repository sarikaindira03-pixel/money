import StackProvider from "../lib/tanstack/StackProvider";
import "./styles/global.css";
// src/app/layout.tsx
export const metadata = {
  title: "Next App",
  description: "Web site created with Next.js.",
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
