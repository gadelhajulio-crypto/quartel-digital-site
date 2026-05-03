# Quartel Digital — Site Institucional

Site institucional público da plataforma educacional Quartel Digital.
Desenvolvido com Next.js 15, TypeScript, Tailwind CSS e Framer Motion.

## Stack

- **Framework**: Next.js 15 (App Router)
- **Linguagem**: TypeScript
- **Estilo**: Tailwind CSS v4
- **Animações**: Framer Motion
- **Deploy**: Compatível com Vercel, Netlify ou qualquer servidor Node.js

## Comandos

### Instalar dependências

```bash
npm install
```

### Rodar em desenvolvimento

```bash
npm run dev
```

Acesse: [http://localhost:3000](http://localhost:3000)

### Build de produção

```bash
npm run build
```

### Iniciar em produção

```bash
npm start
```

## Estrutura

```
src/
├── app/
│   ├── globals.css        # Estilos globais e variáveis CSS
│   ├── layout.tsx         # Layout raiz com metadados SEO
│   └── page.tsx           # Página principal (monta todas as seções)
└── components/
    ├── Navbar.tsx          # Barra de navegação fixa com scroll detection
    ├── Footer.tsx          # Rodapé institucional
    └── sections/
        ├── Hero.tsx                   # Seção hero com headline e stats
        ├── Metodo.tsx                 # 4 etapas do método de estudo
        ├── Plataforma.tsx             # Recursos da plataforma
        ├── AreasEstudo.tsx            # 8 áreas de conhecimento
        ├── Diferenciais.tsx           # Por que escolher o Quartel Digital
        ├── SegurancaInstitucional.tsx # Pilares de segurança e privacidade
        ├── AvisoIndependencia.tsx     # Disclaimer de independência institucional
        └── CTAFinal.tsx               # Call to action final
```

## Design

- Tema escuro (`#080810` como base)
- Paleta dourada (`#c9a84c`) como accent
- Tipografia Inter
- Animações de entrada com Framer Motion (fade + slide)
- Layout responsivo mobile-first

## Aviso Legal

O Quartel Digital é uma plataforma educacional independente, sem vínculo
oficial com as Forças Armadas, Marinha do Brasil, Exército Brasileiro,
Aeronáutica, Polícias Militares ou qualquer órgão governamental.
