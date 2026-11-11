import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Balaji Chit Funds | Management",
  description: "Chit fund operations and member account management.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en-IN"><body>{children}</body></html>;
}
