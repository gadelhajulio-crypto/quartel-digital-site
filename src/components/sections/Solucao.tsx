"use client";

import { motion, useInView } from "framer-motion";
import { useRef } from "react";
import { Card, CardContent } from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";
import { Badge } from "@/components/ui/badge";
import { BookOpen, RotateCcw, TrendingUp, Target } from "lucide-react";

const pilares = [
  {
    icon: BookOpen,
    titulo: "Revisões guiadas",
    descricao:
      "Conteúdo organizado em módulos progressivos. O recruta sabe exatamente o que revisar e em que ordem.",
  },
  {
    icon: RotateCcw,
    titulo: "Prática contínua",
    descricao:
      "Exercícios e questões para fixar o conteúdo. Repetição estruturada que transforma estudo em retenção real.",
  },
  {
    icon: TrendingUp,
    titulo: "Acompanhamento por progresso",
    descricao:
      "XP e IEA medem consistência de estudo, não entretenimento. O recruta vê sua evolução real ao longo do tempo.",
  },
  {
    icon: Target,
    titulo: "Foco em notas e classificação",
    descricao:
      "Tudo na plataforma é orientado para um resultado concreto: melhor desempenho nas avaliações da formação.",
  },
];

export function Solucao() {
  const ref = useRef(null);
  const isInView = useInView(ref, { once: true, margin: "-80px" });

  return (
    <section ref={ref} className="py-24 px-6 bg-[#F5F5F5]">
      <div className="max-w-7xl mx-auto">
        {/* Header */}
        <div className="flex flex-col lg:flex-row gap-12 items-start mb-14">
          <motion.div
            initial={{ opacity: 0, x: -20 }}
            animate={isInView ? { opacity: 1, x: 0 } : {}}
            transition={{ duration: 0.65 }}
            className="flex-1"
          >
            <div className="flex items-center gap-3 mb-6">
              <Badge
                variant="outline"
                className="border-[#7ABF3C]/30 text-[#7ABF3C] bg-[#7ABF3C]/5 text-xs tracking-widest uppercase"
              >
                A Solução
              </Badge>
            </div>
            <h2 className="text-4xl md:text-5xl font-black text-[#111111] leading-tight">
              Reforço educacional
              <br />
              <span className="gold-gradient">estruturado para o recruta.</span>
            </h2>
            <Separator className="bg-gray-200 my-8 max-w-xs" />
          </motion.div>

          <motion.p
            initial={{ opacity: 0, x: 20 }}
            animate={isInView ? { opacity: 1, x: 0 } : {}}
            transition={{ duration: 0.65, delay: 0.15 }}
            className="flex-1 text-[#555555] text-lg leading-relaxed pt-2 lg:pt-16"
          >
            O Quartel Digital organiza revisões, prática e acompanhamento de
            evolução para transformar estudo fora do quartel em desempenho
            melhor dentro da formação.
          </motion.p>
        </div>

        {/* Pilares */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-5">
          {pilares.map((pilar, i) => {
            const Icon = pilar.icon;
            return (
              <motion.div
                key={pilar.titulo}
                initial={{ opacity: 0, y: 24 }}
                animate={isInView ? { opacity: 1, y: 0 } : {}}
                transition={{ delay: i * 0.1, duration: 0.55, ease: "easeOut" }}
              >
                <Card className="h-full bg-white border-gray-200 shadow-sm hover:shadow-md hover:border-[#7ABF3C]/30 transition-all duration-300 group rounded-xl">
                  <CardContent className="pt-6 space-y-4">
                    <div className="w-10 h-10 rounded-xl border border-[#7ABF3C]/20 bg-[#7ABF3C]/5 flex items-center justify-center text-[#7ABF3C]/50 group-hover:text-[#7ABF3C] group-hover:border-[#7ABF3C]/40 transition-all duration-300">
                      <Icon className="w-5 h-5" strokeWidth={1.5} />
                    </div>
                    <h3 className="font-bold text-[#111111] text-sm">{pilar.titulo}</h3>
                    <p className="text-xs text-[#666666] leading-relaxed">{pilar.descricao}</p>
                  </CardContent>
                </Card>
              </motion.div>
            );
          })}
        </div>
      </div>
    </section>
  );
}
