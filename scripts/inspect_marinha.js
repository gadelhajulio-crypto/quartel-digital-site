const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');
const path = require('path');

const SUPABASE_URL = 'https://fjwvtzvfbhubxicsmbdz.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZqd3Z0enZmYmh1YnhpY3NtYmR6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjU0MTMwNjQsImV4cCI6MjA4MDk4OTA2NH0.DWARgikiJUdBugX7UqZ-A-_fBdVODJ_KBc-QfXdyhwM';

const OUT_FILE = path.join(process.cwd(), 'inspect_result.txt');
fs.writeFileSync(OUT_FILE, '--- START INSPECTION ---\n');

function log(msg) {
    console.log(msg);
    fs.appendFileSync(OUT_FILE, msg + '\n');
}

function logTable(data) {
    // Basic table formatting or JSON
    if (!data) return log('null');
    log(JSON.stringify(data, null, 2));
}

const supabase = createClient(SUPABASE_URL, SUPABASE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false }
});

async function run() {
    try {
        log('\n--- 1. MODULOS (MARINHA) ---');
        const { data: modules, error: err1 } = await supabase
            .from('modulos')
            .select('id, titulo, ordem, forca, ativo, created_at')
            .eq('forca', 'marinha')
            .order('ordem');

        if (err1) log('Error 1: ' + JSON.stringify(err1));
        else logTable(modules);

        log('\n--- 2. AULAS (MARINHA) ---');
        const { data: lessons, error: err2 } = await supabase
            .from('lessons')
            .select('id, title, module, lesson_order, force, created_at')
            .eq('force', 'marinha')
            .order('module', { ascending: true })
            .order('lesson_order', { ascending: true });

        if (err2) log('Error 2: ' + JSON.stringify(err2));
        else logTable(lessons);

        log('\n--- 3. REGRAS (LESSON_MEDIA) ---');
        const lessonIds = lessons ? lessons.map(l => l.id) : [];
        if (lessonIds.length > 0) {
            const { data: m, error: err3 } = await supabase
                .from('lesson_media')
                .select('lesson_id, type, available_after_hours, "order"') // Quote order if needed
                .in('lesson_id', lessonIds)
                .order('lesson_id')
                .order('order');
            if (err3) log('Error 3: ' + JSON.stringify(err3));
            else logTable(m);
        } else {
            log('No lessons found to check media');
        }

        log('\n--- 4.1 MODULO 0 CHECK (MODULOS) ---');
        const { data: mod0, error: err41 } = await supabase
            .from('modulos')
            .select('id, titulo, ordem, ativo')
            .eq('forca', 'marinha')
            .or('titulo.ilike.%regulamento%,titulo.ilike.%disciplinar%,titulo.ilike.%RDM%,titulo.ilike.%disciplina%');

        if (err41) log('Error 4.1: ' + JSON.stringify(err41));
        else logTable(mod0);

        log('\n--- 4.2 MODULO 0 CHECK (AULAS) ---');
        const { data: lessons0, error: err42 } = await supabase
            .from('lessons')
            .select('id, title, lesson_order')
            .eq('force', 'marinha')
            .ilike('module', '%disciplinar%')
            .order('lesson_order');

        if (err42) log('Error 4.2: ' + JSON.stringify(err42));
        else logTable(lessons0);

        log('\n--- 5. PRIMEIRO MODULO ---');
        const { data: firstMod, error: err5 } = await supabase
            .from('modulos')
            .select('id, titulo, ordem')
            .eq('forca', 'marinha')
            .order('ordem')
            .limit(1);

        if (err5) log('Error 5: ' + JSON.stringify(err5));
        else logTable(firstMod);

        log('\n--- 6.1 MODULOS SEM AULAS ---');
        if (modules && lessons) {
            const activeModuleTitles = new Set(lessons.map(l => l.module));
            const emptyModules = modules.filter(m => !activeModuleTitles.has(m.titulo));
            logTable(emptyModules.map(m => ({ id: m.id, titulo: m.titulo })));
        }

        log('\n--- 6.2 AULAS SEM MODULO ---');
        if (modules && lessons) {
            const knownModuleTitles = new Set(modules.map(m => m.titulo));
            const orphanLessons = lessons.filter(l => !knownModuleTitles.has(l.module));
            logTable(orphanLessons.map(l => ({ id: l.id, title: l.title, module: l.module })));
        }

        log('\n--- 6.3 ORDEM DUPLICADA ---');
        if (lessons) {
            const counts = {};
            lessons.forEach(l => {
                const key = `${l.module}||${l.lesson_order}`;
                counts[key] = (counts[key] || 0) + 1;
            });
            const duplicates = Object.entries(counts)
                .filter(([key, count]) => count > 1)
                .map(([key, count]) => {
                    const [mod, ord] = key.split('||');
                    return { module: mod, lesson_order: ord, total: count };
                });
            logTable(duplicates);
        }

        log('--- END INSPECTION ---');
    } catch (e) {
        log('FATAL EXCEPTION: ' + e);
    }
}

run();
