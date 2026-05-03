"use client";

import { motion, useInView } from "framer-motion";
import { useRef } from "react";
import { buttonVariants } from "@/components/ui/button";
import { Separator } from "@/components/ui/separator";
import { cn } from "@/lib/utils";
import { CheckCircle2 } from "lucide-react";

const promessas = [
  "Exército, Marinha ou Aeronáutica",
  "Aulas, revisões e testes por Força",
  "Instrutor virtual integrado",
  "Sem vínculo com Forças Armadas",
];

export function CTAFinal() {
  const ref = useRef(null);
  const isInView = useInView(ref, { once: true, margin: "-80px" });

  return (
    <section id="cta" ref={ref} className="py-28 px-6 bg-[#0B0B0B]">
      <div className="max-w-4xl mx-auto">
        <div className="relative">
          <div className="absolute inset-0 -top-20 flex items-center justify-center pointer-events-none" aria-hidden>
            <div
              className="w-[500px] h-[280px] rounded-full blur-3xl opacity-10"
              style={{ background: "radial-gradient(ellipse, #7ABF3C 0%, transparent 70%)" }}
            />
          </div>

          <motion.div
            initial={{ opacity: 0, y: 30 }}
            animate={isInView ? { opacity: 1, y: 0 } : {}}
            transition={{ duration: 0.7 }}
            className="relative text-center"
          >
            <span className="text-xs font-semibold text-[#7ABF3C] tracking-[0.3em] uppercase">
              Comece agora
            </span>

            <h2 className="mt-6 text-5xl md:text-6xl lg:text-7xl font-black text-white leading-[0.93] tracking-tight">
              Quem se prepara melhor fora,
              <br />
              <span className="gold-gradient">performa melhor dentro.</span>
            </h2>

            <p className="mt-8 text-gray-400 text-xl leading-relaxed max-w-2xl mx-auto">
              Comece com revisões estruturadas, acompanhe sua evolução e aumente
              suas chances de melhor desempenho na formação. O sistema registra
              cada passo — você só precisa estudar.
            </p>

            <motion.div
              initial={{ opacity: 0, y: 16 }}
              animate={isInView ? { opacity: 1, y: 0 } : {}}
              transition={{ delay: 0.15, duration: 0.6 }}
              className="mt-10 grid grid-cols-1 sm:grid-cols-2 gap-3 max-w-xl mx-auto text-left"
            >
              {promessas.map((p) => (
                <div key={p} className="flex items-center gap-2.5">
                  <CheckCircle2 className="w-4 h-4 text-[#7ABF3C] shrink-0" strokeWidth={1.5} />
                  <span className="text-sm text-gray-400">{p}</span>
                </div>
              ))}
            </motion.div>

            <Separator className="bg-[#222222] max-w-xs mx-auto my-10" />

            <motion.div
              initial={{ opacity: 0, y: 16 }}
              animate={isInView ? { opacity: 1, y: 0 } : {}}
              transition={{ delay: 0.25, duration: 0.6 }}
              className="flex flex-col sm:flex-row gap-4 items-center justify-center"
            >
              <a
                href="#forcas"
                className={cn(
                  buttonVariants({ size: "lg" }),
                  "w-full sm:w-auto gold-gradient-bg text-white font-bold tracking-wide hover:opacity-90 transition-opacity px-10 shadow-[0_0_40px_rgba(122,191,60,0.20)]"
                )}
              >
                Começar minha preparação
              </a>
              <a
                href="#como-funciona"
                className={cn(
                  buttonVariants({ variant: "outline", size: "lg" }),
                  "w-full sm:w-auto border-[#222222] text-gray-300 hover:border-[#7ABF3C]/40 hover:text-[#7ABF3C] bg-transparent px-10"
                )}
              >
                Ver como funciona
              </a>
            </motion.div>

            <motion.p
              initial={{ opacity: 0 }}
              animate={isInView ? { opacity: 1 } : {}}
              transition={{ delay: 0.4, duration: 0.6 }}
              className="mt-8 text-xs text-gray-600 max-w-lg mx-auto leading-relaxed"
            >
              O Quartel Digital é uma plataforma educacional independente, sem vínculo
              oficial com as Forças Armadas, Marinha do Brasil, Exército Brasileiro,
              Aeronáutica, Polícias Militares ou qualquer órgão governamental.
            </motion.p>
          </motion.div>
        </div>
      </div>
    </section>
  );
}
