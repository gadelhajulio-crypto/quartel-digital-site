"use client";

import { motion, useInView } from "framer-motion";
import { useRef } from "react";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";
import { Info } from "lucide-react";

export function AvisoIndependencia() {
  const ref = useRef(null);
  const isInView = useInView(ref, { once: true, margin: "-60px" });

  return (
    <section ref={ref} className="py-16 px-6 bg-[#0B0B0B]">
      <div className="max-w-4xl mx-auto">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={isInView ? { opacity: 1, y: 0 } : {}}
          transition={{ duration: 0.6 }}
        >
          <Card className="bg-[#121212] border-[#7ABF3C]/20 rounded-2xl overflow-hidden">
            <CardContent className="pt-8 pb-8">
              <div className="flex gap-5 items-start">
                <div className="flex-shrink-0 w-10 h-10 rounded-lg border border-[#7ABF3C]/30 bg-[#7ABF3C]/5 flex items-center justify-center text-[#7ABF3C]">
                  <Info className="w-5 h-5" strokeWidth={1.5} />
                </div>

                <div className="flex-1 space-y-4">
                  <div className="flex items-center gap-3 flex-wrap">
                    <h3 className="font-bold text-[#7ABF3C] text-sm uppercase tracking-widest">
                      Aviso de Independência
                    </h3>
                    <Badge
                      variant="outline"
                      className="border-[#7ABF3C]/25 text-[#7ABF3C]/70 text-[10px]"
                    >
                      Declaração Institucional
                    </Badge>
                  </div>

                  <Separator className="bg-[#7ABF3C]/10" />

                  <p className="text-gray-300 text-base leading-relaxed">
                    O Quartel Digital é uma plataforma educacional independente,
                    sem vínculo oficial com as Forças Armadas, Marinha do Brasil,
                    Exército Brasileiro, Aeronáutica, Polícias Militares ou
                    qualquer órgão governamental.
                  </p>
                  <p className="text-gray-400 text-sm leading-relaxed">
                    Toda a estrutura hierárquica, terminologia e dinâmica de
                    progressão são de natureza simbólica e digital, criadas
                    exclusivamente para o ambiente da plataforma. Não utilizamos
                    brasões, insígnias ou símbolos oficiais de qualquer
                    instituição. Eventuais referências a carreiras têm propósito
                    exclusivamente informativo e educacional.
                  </p>
                  <p className="text-xs text-gray-600">
                    Para informações oficiais sobre processos seletivos,
                    consulte sempre os canais oficiais das instituições
                    responsáveis.
                  </p>
                </div>
              </div>
            </CardContent>
          </Card>
        </motion.div>
      </div>
    </section>
  );
}
