"use client";

import { motion, useInView } from "framer-motion";
import { useRef } from "react";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { CheckCircle2 } from "lucide-react";

const forcas = [
  {
    nome: "Exército",
    sigla: "EB",
    texto:
      "Trilha de estudo voltada à realidade de formação do Exército. Conteúdos, doutrinas e rotinas específicas da formação terrestre.",
    itens: [
      "Conteúdos da formação do Exército",
      "Revisões e prática por módulo",
      "Acompanhamento de desempenho",
      "Instrutor virtual contextualizado",
    ],
    borderHover: "hover:border-[#3d7a4a]/40 hover:shadow-[0_4px_20px_rgba(61,122,74,0.10)]",
    badgeBg: "bg-[#3d7a4a]/8 border-[#3d7a4a]/25 text-[#3d7a4a]",
    checkColor: "text-[#3d7a4a]",
  },
  {
    nome: "Marinha",
    sigla: "MB",
    texto:
      "Trilha de estudo voltada à realidade de formação naval. Conteúdos, doutrinas e rotinas específicas da Marinha do Brasil.",
    itens: [
      "Conteúdos da formação naval",
      "Revisões e prática por módulo",
      "Acompanhamento de desempenho",
      "Instrutor virtual contextualizado",
    ],
    borderHover: "hover:border-[#1e5a8a]/40 hover:shadow-[0_4px_20px_rgba(30,90,138,0.10)]",
    badgeBg: "bg-[#1e5a8a]/8 border-[#1e5a8a]/25 text-[#1e5a8a]",
    checkColor: "text-[#1e5a8a]",
  },
  {
    nome: "Aeronáutica",
    sigla: "FAB",
    texto:
      "Trilha de estudo voltada à realidade de formação aeronáutica. Conteúdos, doutrinas e rotinas específicas da FAB.",
    itens: [
      "Conteúdos da formação aeronáutica",
      "Revisões e prática por módulo",
      "Acompanhamento de desempenho",
      "Instrutor virtual contextualizado",
    ],
    borderHover: "hover:border-[#3a5f9e]/40 hover:shadow-[0_4px_20px_rgba(58,95,158,0.10)]",
    badgeBg: "bg-[#3a5f9e]/8 border-[#3a5f9e]/25 text-[#3a5f9e]",
    checkColor: "text-[#3a5f9e]",
  },
];

export function EscolhaSuaForca() {
  const ref = useRef(null);
  const isInView = useInView(ref, { once: true, margin: "-80px" });

  return (
    <section id="forcas" ref={ref} className="py-28 px-6 bg-[#F5F5F5]">
      <div className="max-w-7xl mx-auto">

        {/* Bloco introdutório */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={isInView ? { opacity: 1, y: 0 } : {}}
          transition={{ duration: 0.6 }}
          className="mb-14"
        >
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-10 items-start">
            <div>
              <span className="text-xs font-semibold text-[#7ABF3C] tracking-[0.3em] uppercase">
                Trilhas por Força
              </span>
              <h2 className="mt-4 text-4xl md:text-5xl font-black text-[#111111] leading-tight">
                Sua preparação depende{" "}
                <span className="gold-gradient">da sua Força.</span>
              </h2>
            </div>
            <div className="lg:pt-14">
              <p className="text-[#444444] text-lg leading-relaxed">
                Exército, Marinha e Aeronáutica possuem formações, conteúdos e
                exigências diferentes. Por isso, o Quartel Digital trabalha com
                trilhas educacionais distintas para cada realidade de formação.
              </p>
              <p className="mt-4 text-[#666666] text-base leading-relaxed">
                Se você já está servindo, selecione a Força em que está. Se
                ainda pretende servir, selecione a Força para a qual deseja se
                preparar.
              </p>
            </div>
          </div>
        </motion.div>

        {/* Divisor com instrução contextual */}
        <motion.div
          initial={{ opacity: 0, y: 12 }}
          animate={isInView ? { opacity: 1, y: 0 } : {}}
          transition={{ duration: 0.6, delay: 0.15 }}
          className="mb-10"
        >
          <div className="border-t border-gray-200 pt-8">
            <p className="text-sm font-semibold text-[#111111] mb-1">
              Para qual Força você está se preparando?
            </p>
            <p className="text-sm text-[#666666]">
              O conteúdo do Quartel Digital é organizado de acordo com a
              realidade da sua formação.{" "}
              <span className="text-[#444444]">
                Se você já está servindo, selecione sua Força atual. Se ainda
                vai servir, escolha a Força que pretende seguir.
              </span>
            </p>
          </div>
        </motion.div>

        {/* Cards das Forças */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          {forcas.map((forca, i) => (
            <motion.div
              key={forca.nome}
              initial={{ opacity: 0, y: 28 }}
              animate={isInView ? { opacity: 1, y: 0 } : {}}
              transition={{ delay: 0.25 + i * 0.12, duration: 0.6, ease: "easeOut" }}
            >
              <Card
                className={`h-full bg-white border-gray-200 shadow-sm ${forca.borderHover} transition-all duration-300 rounded-xl`}
              >
                <CardHeader className="pb-4">
                  <div className="flex items-center gap-3 mb-3">
                    <span
                      className={`text-xs font-black font-mono border px-2 py-0.5 rounded ${forca.badgeBg}`}
                    >
                      {forca.sigla}
                    </span>
                  </div>
                  <h3 className="text-xl font-black text-[#111111]">{forca.nome}</h3>
                  <p className="text-sm text-[#666666] leading-relaxed mt-1">
                    {forca.texto}
                  </p>
                </CardHeader>
                <CardContent className="space-y-2.5 pt-0">
                  {forca.itens.map((item) => (
                    <div key={item} className="flex items-start gap-2.5">
                      <CheckCircle2
                        className={`w-4 h-4 shrink-0 mt-0.5 ${forca.checkColor}`}
                        strokeWidth={1.5}
                      />
                      <span className="text-sm text-[#444444] leading-snug">{item}</span>
                    </div>
                  ))}
                </CardContent>
              </Card>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  );
}
