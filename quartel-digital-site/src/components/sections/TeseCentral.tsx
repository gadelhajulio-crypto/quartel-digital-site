"use client";

import { motion, useInView } from "framer-motion";
import { useRef } from "react";

export function TeseCentral() {
  const ref = useRef(null);
  const isInView = useInView(ref, { once: true, margin: "-80px" });

  return (
    <section ref={ref} className="py-24 px-6 bg-white">
      <div className="max-w-4xl mx-auto text-center">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={isInView ? { opacity: 1, y: 0 } : {}}
          transition={{ duration: 0.65 }}
        >
          <span className="text-xs font-semibold text-[#7ABF3C] tracking-[0.3em] uppercase">
            A Questão Real
          </span>
          <h2 className="mt-6 text-4xl md:text-5xl font-black text-[#111111] leading-tight">
            O problema não é falta de capacidade.
          </h2>
          <p className="mt-6 text-[#444444] text-xl leading-relaxed max-w-2xl mx-auto">
            O recruta não falha porque não consegue aprender. Ele falha porque
            tenta performar dentro de uma rotina exigente sem um sistema claro
            de estudo, revisão e acompanhamento.
          </p>
        </motion.div>

        <motion.div
          initial={{ opacity: 0, y: 16 }}
          animate={isInView ? { opacity: 1, y: 0 } : {}}
          transition={{ duration: 0.65, delay: 0.2 }}
          className="mt-10 inline-block bg-[#F5F5F5] border border-gray-200 rounded-2xl px-8 py-6 max-w-2xl"
        >
          <p className="text-[#111111] text-lg font-semibold leading-relaxed">
            PDFs, vídeos e resumos ajudam.
          </p>
          <p className="text-[#555555] text-base leading-relaxed mt-2">
            Mas conteúdo solto não forma desempenho consistente.
          </p>
        </motion.div>
      </div>
    </section>
  );
}
