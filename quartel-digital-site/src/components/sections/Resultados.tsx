"use client";

import { motion, useInView } from "framer-motion";
import { useRef } from "react";
import { Card, CardContent } from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";
import { ArrowUpRight } from "lucide-react";

const resultados = [
  {
    titulo: "Melhor preparo para avaliações",
    descricao:
      "Revisão estruturada e prática contínua ajudam a fixar o conteúdo e aumentam as chances de melhor desempenho nas avaliações da formação.",
  },
  {
    titulo: "Mais constância nos estudos",
    descricao:
      "O sistema cria uma rotina de estudo progressiva e rastreável, desenvolvendo consistência que vai além do esforço isolado.",
  },
  {
    titulo: "Acompanhamento claro de evolução",
    descricao:
      "O recruta sabe exatamente quanto estudou, o que revisou e como está progredindo dentro da sua trilha de formação.",
  },
  {
    titulo: "Mais competitividade na classificação",
    descricao:
      "Uma preparação mais consistente contribui para uma classificação mais competitiva ao longo do curso de formação.",
  },
  {
    titulo: "Maior consciência de desempenho",
    descricao:
      "Dados de progresso e evolução permitem que o recruta identifique pontos fracos e direcione o estudo com mais precisão.",
  },
];

const aviso =
  "O Quartel Digital não garante aprovação, engajamento ou vagas nas Forças Armadas. A plataforma aumenta as chances de melhor preparação e desempenho — o resultado depende do esforço e das condições individuais de cada recruta.";

export function Resultados() {
  const ref = useRef(null);
  const isInView = useInView(ref, { once: true, margin: "-80px" });

  return (
    <section id="resultados" ref={ref} className="py-24 px-6 bg-[#F5F5F5]">
      <div className="max-w-7xl mx-auto">
        {/* Header */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={isInView ? { opacity: 1, y: 0 } : {}}
          transition={{ duration: 0.6 }}
          className="mb-14"
        >
          <span className="text-xs font-semibold text-[#7ABF3C] tracking-[0.3em] uppercase">
            Impacto Real
          </span>
          <h2 className="mt-4 text-4xl md:text-5xl font-black text-[#111111] leading-tight max-w-2xl">
            Estudo vira desempenho.
            <br />
            Desempenho vira posição.
          </h2>
          <p className="mt-4 text-[#555555] text-base leading-relaxed max-w-xl">
            O objetivo do Quartel Digital é ajudar o recruta a construir
            consistência para melhorar notas, disputar melhor classificação e
            aumentar suas oportunidades dentro da formação.
          </p>
        </motion.div>

        {/* Resultados */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5 mb-10">
          {resultados.map((item, i) => (
            <motion.div
              key={item.titulo}
              initial={{ opacity: 0, y: 22 }}
              animate={isInView ? { opacity: 1, y: 0 } : {}}
              transition={{ delay: i * 0.09, duration: 0.55 }}
            >
              <Card className="h-full bg-white border-gray-200 shadow-sm hover:shadow-md hover:border-[#7ABF3C]/30 transition-all duration-300 group rounded-xl">
                <CardContent className="pt-6 space-y-3">
                  <div className="flex items-start justify-between gap-2">
                    <h3 className="font-bold text-[#111111] text-sm leading-snug">{item.titulo}</h3>
                    <ArrowUpRight
                      className="w-4 h-4 text-gray-300 group-hover:text-[#7ABF3C] shrink-0 transition-colors mt-0.5"
                      strokeWidth={1.5}
                    />
                  </div>
                  <p className="text-xs text-[#666666] leading-relaxed">{item.descricao}</p>
                </CardContent>
              </Card>
            </motion.div>
          ))}
        </div>

        {/* Aviso legal */}
        <motion.div
          initial={{ opacity: 0 }}
          animate={isInView ? { opacity: 1 } : {}}
          transition={{ delay: 0.5, duration: 0.6 }}
          className="max-w-3xl"
        >
          <Separator className="bg-gray-200 mb-6" />
          <p className="text-xs text-[#888888] leading-relaxed">{aviso}</p>
        </motion.div>
      </div>
    </section>
  );
}
