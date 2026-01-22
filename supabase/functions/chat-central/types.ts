export type ChatInput = {
    recruta_id: string;
    session_id: string;
    source: "app" | "whatsapp";
    text: string;
};

export type Classificacao =
    | "pedagogica"
    | "administrativa"
    | "fora_de_escopo"
    | "tentativa_acesso_indevido";

export type RecrutaInstitucional = {
    recruta_id: string;
    forca: "exercito" | "marinha" | "aeronautica";
    status: "ativo" | "inativo" | "bloqueado";
    instrutor_id: string;
    access_mode: "free" | "full";
    allowed_modules: string[];
};
