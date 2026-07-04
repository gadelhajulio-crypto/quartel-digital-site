import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { canAccessModule } from './useModuleAccess';
import type { Profile } from '../context/AuthContext';

// useModulesCatalog — fonte DB-driven da tab de módulos (substitui a constante
// hardcoded MARINHA_CURRICULUM). Reconcilia A-15 (GRANT) e A-16 (dupla fonte).
//
// Fontes:
//   - v_modulos_catalogo  → módulos por força (id, título, ordem, is_degustacao)
//   - v_lessons_panel     → lições por força (título, ordem, módulo UUID) [view canônica RCC]
// Agrupa lições por módulo (module UUID = v_modulos_catalogo.id).
//
// CADEADO: o gate é APENAS por módulo (canAccessModule → degustação/plano). Lição
// nunca é travada individualmente porque o banco não sabe disso hoje —
// vw_rdm_lessons_v2.status é 'available' fixo, não há lógica de pré-requisito.
// `locked: false` em toda lição é intencional. Cadeado real por lição fica para
// quando existir quiz/pré-requisito (ver A-16 em docs/AUDITORIA_INICIAL.md).

export interface CatalogLesson {
  title: string;
  locked: boolean;
}

export interface CatalogModule {
  id: string;
  title: string;
  lessons: CatalogLesson[];
}

export function useModulesCatalog(force: string, profile: Profile | null) {
  const [modules, setModules] = useState<CatalogModule[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let active = true;

    async function load() {
      setLoading(true);
      try {
        const [modRes, lessonRes] = await Promise.all([
          supabase
            .from('v_modulos_catalogo')
            .select('id, titulo, ordem, is_degustacao')
            .eq('forca', force)
            .order('ordem', { ascending: true }),
          supabase
            .from('v_lessons_panel')
            .select('title, module, lesson_order')
            .eq('force', force)
            .order('lesson_order', { ascending: true }),
        ]);

        if (!active) return;
        if (modRes.error) throw modRes.error;
        if (lessonRes.error) throw lessonRes.error;

        // Agrupar lições por módulo (UUID). Ordem já vem do banco (lesson_order).
        const lessonsByModule = new Map<string, CatalogLesson[]>();
        for (const l of (lessonRes.data ?? []) as any[]) {
          const arr = lessonsByModule.get(l.module) ?? [];
          arr.push({ title: l.title, locked: false }); // ver nota CADEADO acima
          lessonsByModule.set(l.module, arr);
        }

        // Gate por módulo (degustação/plano) + só módulos com lições.
        const result: CatalogModule[] = ((modRes.data ?? []) as any[])
          .filter((m) =>
            canAccessModule({
              profile,
              modulo: { id: m.id, titulo: m.titulo, is_degustacao: m.is_degustacao ?? false },
            }),
          )
          .map((m) => ({
            id: m.id as string,
            title: m.titulo as string,
            lessons: lessonsByModule.get(m.id) ?? [],
          }))
          .filter((m) => m.lessons.length > 0);

        setModules(result);
      } catch (err) {
        console.error('[MODULES_CATALOG] erro ao carregar módulos:', err);
        if (active) setModules([]);
      } finally {
        if (active) setLoading(false);
      }
    }

    load();
    return () => {
      active = false;
    };
    // profile: dependemos só de tipo_acesso (campo do gate presente no Profile), para
    // evitar re-fetch por identidade. paid_at não existe no Profile do AuthContext —
    // canAccessModule trata como undefined (usuário 'completo' → acesso liberado).
  }, [force, profile?.tipo_acesso]);

  return { modules, loading };
}
