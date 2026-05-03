"use client";

import { motion, useInView } from "framer-motion";
import { useRef } from "react";
import { MonitorSmartphone } from "lucide-react";

const etapas = [
  {
    number: "01",
    title: "Você acessa sua trilha",
    description:
      "Conteúdos organizados conforme a Força selecionada. Sem dispersão — só o que é relevante para a sua formação.",
  },
  {
    number: "02",
    title: "Estuda com aulas e revisões",
    description:
      "Aulas, resumos e revisões estruturadas para manter ritmo e constância ao longo da formação.",
  },
  {
    number: "03",
    title: "Pratica com testes",
    description:
      "Exercícios e avaliações ajudam a transformar conteúdo em retenção real e preparo para avaliações.",
  },
  {
    number: "04",
    title: "Tira dúvidas com o instrutor virtual",
    description:
      "O instrutor virtual apoia seus estudos com explicações e direcionamento dentro da sua trilha.",
  },
  {
    number: "05",
    title: "Acompanha sua evolução",
    description:
      "O sistema mostra progresso, desempenho e posição dentro da jornada para você saber onde está.",
  },
];

export function Metodo() {
  const ref = useRef(null);
  const isInView = useInView(ref, { once: true, margin: "-100px" });

  return (
    <section id="como-funciona" ref={ref} className="py-28 px-6 bg-[#F5F5F5]">
      <div className="max-w-7xl mx-auto">
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-16 items-start">

          {/* Etapas */}
          <div>
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={isInView ? { opacity: 1, y: 0 } : {}}
              transition={{ duration: 0.6 }}
              className="mb-12"
            >
              <span className="text-xs font-semibold text-[#7ABF3C] tracking-[0.3em] uppercase">
                Passo a Passo
              </span>
              <h2 className="mt-4 text-4xl md:text-5xl font-black text-[#111111] leading-tight">
                Como funciona na prática
              </h2>
              <p className="mt-4 text-[#555555] text-lg">
                Tudo acontece dentro do aplicativo.
              </p>
            </motion.div>

            <div className="relative">
              <div className="absolute left-[27px] top-3 bottom-3 w-px bg-gradient-to-b from-[#7ABF3C]/30 via-[#7ABF3C]/15 to-transparent hidden md:block" />
              <div className="space-y-6">
                {etapas.map((etapa, i) => (
                  <motion.div
                    key={etapa.number}
                    initial={{ opacity: 0, x: -20 }}
                    animate={isInView ? { opacity: 1, x: 0 } : {}}
                    transition={{ delay: 0.1 + i * 0.1, duration: 0.5, ease: "easeOut" }}
                    className="flex gap-6 items-start group"
                  >
                    <div className="flex-shrink-0 w-14 h-14 rounded-xl border border-gray-200 bg-white shadow-sm flex items-center justify-center group-hover:border-[#7ABF3C]/40 group-hover:shadow-md transition-all duration-300 relative z-10">
                      <span className="text-sm font-black text-[#7ABF3C]/60 group-hover:text-[#7ABF3C] transition-colors font-mono">
                        {etapa.number}
                      </span>
                    </div>
                    <div className="flex-1 pt-3">
                      <h3 className="text-base font-bold text-[#111111] mb-1.5">{etapa.title}</h3>
                      <p className="text-sm text-[#666666] leading-relaxed">{etapa.description}</p>
                    </div>
                  </motion.div>
                ))}
              </div>
            </div>
          </div>

          {/* App screen placeholder */}
          <motion.div
            initial={{ opacity: 0, x: 20 }}
            animate={isInView ? { opacity: 1, x: 0 } : {}}
            transition={{ duration: 0.6, delay: 0.2 }}
            className="flex justify-center lg:justify-end"
          >
            <div className="w-full max-w-xs aspect-[9/16] rounded-3xl border-2 border-dashed border-gray-300 bg-white shadow-sm flex flex-col items-center justify-center gap-4 px-8 text-center">
              <div className="w-14 h-14 rounded-2xl bg-[#F5F5F5] border border-gray-200 flex items-center justify-center">
                <MonitorSmartphone className="w-7 h-7 text-gray-300" strokeWidth={1.5} />
              </div>
              <div>
                <p className="text-xs font-bold text-[#111111] mb-1">Em breve: visual do aplicativo</p>
                <p className="text-xs text-gray-400 leading-relaxed">
                  As telas reais do aplicativo serão exibidas aqui.
                </p>
              </div>
              <span className="text-[10px] text-gray-300 tracking-widest uppercase">Tela — Dashboard</span>
            </div>
          </motion.div>

        </div>
      </div>
    </section>
  );
}
