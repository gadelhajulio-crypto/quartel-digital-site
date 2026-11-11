"use client";

import { motion, useScroll } from "framer-motion";
import { useState, useEffect } from "react";
import { buttonVariants } from "@/components/ui/button";
import { Separator } from "@/components/ui/separator";
import { cn } from "@/lib/utils";
import { Menu, X } from "lucide-react";
import Image from "next/image";

const navLinks = [
  { label: "Forças", href: "#forcas" },
  { label: "Como Funciona", href: "#como-funciona" },
  { label: "Instrutor", href: "#instrutor" },
  { label: "Resultados", href: "#resultados" },
  { label: "Diferenciais", href: "#diferenciais" },
];

export function Navbar() {
  const [isScrolled, setIsScrolled] = useState(false);
  const [isMenuOpen, setIsMenuOpen] = useState(false);
  const { scrollY } = useScroll();

  useEffect(() => {
    const unsubscribe = scrollY.on("change", (y) => setIsScrolled(y > 40));
    return unsubscribe;
  }, [scrollY]);

  return (
    <motion.header
      initial={{ y: -80, opacity: 0 }}
      animate={{ y: 0, opacity: 1 }}
      transition={{ duration: 0.6, ease: "easeOut" }}
      className={`fixed top-0 left-0 right-0 z-50 transition-all duration-300 ${
        isScrolled
          ? "bg-[#0B0B0B]/95 backdrop-blur-xl border-b border-[#222222]"
          : "bg-transparent"
      }`}
    >
      <div className="max-w-7xl mx-auto px-6 h-16 flex items-center justify-between">
        {/* Logo */}
        <a href="#" className="flex items-center gap-3">
          <Image
            src="/assets/brand/quartel-digital-v1/QD_12_horizontal_grafite.svg"
            alt="Quartel Digital"
            width={2400}
            height={900}
            className="h-auto w-40 shrink-0"
            unoptimized
          />
        </a>

        {/* Desktop nav */}
        <nav className="hidden md:flex items-center gap-7">
          {navLinks.map((link) => (
            <a
              key={link.href}
              href={link.href}
              className="text-xs font-medium text-gray-400 hover:text-[#B89B5E] transition-colors duration-200 tracking-wide uppercase"
            >
              {link.label}
            </a>
          ))}
        </nav>

        {/* CTA */}
        <div className="hidden md:block">
          <a
            href="#forcas"
            className={cn(
              buttonVariants({ variant: "outline", size: "sm" }),
              "border-[#B89B5E]/40 text-[#B89B5E] hover:bg-[#B89B5E] hover:text-[#102820] bg-transparent font-semibold transition-all duration-200"
            )}
          >
            Começar preparação
          </a>
        </div>

        {/* Mobile toggle */}
        <button
          onClick={() => setIsMenuOpen(!isMenuOpen)}
          className="md:hidden text-gray-400 hover:text-white transition-colors"
          aria-label="Menu"
        >
          {isMenuOpen ? <X className="w-5 h-5" /> : <Menu className="w-5 h-5" />}
        </button>
      </div>

      {/* Mobile menu */}
      {isMenuOpen && (
        <motion.div
          initial={{ opacity: 0, y: -8 }}
          animate={{ opacity: 1, y: 0 }}
          className="md:hidden bg-[#121212] border-b border-[#222222] px-6 py-5 flex flex-col gap-4"
        >
          {navLinks.map((link) => (
            <a
              key={link.href}
              href={link.href}
              onClick={() => setIsMenuOpen(false)}
              className="text-sm text-gray-300 hover:text-[#B89B5E] transition-colors tracking-wide"
            >
              {link.label}
            </a>
          ))}
          <Separator className="bg-[#222222]" />
          <a
            href="#forcas"
            onClick={() => setIsMenuOpen(false)}
            className={cn(
              buttonVariants({ variant: "outline" }),
              "border-[#B89B5E]/40 text-[#B89B5E] hover:bg-[#B89B5E] hover:text-[#102820] bg-transparent w-full justify-center"
            )}
          >
            Começar preparação
          </a>
        </motion.div>
      )}
    </motion.header>
  );
}
