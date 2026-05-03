"use client";

import { motion, useInView } from "framer-motion";
import { useRef } from "react";
import { ArrowRight } from "lucide-react";

const fluxo = [
  "Aula",
  "Revisão",
  "Prática",
  "Avaliação",
  "Desempenho",
  "Ranking",
  "Progressão",
];

export function SistemaProgressao() {
  const ref = useRef(null);
  const isInView = useInView(ref, { once: true, margin: "-80px" });

  return (
    <section ref={ref} className="py-28 px-6 bg-[#0B0B0B]">
      <div className="max-w-7xl mx-auto">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={isInView ? { opacity: 1, y: 0 } : {}}
          transition={{ duration: 0.6 }}
          className="text-center mb-16"
        >
          <span className="text-xs font-semibold text-[#7ABF3C] tracking-[0.3em] uppercase">
            O Sistema
          </span>
          <h2 className="mt-4 text-4xl md:text-5xl font-black text-white leading-tight">
            Sistema de Progressão Acadêmica
          </h2>
          <p className="mt-4 text-gray-400 text-lg max-w-2xl mx-auto leading-relaxed">
            O Quartel Digital conecta cada parte da formação para transformar
            esforço em desempenho.
          </p>
        </motion.div>

        {/* Fluxo visual */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={isInView ? { opacity: 1, y: 0 } : {}}
          transition={{ duration: 0.6, delay: 0.15 }}
          className="flex flex-wrap items-center justify-center gap-2 mb-16"
        >
          {fluxo.map((etapa, i) => (
            <div key={etapa} className="flex items-center gap-2">
              <div className="bg-[#121212] border border-[#7ABF3C]/30 rounded-xl px-5 py-3 text-center">
                <span className="text-[10px] text-[#7ABF3C]/60 font-mono tracking-widest uppercase block mb-0.5">
                  {String(i + 1).padStart(2, "0")}
                </span>
                <span className="text-sm font-bold text-white">{etapa}</span>
              </div>
              {i < fluxo.length - 1 && (
                <ArrowRight className="w-4 h-4 text-[#7ABF3C]/30 shrink-0" />
              )}
            </div>
          ))}
        </motion.div>

        <motion.div
          initial={{ opacity: 0, y: 16 }}
          animate={isInView ? { opacity: 1, y: 0 } : {}}
          transition={{ duration: 0.6, delay: 0.3 }}
          className="max-w-3xl mx-auto border border-[#7ABF3C]/15 bg-[#121212] rounded-2xl px-8 py-8 text-center"
        >
          <p className="text-gray-300 text-lg leading-relaxed">
            Você não consome conteúdo de forma solta. Você entra em uma
            estrutura contínua que organiza{" "}
            <span className="text-white font-semibold">o que estudar</span>,{" "}
            <span className="text-white font-semibold">quando revisar</span>,{" "}
            <span className="text-white font-semibold">como praticar</span> e
            como acompanhar sua evolução.
          </p>
        </motion.div>
      </div>
    </section>
  );
}
