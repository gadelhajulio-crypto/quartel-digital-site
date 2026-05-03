"use client";

import { motion, useInView } from "framer-motion";
import { useRef } from "react";
import { Card, CardContent } from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";
import { AlertCircle } from "lucide-react";

const dores = [
  {
    titulo: "Pouco tempo para revisar",
    descricao:
      "A rotina do quartel é intensa. O recruta não tem horas livres para organizar estudo por conta própria.",
  },
  {
    titulo: "Conteúdo acumulado",
    descricao:
      "Disciplinas e matérias se acumulam rapidamente. Sem revisão estruturada, o esquecimento é inevitável.",
  },
  {
    titulo: "Alta cobrança por desempenho",
    descricao:
      "Avaliações acontecem dentro da formação. Quem não revisa chega menos preparado e performa abaixo do potencial.",
  },
  {
    titulo: "Classificação competitiva",
    descricao:
      "A colocação no curso influencia oportunidades futuras: funções, engajamento, progressão. Cada ponto importa.",
  },
];

export function Problema() {
  const ref = useRef(null);
  const isInView = useInView(ref, { once: true, margin: "-80px" });

  return (
    <section id="problema" ref={ref} className="py-24 px-6 bg-[#F5F5F5]">
      <div className="max-w-7xl mx-auto">
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-14 items-center">
          {/* Left */}
          <motion.div
            initial={{ opacity: 0, x: -24 }}
            animate={isInView ? { opacity: 1, x: 0 } : {}}
            transition={{ duration: 0.65 }}
          >
            <div className="flex items-center gap-3 mb-6">
              <div className="w-8 h-8 rounded-lg border border-red-400/30 bg-red-50 flex items-center justify-center text-red-500">
                <AlertCircle className="w-4 h-4" strokeWidth={1.5} />
              </div>
              <span className="text-xs font-semibold text-red-500 tracking-[0.25em] uppercase">
                O Problema
              </span>
            </div>

            <h2 className="text-4xl md:text-5xl font-black text-[#111111] leading-tight">
              O desafio do recruta
              <br />
              <span className="text-[#444444]">não termina no quartel.</span>
            </h2>

            <Separator className="bg-gray-200 my-8 max-w-sm" />

            <p className="text-[#444444] text-lg leading-relaxed">
              O recruta tem pouco tempo, muita cobrança e precisa absorver
              conteúdos importantes em ritmo acelerado. Quem não revisa fora,
              chega menos preparado dentro.
            </p>

            <p className="mt-4 text-[#666666] text-base leading-relaxed">
              Não é falta de capacidade. É falta de um sistema que sustente a
              evolução fora do ambiente formal.
            </p>
          </motion.div>

          {/* Right: pain points */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            {dores.map((dor, i) => (
              <motion.div
                key={dor.titulo}
                initial={{ opacity: 0, y: 20 }}
                animate={isInView ? { opacity: 1, y: 0 } : {}}
                transition={{ delay: 0.15 + i * 0.1, duration: 0.5 }}
              >
                <Card className="h-full bg-white border-gray-200 shadow-sm hover:shadow-md hover:border-red-200 transition-all duration-300 rounded-xl">
                  <CardContent className="pt-5 space-y-2">
                    <div className="w-1.5 h-1.5 rounded-full bg-red-400" />
                    <h3 className="font-bold text-[#111111] text-sm">{dor.titulo}</h3>
                    <p className="text-xs text-[#666666] leading-relaxed">{dor.descricao}</p>
                  </CardContent>
                </Card>
              </motion.div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
