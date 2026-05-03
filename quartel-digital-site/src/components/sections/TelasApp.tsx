"use client";

import { motion, useInView } from "framer-motion";
import { useRef } from "react";
import { MonitorSmartphone } from "lucide-react";

const telas = [
  { label: "Dashboard", descricao: "Tela inicial com visão geral do progresso" },
  { label: "Aulas", descricao: "Tela de conteúdos e trilha de estudo" },
  { label: "Exercícios", descricao: "Tela de testes e atividades de fixação" },
  { label: "Progresso", descricao: "Tela de evolução e histórico de estudo" },
  { label: "Instrutor Virtual", descricao: "Tela do chat com o instrutor" },
];

export function TelasApp() {
  const ref = useRef(null);
  const isInView = useInView(ref, { once: true, margin: "-80px" });

  return (
    <section ref={ref} className="py-24 px-6 bg-[#F5F5F5]">
      <div className="max-w-7xl mx-auto">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={isInView ? { opacity: 1, y: 0 } : {}}
          transition={{ duration: 0.6 }}
          className="text-center mb-14"
        >
          <span className="text-xs font-semibold text-[#7ABF3C] tracking-[0.3em] uppercase">
            O Aplicativo
          </span>
          <h2 className="mt-4 text-4xl md:text-5xl font-black text-[#111111] leading-tight">
            Visual em breve
          </h2>
          <p className="mt-4 text-[#555555] text-lg max-w-xl mx-auto">
            As telas reais do Quartel Digital serão exibidas aqui em breve.
          </p>
        </motion.div>

        <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-5 gap-4">
          {telas.map((tela, i) => (
            <motion.div
              key={tela.label}
              initial={{ opacity: 0, y: 24 }}
              animate={isInView ? { opacity: 1, y: 0 } : {}}
              transition={{ delay: i * 0.08, duration: 0.5, ease: "easeOut" }}
            >
              <div className="aspect-[9/16] rounded-2xl border-2 border-dashed border-gray-300 bg-white flex flex-col items-center justify-center gap-3 px-4 text-center shadow-sm">
                <div className="w-10 h-10 rounded-xl bg-[#F5F5F5] border border-gray-200 flex items-center justify-center">
                  <MonitorSmartphone className="w-5 h-5 text-gray-300" strokeWidth={1.5} />
                </div>
                <div>
                  <p className="text-[11px] font-bold text-[#111111] mb-0.5">
                    Em breve: visual do aplicativo
                  </p>
                  <p className="text-[10px] text-gray-400 leading-relaxed">
                    As telas reais do aplicativo serão exibidas aqui.
                  </p>
                </div>
                <span className="text-[9px] text-gray-300 tracking-widest uppercase border border-gray-200 px-2 py-0.5 rounded-full">
                  {tela.label}
                </span>
              </div>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  );
}
