"use client";

import { motion, useInView } from "framer-motion";
import { useRef } from "react";
import { MessageSquare, HelpCircle, BookOpen, Navigation } from "lucide-react";

const bullets = [
  {
    icon: HelpCircle,
    titulo: "Explicações sob demanda",
    texto: "Quando você tiver dúvida sobre um conteúdo, o instrutor explica de forma direta e objetiva.",
  },
  {
    icon: BookOpen,
    titulo: "Apoio durante revisões",
    texto: "Durante o estudo, o instrutor orienta pontos que precisam de mais atenção e reforço.",
  },
  {
    icon: Navigation,
    titulo: "Direcionamento de estudo",
    texto: "Ajuda a identificar o que estudar a seguir para manter continuidade e consistência.",
  },
  {
    icon: MessageSquare,
    titulo: "Suporte contínuo no app",
    texto: "Disponível dentro do aplicativo durante toda a sua jornada de formação.",
  },
];

export function InstrutorVirtual() {
  const ref = useRef(null);
  const isInView = useInView(ref, { once: true, margin: "-80px" });

  return (
    <section id="instrutor" ref={ref} className="py-28 px-6 bg-[#0B0B0B]">
      <div className="max-w-7xl mx-auto">
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-14 items-center">

          {/* Text */}
          <motion.div
            initial={{ opacity: 0, x: -20 }}
            animate={isInView ? { opacity: 1, x: 0 } : {}}
            transition={{ duration: 0.6 }}
          >
            <span className="text-xs font-semibold text-[#7ABF3C] tracking-[0.3em] uppercase">
              Suporte ao Estudo
            </span>
            <h2 className="mt-4 text-4xl md:text-5xl font-black text-white leading-tight">
              Você não precisa{" "}
              <span className="gold-gradient">travar sozinho.</span>
            </h2>
            <p className="mt-6 text-gray-400 text-lg leading-relaxed">
              O instrutor virtual ajuda a tirar dúvidas, explicar conteúdos e
              orientar revisões dentro da sua trilha de estudo.
            </p>

            <ul className="mt-8 space-y-5">
              {bullets.map((item, i) => {
                const Icon = item.icon;
                return (
                  <motion.li
                    key={item.titulo}
                    initial={{ opacity: 0, x: -16 }}
                    animate={isInView ? { opacity: 1, x: 0 } : {}}
                    transition={{ delay: 0.2 + i * 0.1, duration: 0.5 }}
                    className="flex items-start gap-4"
                  >
                    <div className="flex-shrink-0 w-9 h-9 rounded-lg border border-[#7ABF3C]/25 bg-[#7ABF3C]/5 flex items-center justify-center text-[#7ABF3C]/60 mt-0.5">
                      <Icon className="w-4 h-4" strokeWidth={1.5} />
                    </div>
                    <div>
                      <p className="text-sm font-bold text-white mb-0.5">{item.titulo}</p>
                      <p className="text-sm text-gray-500 leading-relaxed">{item.texto}</p>
                    </div>
                  </motion.li>
                );
              })}
            </ul>

            <motion.div
              initial={{ opacity: 0 }}
              animate={isInView ? { opacity: 1 } : {}}
              transition={{ delay: 0.6, duration: 0.5 }}
              className="mt-8 border-t border-[#222222] pt-6"
            >
              <p className="text-xs text-gray-600 leading-relaxed">
                O instrutor virtual é um recurso de apoio ao estudo. Não substitui
                aulas oficiais, instrutores das Forças Armadas ou qualquer orientação
                institucional formal.
              </p>
            </motion.div>
          </motion.div>

          {/* App screen placeholder */}
          <motion.div
            initial={{ opacity: 0, x: 20 }}
            animate={isInView ? { opacity: 1, x: 0 } : {}}
            transition={{ duration: 0.6, delay: 0.15 }}
            className="flex justify-center lg:justify-end"
          >
            <div className="w-full max-w-xs aspect-[9/16] rounded-3xl border border-[#222222] bg-[#121212] flex flex-col overflow-hidden shadow-[0_0_60px_rgba(122,191,60,0.05)]">
              {/* Phone header */}
              <div className="flex items-center gap-2.5 px-5 py-4 border-b border-[#222222]">
                <div className="w-8 h-8 rounded-full bg-[#7ABF3C]/10 border border-[#7ABF3C]/20 flex items-center justify-center">
                  <MessageSquare className="w-4 h-4 text-[#7ABF3C]/60" strokeWidth={1.5} />
                </div>
                <div>
                  <p className="text-xs font-bold text-white">Instrutor Virtual</p>
                  <p className="text-[10px] text-gray-600">Disponível agora</p>
                </div>
              </div>

              {/* Chat messages */}
              <div className="flex-1 px-4 py-5 space-y-4 overflow-hidden">
                <div className="flex justify-start">
                  <div className="max-w-[80%] bg-[#1a1a1a] border border-[#222222] rounded-2xl rounded-tl-sm px-3.5 py-2.5">
                    <p className="text-xs text-gray-300 leading-relaxed">
                      Olá! Sobre o que você tem dúvida hoje?
                    </p>
                  </div>
                </div>
                <div className="flex justify-end">
                  <div className="max-w-[80%] bg-[#7ABF3C]/10 border border-[#7ABF3C]/20 rounded-2xl rounded-tr-sm px-3.5 py-2.5">
                    <p className="text-xs text-gray-300 leading-relaxed">
                      Não entendi a parte de ontem.
                    </p>
                  </div>
                </div>
                <div className="flex justify-start">
                  <div className="max-w-[80%] bg-[#1a1a1a] border border-[#222222] rounded-2xl rounded-tl-sm px-3.5 py-2.5">
                    <p className="text-xs text-gray-300 leading-relaxed">
                      Sem problema. Vamos revisar juntos.
                    </p>
                  </div>
                </div>
                <div className="flex justify-end">
                  <div className="max-w-[80%] bg-[#7ABF3C]/10 border border-[#7ABF3C]/20 rounded-2xl rounded-tr-sm px-3.5 py-2.5">
                    <p className="text-xs text-gray-300 leading-relaxed">
                      Pelo início do módulo.
                    </p>
                  </div>
                </div>
                <div className="flex justify-start">
                  <div className="max-w-[80%] bg-[#1a1a1a] border border-[#222222] rounded-2xl rounded-tl-sm px-3.5 py-2.5">
                    <p className="text-xs text-gray-300 leading-relaxed">
                      Abrindo o conteúdo agora...
                    </p>
                  </div>
                </div>
              </div>

              {/* Placeholder label */}
              <div className="px-4 py-3 border-t border-[#222222] text-center">
                <p className="text-[10px] text-gray-600">Em breve: visual do aplicativo</p>
              </div>
            </div>
          </motion.div>

        </div>
      </div>
    </section>
  );
}
