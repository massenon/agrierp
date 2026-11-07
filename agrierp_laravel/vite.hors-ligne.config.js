import { defineConfig } from 'vite';

/**
 * PWA-1 — Construction de la caisse hors ligne : fichiers à NOM STABLE (sans empreinte) sous `public/assets/hors-ligne/`.
 * La page statique `public/caisse-hors-ligne.html` ne peut pas lire le manifeste Vite : elle référence ces noms. Le service
 * worker les sert RÉSEAU D'ABORD (jamais un vieux script avec un nouveau HTML) puis, hors ligne, depuis son cache.
 * Lancé par `npm run build` (après le build principal). Aucune dépendance de plus : esbuild est celui de Vite.
 */
export default defineConfig({
    publicDir: false,
    build: {
        outDir: 'public/assets/hors-ligne',
        emptyOutDir: true,
        rollupOptions: {
            input: { caisse: 'resources/js/hors-ligne/caisse-app.js', 'caisse-style': 'resources/css/hors-ligne.css' },
            output: {
                entryFileNames: '[name].js',
                chunkFileNames: 'chunks/[name]-[hash].js',
                assetFileNames: '[name][extname]',
            },
        },
    },
});
