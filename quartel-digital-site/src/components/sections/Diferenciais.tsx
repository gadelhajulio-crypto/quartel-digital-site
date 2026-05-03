"use client";

import { motion, useInView } from "framer-motion";
import { useRef } from "react";
import { Card, CardContent } from "@/components/ui/card";
import {
  BookOpenCheck,
  ScanLine,
  Users,
  Layers,
  RotateCcw,
  MessageSquare,
} from "lucide-react";

const diferenciais = [
  {
    titulo: "Reforço fora do quartel",
    descricao:
      "A plataforma funciona como extensão do treinamento. Fora do quartel, o recruta continua revisando, praticando e fixando conteúdo.",
    icon: BookOpenCheck,
  },
  {
    titulo: "Progresso rastreável",
    descricao:
      "Toda atividade de estudo é registrada e visível. O recruta sabe exatamente quanto estudou, o que revisou e como evoluiu.",
    icon: ScanLine,
  },
  {
    titulo: "Personalizado por Força",
    descricao:
      "Exército, Marinha ou Aeronáutica: o conteúdo, a linguagem e o tema visual se adaptam à Força escolhida pelo recruta.",
    icon: Layers,
  },
  {
    titulo: "Aulas e revisões organizadas",
    descricao:
      "Conteúdo estruturado em trilhas e módulos progressivos. O recruta sabe o que estudar e em que ordem, sem perder tempo.",
    icon: RotateCcw,
  },
  {
    titulo: "Preparação individual",
    descricao:
      "Cada recruta evolui no seu ritmo, mas com a mesma estrutura e os mesmos critérios. Sem favoritismo, sem atalhos.",
    icon: Users,
  },
  {
    titulo: "Instrutor virtual integrado",
    descricao:
      "Suporte para dúvidas dentro do próprio aplicativo, com orientações adaptadas à Força e ao conteúdo em estudo.",
    icon: MessageSquare,
  },
];

export function Diferenciais() {
  const ref = useRef(null);
  const isInView = useInView(ref, { once: true, margin: "-80px" });

  return (
    <section id="diferenciais" ref={ref} className="py-28 px-6 bg-[#0B0B0B]">
      <div className="max-w-7xl mx-auto">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={isInView ? { opacity: 1, y: 0 } : {}}
          transition={{ duration: 0.6 }}
          className="text-center mb-16"
        >
          <span className="text-xs font-semibold text-[#7ABF3C] tracking-[0.3em] uppercase">
            Por Que Escolher
          </span>
          <h2 className="mt-4 text-4xl md:text-5xl font-black text-white leading-tight">
            Diferenciais
          </h2>
          <p className="mt-4 text-gray-400 text-lg max-w-xl mx-auto">
            O que torna o Quartel Digital diferente de uma plataforma genérica
            de cursos ou gamificação vazia.
          </p>
        </motion.div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
          {diferenciais.map((item, i) => {
            const Icon = item.icon;
            return (
              <motion.div
                key={item.titulo}
                initial={{ opacity: 0, y: 24 }}
                animate={isInView ? { opacity: 1, y: 0 } : {}}
                transition={{ delay: i * 0.1, duration: 0.6, ease: "easeOut" }}
              >
                <Card className="h-full bg-[#121212] border-[#222222] hover:border-[#7ABF3C]/25 transition-all duration-300 group rounded-xl">
                  <CardContent className="pt-6 flex gap-5">
                    <div className="flex-shrink-0 w-10 h-10 rounded-xl border border-[#222222] bg-[#0B0B0B] flex items-center justify-center text-[#7ABF3C]/40 group-hover:text-[#7ABF3C] group-hover:border-[#7ABF3C]/30 transition-all duration-300">
                      <Icon className="w-5 h-5" strokeWidth={1.5} />
                    </div>
                    <div>
                      <h3 className="font-bold text-white text-sm mb-2">{item.titulo}</h3>
                      <p className="text-sm text-gray-500 leading-relaxed">{item.descricao}</p>
                    </div>
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
