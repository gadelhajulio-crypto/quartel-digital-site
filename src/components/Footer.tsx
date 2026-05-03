"use client";

import { Separator } from "@/components/ui/separator";
import Image from "next/image";

export function Footer() {
  return (
    <footer className="border-t border-[#222222] bg-[#0B0B0B]">
      <div className="max-w-7xl mx-auto px-6 py-12">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-10 mb-10">
          {/* Brand */}
          <div>
            <a href="#" className="flex items-center gap-3 mb-2">
              <div className="bg-white rounded-md p-1 flex items-center justify-center">
                <Image
                  src="/assets/logo/logoqd.png"
                  alt="Quartel Digital"
                  width={36}
                  height={36}
                  className="object-contain"
                />
              </div>
              <div className="flex flex-col leading-tight">
                <span className="font-bold text-white tracking-wide text-sm uppercase leading-none">
                  Quartel Digital
                </span>
                <span className="text-[10px] text-[#7ABF3C] tracking-widest leading-none mt-0.5">
                  Recruta Padrão
                </span>
              </div>
            </a>
            <p className="text-xs text-gray-600 mt-4 leading-relaxed max-w-xs">
              O Quartel Digital é o sistema de excelência acadêmica militar da
              plataforma Recruta Padrão.
            </p>
            <p className="text-sm text-gray-500 leading-relaxed max-w-xs mt-3">
              Plataforma educacional independente para recrutas do Exército,
              Marinha e Aeronáutica. Sem vínculo oficial com Forças Armadas.
            </p>
          </div>

          {/* Navegação */}
          <div>
            <h4 className="text-xs font-semibold text-gray-400 uppercase tracking-widest mb-4">
              Navegação
            </h4>
            <ul className="space-y-2">
              {[
                { label: "Começar preparação", href: "#forcas" },
                { label: "Como funciona", href: "#como-funciona" },
                { label: "Instrutor virtual", href: "#instrutor" },
                { label: "Resultados", href: "#resultados" },
                { label: "Diferenciais", href: "#diferenciais" },
              ].map((item) => (
                <li key={item.label}>
                  <a
                    href={item.href}
                    className="text-sm text-gray-500 hover:text-[#7ABF3C] transition-colors"
                  >
                    {item.label}
                  </a>
                </li>
              ))}
            </ul>
          </div>

          {/* Institucional */}
          <div>
            <h4 className="text-xs font-semibold text-gray-400 uppercase tracking-widest mb-4">
              Institucional
            </h4>
            <ul className="space-y-2">
              {["Termos de Uso", "Política de Privacidade", "Aviso de Independência"].map(
                (item) => (
                  <li key={item}>
                    <a
                      href="#"
                      className="text-sm text-gray-500 hover:text-[#7ABF3C] transition-colors"
                    >
                      {item}
                    </a>
                  </li>
                )
              )}
            </ul>
          </div>
        </div>

        <Separator className="bg-[#222222] mb-8" />

        <div className="flex flex-col md:flex-row items-center justify-between gap-4">
          <p className="text-xs text-gray-600">
            &copy; {new Date().getFullYear()} Recruta Padrão. Todos os direitos
            reservados.
          </p>
          <p className="text-xs text-gray-700 text-center max-w-lg leading-relaxed">
            O Quartel Digital é uma plataforma educacional independente, sem vínculo oficial
            com as Forças Armadas, Marinha do Brasil, Exército Brasileiro, Aeronáutica, Polícias
            Militares ou qualquer órgão governamental. Eventuais referências a carreiras, formações
            ou rotinas têm propósito exclusivamente informativo e educacional.
          </p>
        </div>
      </div>
    </footer>
  );
}
