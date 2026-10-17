/**
 * tailwind.config.js — AgriERP
 *
 * Source de vérité : assets/js/tailwind-config.js du prototype
 * (agrisync_prototype.zip, 91 pages) — fait foi en premier pour chaque
 * couleur/token effectivement utilisé comme classe Tailwind dans le HTML.
 * Complété par les alias listés au Document 06 §1.2 (06_DEVELOPMENT_STANDARDS.md)
 * qui ajoutent des tokens supplémentaires non présents dans le fichier
 * prototype d'origine mais référencés côté documentation.
 *
 * Décision documentée (Sprint 0, ticket 0.1) :
 * - `brand-maize` et `accent-yellow` sont deux noms de classe DIFFÉRENTS
 *   pointant vers la MÊME couleur #FFD55F. Nécessaire car assets/js/sidebar.js
 *   utilise `text-brand-maize` / `hover:text-brand-maize` (menu flottant,
 *   panneau Accès Rapide) alors que tailwind-config.js du prototype ne
 *   définissait que `accent-yellow` — sans cet alias, `brand-maize` serait
 *   une classe Tailwind non résolue (bug de couleur invisible, silencieux
 *   avec le compilateur CDN utilisé par le prototype statique). Avec un
 *   build Tailwind CLI réel (ce fichier), les deux classes doivent exister
 *   pour ne rien casser lors du portage fidèle du DOM du sidebar.
 * - Tout token supplémentaire découvert dans un fichier HTML du prototype
 *   lors d'un ticket ultérieur (Sprint 1+) doit être AJOUTÉ ici plutôt que
 *   d'être inventé localement dans une vue Blade (un seul point de vérité
 *   pour la charte graphique, cf. AVOID_INSTRUCTIONS.md § Inconsistent
 *   Coding Patterns).
 */
export default {
    content: [
        './vendor/laravel/framework/src/Illuminate/Pagination/resources/views/*.blade.php',
        './storage/framework/views/*.php',
        './resources/views/**/*.blade.php',
        './app/Livewire/**/*.php',
        './app/View/Components/**/*.php',
    ],
    theme: {
        extend: {
            colors: {
                // --- Source canonique : assets/js/tailwind-config.js (prototype, 91 pages) ---
                'brand-forest': '#052e16',
                'brand-forest-dark': '#00210d',
                'brand-emerald': '#065f46',
                'accent-yellow': '#FFD55F',
                'error-red': '#DC2626',
                'error-deep': '#BA1A1A',
                'error-bg': '#ffdad6',
                'info-blue': '#2563EB',
                'surface-bg': '#F8F9FA',
                'surface-card': '#FFFFFF',
                'surface-zebra': '#F3F4F5',
                'outline-variant': '#bec9c2',
                'outline': '#6f7973',
                'on-surface': '#191c1d',

                // --- Alias/ajouts Document 06 §1.2 (06_DEVELOPMENT_STANDARDS.md) ---
                'brand-maize': '#FFD55F', // alias exact de accent-yellow — voir docblock ci-dessus

                /*
                 * `brand-maize-ink` — le maïs de la marque, POSÉ SUR FOND CLAIR.
                 *
                 * ⚠️⚠️ #FFD55F SUR BLANC DONNE 1,41:1. WCAG AA exige 4,5:1 pour
                 * du texte : le « ERP » de « AgriERP » était illisible sur la
                 * page de connexion, et l'étiquette de catégorie de la recherche
                 * globale — 10 px, gras — l'était plus encore. Sur un écran bon
                 * marché en plein soleil, à Ikpinlè, le nom du produit se lisait
                 * « Agri ».
                 *
                 * #8C6D00 donne 4,88:1 sur blanc : c'est le maïs le plus clair
                 * qui passe le seuil avec une marge, et non un brun choisi à
                 * l'œil. Le jaune d'origine reste inchangé partout où le fond
                 * est sombre (bandeau de connexion, ruban replié, menu Accès
                 * Rapide) : il y donne 10,6:1 et c'est la couleur validée.
                 *
                 * Ticket 15.7 — arbitrage client du 24/08/2026.
                 */
                'brand-maize-ink': '#8C6D00',
                'primary': '#004532',
                'primary-container': '#065f46',
                'secondary-container': '#c1edc8',
                'background': '#F8F9FA',
                'surface-container-lowest': '#ffffff',
                'surface-container-low': '#f3f4f5',
                'error': '#ba1a1a',
                'error-container': '#ffdad6',
            },
            spacing: {
                xs: '4px',
                sm: '8px',
                md: '16px',
                lg: '24px',
                xl: '32px',
                '2xl': '48px',
            },
            borderRadius: {
                lg: '0.5rem',
                xl: '0.75rem',
            },
            fontFamily: {
                sans: ['Inter', 'sans-serif'],
            },
        },
    },
    plugins: [require('@tailwindcss/forms')],
};
