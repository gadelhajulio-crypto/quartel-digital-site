"use client";

import { motion, useInView } from "framer-motion";
import { useRef } from "react";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from "@/components/ui/accordion";
import { Lock, Fingerprint, FileCheck2, ServerCrash } from "lucide-react";

const pilares = [
  {
    titulo: "Fonte da Verdade Única",
    descricao: "O banco é o árbitro final de qualquer estado institucional. Nenhuma camada superior pode declarar um recruta em nível diferente do que o banco registra.",
    icon: Lock,
  },
  {
    titulo: "Identidade Verificada",
    descricao: "Cada recruta possui um auth_id único e um thread_id de Chat vinculados ao seu registro. Não existe recruta anônimo no sistema.",
    icon: Fingerprint,
  },
  {
    titulo: "Eventos Auditáveis",
    descricao: "Todo ganho de XP, toda mudança de status e todo avanço hierárquico geram um registro formal. O histórico é completo e imutável.",
    icon: FileCheck2,
  },
  {
    titulo: "Resiliência a Falhas",
    descricao: "A idempotência dos eventos garante que reprocessamentos não corrompem o estado. O sistema se recupera sem gerar duplicidade ou inconsistência.",
    icon: ServerCrash,
  },
];

const faq = [
  {
    pergunta: "O que é o IEA?",
    resposta:
      "O IEA (Índice de Evolução Atual) é um valor de 0 a 100 calculado no backend com base nos eventos registrados do recruta. Ele determina elegibilidade para progressão hierárquica, posição no ranking e acesso a funcionalidades restritas.",
  },
  {
    pergunta: "Como funciona o sistema de XP?",
    resposta:
      "XP não existe implicitamente. Cada ponto de XP é gerado por um evento institucional registrado e validado. Não há XP manual, não há XP de bônus subjetivo. O cálculo é determinístico e rastreável.",
  },
  {
    pergunta: "O que impede progressão artificial?",
    resposta:
      "A arquitetura. Nenhuma lógica de mérito reside no frontend. Toda progressão ocorre via eventos idempotentes registrados no banco, validados pelo backend. Manipular o frontend não altera o estado real do recruta.",
  },
  {
    pergunta: "O nível Elite pode ser ocupado por mais de uma pessoa?",
    resposta:
      "Não. A posição Elite é única no sistema global. Existe apenas uma. O sistema impede que dois recrutas ocupem simultaneamente esse nível.",
  },
];

export function SegurancaInstitucional() {
  const ref = useRef(null);
  const isInView = useInView(ref, { once: true, margin: "-80px" });

  return (
    <section id="seguranca" ref={ref} className="py-28 px-6">
      <div className="max-w-7xl mx-auto">
        {/* Header */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={isInView ? { opacity: 1, y: 0 } : {}}
          transition={{ duration: 0.6 }}
          className="text-center mb-16"
        >
          <span className="text-xs font-semibold text-[#c9a84c] tracking-[0.3em] uppercase">
            Integridade
          </span>
          <h2 className="mt-4 text-4xl md:text-5xl font-black text-white leading-tight">
            Segurança Institucional
          </h2>
          <p className="mt-4 text-gray-400 text-lg max-w-xl mx-auto">
            Um sistema meritocrático só é justo se for impossível corrompê-lo.
            Aqui estão os pilares que garantem isso.
          </p>
        </motion.div>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-10 items-start">
          {/* Pilares */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-5">
            {pilares.map((pilar, i) => {
              const Icon = pilar.icon;
              return (
                <motion.div
                  key={pilar.titulo}
                  initial={{ opacity: 0, y: 20 }}
                  animate={isInView ? { opacity: 1, y: 0 } : {}}
                  transition={{ delay: 0.1 + i * 0.1, duration: 0.5 }}
                >
                  <Card className="h-full bg-[#0d0d1a] border-[#1a1a2e] hover:border-[#c9a84c]/20 transition-all duration-300 group rounded-xl">
                    <CardContent className="pt-5 space-y-3">
                      <div className="w-9 h-9 rounded-lg border border-[#c9a84c]/15 bg-[#c9a84c]/5 flex items-center justify-center text-[#c9a84c]/60 group-hover:text-[#c9a84c] group-hover:border-[#c9a84c]/40 transition-all duration-300">
                        <Icon className="w-4 h-4" strokeWidth={1.5} />
                      </div>
                      <h3 className="font-bold text-white text-sm">{pilar.titulo}</h3>
                      <p className="text-xs text-gray-500 leading-relaxed">{pilar.descricao}</p>
                    </CardContent>
                  </Card>
                </motion.div>
              );
            })}

            {/* Tags */}
            <motion.div
              initial={{ opacity: 0 }}
              animate={isInView ? { opacity: 1 } : {}}
              transition={{ delay: 0.5, duration: 0.5 }}
              className="sm:col-span-2 flex flex-wrap gap-2"
            >
              {["Idempotência", "LGPD", "Auth por UUID", "Zero confiança no frontend", "Eventos imutáveis"].map(
                (tag) => (
                  <Badge
                    key={tag}
                    variant="outline"
                    className="border-[#1a1a2e] text-gray-500 text-[10px] font-medium"
                  >
                    {tag}
                  </Badge>
                )
              )}
            </motion.div>
          </div>

          {/* FAQ Accordion */}
          <motion.div
            initial={{ opacity: 0, x: 20 }}
            animate={isInView ? { opacity: 1, x: 0 } : {}}
            transition={{ delay: 0.2, duration: 0.6 }}
          >
            <p className="text-xs font-semibold text-gray-500 tracking-widest uppercase mb-5">
              Perguntas frequentes
            </p>
            <Accordion className="space-y-2">
              {faq.map((item, i) => (
                <AccordionItem
                  key={i}
                  value={i}
                  className="border border-[#1a1a2e] rounded-xl px-4 bg-[#0d0d1a]"
                >
                  <AccordionTrigger className="text-sm font-semibold text-gray-300 hover:text-white hover:no-underline py-4">
                    {item.pergunta}
                  </AccordionTrigger>
                  <AccordionContent className="text-sm text-gray-500 leading-relaxed pb-4">
                    {item.resposta}
                  </AccordionContent>
                </AccordionItem>
              ))}
            </Accordion>
          </motion.div>
        </div>
      </div>
    </section>
  );
}
