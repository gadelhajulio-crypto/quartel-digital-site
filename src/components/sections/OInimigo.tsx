"use client";

import { motion, useInView } from "framer-motion";
import { useRef } from "react";
import { Card, CardContent } from "@/components/ui/card";
import { XCircle } from "lucide-react";

const problemas = [
  "Estudar quando dá",
  "Revisar só quando lembra",
  "Não acompanhar evolução",
  "Chegar na avaliação sem estratégia",
  "Depender de esforço sem método",
];

export function OInimigo() {
  const ref = useRef(null);
  const isInView = useInView(ref, { once: true, margin: "-80px" });

  return (
    <section ref={ref} className="py-24 px-6 bg-[#F5F5F5]">
      <div className="max-w-7xl mx-auto">
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-14 items-center">
          {/* Left */}
          <motion.div
            initial={{ opacity: 0, x: -24 }}
            animate={isInView ? { opacity: 1, x: 0 } : {}}
            transition={{ duration: 0.65 }}
          >
            <span className="text-xs font-semibold text-red-500 tracking-[0.25em] uppercase">
              O Inimigo
            </span>
            <h2 className="mt-4 text-4xl md:text-5xl font-black text-[#111111] leading-tight">
              O inimigo é o estudo desorganizado.
            </h2>
            <p className="mt-6 text-[#444444] text-lg leading-relaxed">
              Não é falta de vontade. É a ausência de estrutura que impede o
              recruta de transformar esforço em resultado.
            </p>
            <div className="mt-8 p-5 bg-white border border-red-100 rounded-xl shadow-sm">
              <p className="text-[#111111] font-bold text-base">
                Muito esforço sem sistema gera pouca progressão.
              </p>
            </div>
          </motion.div>

          {/* Right: cards */}
          <div className="flex flex-col gap-3">
            {problemas.map((item, i) => (
              <motion.div
                key={item}
                initial={{ opacity: 0, x: 20 }}
                animate={isInView ? { opacity: 1, x: 0 } : {}}
                transition={{ delay: 0.1 + i * 0.08, duration: 0.5 }}
              >
                <Card className="bg-white border-gray-200 shadow-sm rounded-xl">
                  <CardContent className="py-4 flex items-center gap-4">
                    <XCircle className="w-5 h-5 text-red-400 shrink-0" strokeWidth={1.5} />
                    <span className="text-sm font-medium text-[#333333]">{item}</span>
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
