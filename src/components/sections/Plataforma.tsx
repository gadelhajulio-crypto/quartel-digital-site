"use client";

import { motion, useInView } from "framer-motion";
import { useRef } from "react";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";

const camadas = [
  {
    sigla: "C1",
    nome: "Interface",
    descricao:
      "O recruta acessa o conteúdo, revisões e seu progresso. O frontend apenas exibe — toda decisão de progresso vem do sistema.",
    tag: "Frontend",
  },
  {
    sigla: "C2",
    nome: "API / Edge Functions",
    descricao:
      "Valida entradas e conecta a interface ao núcleo do sistema. Garante que apenas dados legítimos entram na plataforma.",
    tag: "Backend",
  },
  {
    sigla: "C3",
    nome: "Chat Central",
    descricao:
      "Canal de orientação e suporte educacional. Interpreta dúvidas, orienta o recruta e organiza lógica de forma centralizada.",
    tag: "IA",
  },
  {
    sigla: "C4",
    nome: "Automações",
    descricao:
      "Fluxos automatizados que garantem consistência entre sistemas. Nenhuma progressão exige intervenção manual.",
    tag: "n8n",
  },
  {
    sigla: "C5",
    nome: "Eventos Institucionais",
    descricao:
      "Todo progresso educacional é registrado via eventos auditáveis. Cada revisão feita, cada exercício concluído — registrado.",
    tag: "Núcleo",
  },
  {
    sigla: "C6",
    nome: "Banco de Dados",
    descricao:
      "A fonte única da verdade. Todo progresso, XP, IEA e hierarquia do recruta vivem aqui. É o coração da confiabilidade do sistema.",
    tag: "Supabase",
  },
];

const tagColors: Record<string, string> = {
  Frontend: "border-blue-500/25 text-blue-400 bg-blue-500/5",
  Backend: "border-purple-500/25 text-purple-400 bg-purple-500/5",
  IA: "border-emerald-500/25 text-emerald-400 bg-emerald-500/5",
  n8n: "border-orange-500/25 text-orange-400 bg-orange-500/5",
  Núcleo: "border-[#c9a84c]/25 text-[#c9a84c] bg-[#c9a84c]/5",
  Supabase: "border-green-500/25 text-green-400 bg-green-500/5",
};

export function Plataforma() {
  const ref = useRef(null);
  const isInView = useInView(ref, { once: true, margin: "-100px" });

  return (
    <section id="plataforma" ref={ref} className="py-28 px-6 bg-[#0d0d1a] relative">
      <div className="absolute top-0 left-1/2 -translate-x-1/2 w-px h-28 bg-gradient-to-b from-transparent via-[#c9a84c]/15 to-transparent" />

      <div className="max-w-7xl mx-auto">
        <div className="flex flex-col lg:flex-row gap-12 items-start mb-16">
          <motion.div
            initial={{ opacity: 0, x: -20 }}
            animate={isInView ? { opacity: 1, x: 0 } : {}}
            transition={{ duration: 0.6 }}
            className="flex-1"
          >
            <span className="text-xs font-semibold text-[#c9a84c] tracking-[0.3em] uppercase">
              Confiabilidade
            </span>
            <h2 className="mt-4 text-4xl md:text-5xl font-black text-white leading-tight">
              Um sistema que{" "}
              <span className="gold-gradient">você pode confiar.</span>
            </h2>
          </motion.div>
          <motion.p
            initial={{ opacity: 0, x: 20 }}
            animate={isInView ? { opacity: 1, x: 0 } : {}}
            transition={{ duration: 0.6, delay: 0.15 }}
            className="flex-1 text-gray-400 text-lg leading-relaxed pt-2"
          >
            A arquitetura do Quartel Digital garante que o progresso do recruta
            é real, rastreável e confiável. Cada camada tem responsabilidade
            única — e nenhuma pode ser corrompida por outra.
          </motion.p>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
          {camadas.map((c, i) => (
            <motion.div
              key={c.sigla}
              initial={{ opacity: 0, y: 24 }}
              animate={isInView ? { opacity: 1, y: 0 } : {}}
              transition={{ delay: i * 0.1, duration: 0.55, ease: "easeOut" }}
            >
              <Card className="h-full bg-[#080810] border-[#1a1a2e] hover:border-[#c9a84c]/20 transition-all duration-300 group rounded-xl">
                <CardHeader className="pb-2 flex-row items-center justify-between gap-3">
                  <div className="flex items-center gap-3">
                    <span className="text-xs font-black text-[#c9a84c] font-mono bg-[#c9a84c]/5 border border-[#c9a84c]/20 px-2 py-0.5 rounded">
                      {c.sigla}
                    </span>
                    <h3 className="font-bold text-white text-sm">{c.nome}</h3>
                  </div>
                  <Badge
                    variant="outline"
                    className={`text-[10px] font-medium shrink-0 ${tagColors[c.tag]}`}
                  >
                    {c.tag}
                  </Badge>
                </CardHeader>
                <CardContent>
                  <p className="text-sm text-gray-500 leading-relaxed">{c.descricao}</p>
                </CardContent>
              </Card>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  );
}
