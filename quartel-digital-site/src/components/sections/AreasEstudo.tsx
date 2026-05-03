"use client";

import { motion, useInView } from "framer-motion";
import { useRef } from "react";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";

const niveis = [
  {
    nivel: 1,
    titulo: "Recruta",
    descricao:
      "Ponto de entrada. Todo recruta começa aqui, independentemente do seu nível de conhecimento prévio. A plataforma adapta o reforço ao seu ponto atual.",
    cor: "#6b7280",
    corBg: "rgba(107,114,128,0.07)",
    corBorder: "rgba(107,114,128,0.18)",
    status: "Entrada",
  },
  {
    nivel: 2,
    titulo: "Operacional",
    descricao:
      "Primeiro avanço. Indica consistência de estudos e engajamento real com as revisões propostas pela plataforma.",
    cor: "#60a5fa",
    corBg: "rgba(96,165,250,0.06)",
    corBorder: "rgba(96,165,250,0.16)",
    status: "Progressão",
  },
  {
    nivel: 3,
    titulo: "Combatente",
    descricao:
      "Nível intermediário. O histórico de estudo e prática confirma evolução educacional real e sustentada.",
    cor: "#34d399",
    corBg: "rgba(52,211,153,0.06)",
    corBorder: "rgba(52,211,153,0.16)",
    status: "Intermediário",
  },
  {
    nivel: 4,
    titulo: "Vanguarda",
    descricao:
      "Alto nível de preparação educacional. Exige constância de longo prazo nas revisões e prática contínua.",
    cor: "#a78bfa",
    corBg: "rgba(167,139,250,0.06)",
    corBorder: "rgba(167,139,250,0.16)",
    status: "Alto nível",
  },
  {
    nivel: 5,
    titulo: "Excelência",
    descricao:
      "Representa o topo da curva de preparação dentro da plataforma. Poucos recrutas chegam aqui — exige estudo consistente e disciplina real.",
    cor: "#fb923c",
    corBg: "rgba(251,146,60,0.06)",
    corBorder: "rgba(251,146,60,0.16)",
    status: "Avançado",
  },
  {
    nivel: 6,
    titulo: "Elite",
    descricao:
      "Posição única no sistema. Representa o maior nível de consistência e preparação educacional da plataforma. Existe apenas uma vaga globalmente.",
    cor: "#c9a84c",
    corBg: "rgba(201,168,76,0.08)",
    corBorder: "rgba(201,168,76,0.32)",
    status: "Único",
    destaque: true,
  },
];

export function AreasEstudo() {
  const ref = useRef(null);
  const isInView = useInView(ref, { once: true, margin: "-80px" });

  return (
    <section id="areas" ref={ref} className="py-28 px-6">
      <div className="max-w-7xl mx-auto">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={isInView ? { opacity: 1, y: 0 } : {}}
          transition={{ duration: 0.6 }}
          className="text-center mb-14"
        >
          <span className="text-xs font-semibold text-[#c9a84c] tracking-[0.3em] uppercase">
            Progressão
          </span>
          <h2 className="mt-4 text-4xl md:text-5xl font-black text-white leading-tight">
            Hierarquia Educacional
          </h2>
          <p className="mt-4 text-gray-400 text-lg max-w-2xl mx-auto">
            A hierarquia representa evolução educacional e consistência de
            preparação dentro da plataforma. Seis níveis fixos — todos
            conquistados por estudo e prática, não por tempo ou privilégio.
          </p>
        </motion.div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
          {niveis.map((n, i) => (
            <motion.div
              key={n.nivel}
              initial={{ opacity: 0, scale: 0.97 }}
              animate={isInView ? { opacity: 1, scale: 1 } : {}}
              transition={{ delay: i * 0.09, duration: 0.5 }}
            >
              <Card
                className="h-full rounded-xl transition-all duration-300 group"
                style={{
                  backgroundColor: n.destaque ? n.corBg : "#0d0d1a",
                  borderColor: n.corBorder,
                  borderWidth: "1px",
                }}
              >
                <CardContent className="pt-6 space-y-4">
                  <div className="flex items-start justify-between">
                    <div className="flex items-center gap-3">
                      <span
                        className="text-3xl font-black leading-none font-mono"
                        style={{ color: n.cor + "28" }}
                      >
                        {String(n.nivel).padStart(2, "0")}
                      </span>
                      <h3
                        className="text-base font-bold"
                        style={{ color: n.destaque ? n.cor : "white" }}
                      >
                        {n.titulo}
                      </h3>
                    </div>
                    <Badge
                      variant="outline"
                      className="text-[10px] font-semibold shrink-0"
                      style={{
                        borderColor: n.corBorder,
                        color: n.cor,
                        backgroundColor: n.corBg,
                      }}
                    >
                      {n.status}
                    </Badge>
                  </div>
                  <Separator style={{ backgroundColor: n.corBorder }} />
                  <p className="text-sm text-gray-500 leading-relaxed">{n.descricao}</p>
                  {n.destaque && (
                    <p className="text-xs font-semibold text-[#c9a84c]/80 tracking-wide">
                      Posição única e irrepetível na plataforma.
                    </p>
                  )}
                </CardContent>
              </Card>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  );
}
