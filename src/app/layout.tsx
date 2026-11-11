import type { Metadata } from "next";
import { Inter, Geist } from "next/font/google";
import "./globals.css";
import { cn } from "@/lib/utils";

const geist = Geist({subsets:['latin'],variable:'--font-sans'});

const inter = Inter({
  subsets: ["latin"],
  variable: "--font-inter",
  display: "swap",
});

export const metadata: Metadata = {
  icons: {
    icon: [
      { url: "/assets/brand/quartel-digital-v1/QD_favicon_mira_original.svg", type: "image/svg+xml", sizes: "any" },
      { url: "/assets/brand/quartel-digital-v1/QD_favicon_mira_16.png", type: "image/png", sizes: "16x16" },
      { url: "/assets/brand/quartel-digital-v1/QD_favicon_mira_32.png", type: "image/png", sizes: "32x32" },
    ],
    apple: [{ url: "/assets/brand/quartel-digital-v1/QD_favicon_mira_180.png", sizes: "180x180", type: "image/png" }],
  },
  title: "Quartel Digital — Sistema de desempenho para recrutas",
  description:
    "Sistema de excelência acadêmica militar da plataforma Recruta Padrão, com trilhas, revisão, prática, instrutor virtual e progressão para recrutas.",
  keywords:
    "sistema de estudo recruta, desempenho militar, preparação formação militar, exército marinha aeronáutica, notas quartel, classificação recruta, progressão acadêmica",
  openGraph: {
    title: "Quartel Digital — Sistema de desempenho para recrutas",
    description:
      "Sistema de excelência acadêmica militar da plataforma Recruta Padrão, com trilhas, revisão, prática, instrutor virtual e progressão para recrutas.",
    type: "website",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="pt-BR" className={cn("h-full", inter.variable, "font-sans", geist.variable)}>
      <body className="min-h-full flex flex-col antialiased">{children}</body>
    </html>
  );
}
