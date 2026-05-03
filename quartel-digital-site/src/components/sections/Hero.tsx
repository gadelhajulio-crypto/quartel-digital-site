"use client";

import { motion } from "framer-motion";
import { buttonVariants } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";

const anim = (delay: number) => ({
  initial: { opacity: 0, y: 28 },
  animate: { opacity: 1, y: 0 },
  transition: { delay, duration: 0.7, ease: [0.25, 0.46, 0.45, 0.94] as const },
});

export function Hero() {
  return (
    <section className="relative min-h-screen flex flex-col items-center justify-center overflow-hidden px-6 pt-20 bg-[#0B0B0B]">
      {/* Grid background */}
      <div
        className="absolute inset-0 opacity-[0.03]"
        style={{
          backgroundImage: `
            linear-gradient(to right, #7ABF3C 1px, transparent 1px),
            linear-gradient(to bottom, #7ABF3C 1px, transparent 1px)
          `,
          backgroundSize: "56px 56px",
        }}
      />
      {/* Glow */}
      <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
        <div
          className="w-[700px] h-[500px] rounded-full blur-3xl"
          style={{ background: "radial-gradient(ellipse, rgba(122,191,60,0.07) 0%, transparent 70%)" }}
        />
      </div>

      {/* Badge */}
      <motion.div {...anim(0)} className="mb-8">
        <Badge
          variant="outline"
          className="border-[#7ABF3C]/40 bg-[#7ABF3C]/5 text-[#7ABF3C] px-4 py-1.5 text-xs tracking-widest uppercase rounded-full font-medium"
        >
          <span className="w-1.5 h-1.5 rounded-full bg-[#7ABF3C] animate-pulse mr-2 inline-block" />
          Sistema de Excelência Acadêmica Militar · Recruta Padrão
        </Badge>
      </motion.div>

      {/* Headline */}
      <motion.h1
        {...anim(0.15)}
        className="text-center font-black text-5xl md:text-7xl lg:text-8xl leading-[0.95] tracking-tight max-w-4xl"
      >
        <span className="text-white">Você não precisa</span>
        <br />
        <span className="text-white">estudar mais.</span>
        <br />
        <span className="gold-gradient">Precisa estudar com sistema.</span>
      </motion.h1>

      {/* Subtitle */}
      <motion.p
        {...anim(0.3)}
        className="mt-8 text-center text-gray-400 text-lg md:text-xl leading-relaxed max-w-2xl"
      >
        O Quartel Digital transforma estudo solto em formação, desempenho e
        progressão para recrutas que querem sair do meio da fila e disputar
        posição.
      </motion.p>

      {/* CTAs */}
      <motion.div {...anim(0.45)} className="mt-10 flex flex-col sm:flex-row gap-4 items-center">
        <a
          href="#forcas"
          className={cn(
            buttonVariants({ size: "lg" }),
            "gold-gradient-bg text-white font-bold tracking-wide hover:opacity-90 transition-opacity px-8 shadow-[0_0_30px_rgba(122,191,60,0.25)]"
          )}
        >
          Começar minha preparação
        </a>
        <a
          href="#como-funciona"
          className={cn(
            buttonVariants({ variant: "outline", size: "lg" }),
            "border-[#222222] text-gray-300 hover:border-[#7ABF3C]/50 hover:text-[#7ABF3C] bg-transparent px-8"
          )}
        >
          Ver como funciona
        </a>
      </motion.div>

      {/* Independence notice */}
      <motion.p
        {...anim(0.6)}
        className="mt-8 text-xs text-gray-600 text-center max-w-md"
      >
        Plataforma educacional independente. Sem vínculo oficial com Forças
        Armadas ou órgãos governamentais.
      </motion.p>

      {/* Stats */}
      <motion.div
        {...anim(0.7)}
        className="mt-16 grid grid-cols-3 gap-8 md:gap-20 text-center"
      >
        {[
          { value: "3 Forças", label: "Exército, Marinha e Aeronáutica" },
          { value: "1 Sistema", label: "Aula, revisão, prática e progressão" },
          { value: "Posição", label: "Desempenho e classificação na formação" },
        ].map((stat) => (
          <div key={stat.label}>
            <p className="text-xl md:text-3xl font-black gold-gradient">{stat.value}</p>
            <p className="text-xs md:text-sm text-gray-500 mt-1.5 tracking-wide leading-snug max-w-[130px] mx-auto">
              {stat.label}
            </p>
          </div>
        ))}
      </motion.div>

      {/* Scroll indicator */}
      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 1.4, duration: 0.8 }}
        className="absolute bottom-8 left-1/2 -translate-x-1/2 flex flex-col items-center gap-2"
      >
        <motion.div
          animate={{ y: [0, 7, 0] }}
          transition={{ repeat: Infinity, duration: 1.6 }}
          className="w-px h-10 bg-gradient-to-b from-[#7ABF3C]/40 to-transparent"
        />
      </motion.div>
    </section>
  );
}
