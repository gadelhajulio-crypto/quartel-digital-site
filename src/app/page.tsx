import { Navbar } from "@/components/Navbar";
import { Footer } from "@/components/Footer";
import { Hero } from "@/components/sections/Hero";
import { TeseCentral } from "@/components/sections/TeseCentral";
import { OInimigo } from "@/components/sections/OInimigo";
import { SistemaProgressao } from "@/components/sections/SistemaProgressao";
import { EscolhaSuaForca } from "@/components/sections/EscolhaSuaForca";
import { Metodo } from "@/components/sections/Metodo";
import { InstrutorVirtual } from "@/components/sections/InstrutorVirtual";
import { Resultados } from "@/components/sections/Resultados";
import { TelasApp } from "@/components/sections/TelasApp";
import { AvisoIndependencia } from "@/components/sections/AvisoIndependencia";
import { CTAFinal } from "@/components/sections/CTAFinal";

export default function Home() {
  return (
    <>
      <Navbar />
      <main>
        <Hero />
        <TeseCentral />
        <OInimigo />
        <SistemaProgressao />
        <EscolhaSuaForca />
        <Metodo />
        <InstrutorVirtual />
        <Resultados />
        <TelasApp />
        <AvisoIndependencia />
        <CTAFinal />
      </main>
      <Footer />
    </>
  );
}
