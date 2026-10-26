import collapse from '@alpinejs/collapse';
import './verrou';

/**
 * AgriERP — resources/js/app.js
 *
 * Décision d'architecture (Sprint 0, ticket 0.2, documentée) :
 * Le prototype statique (assets/js/common.js) pilotait sidebar/dropdowns/
 * accordéon KPI/toasts via des fonctions globales (openSidebar(),
 * toggleDropdown(), toggleKpiPanel(), showToast()...). Dans la conversion
 * Livewire 3 + Alpine.js (stack cible, Document 00 §0), ces interactions
 * purement visuelles sont réimplémentées en `x-data`/`x-show`/`x-on:click`
 * directement dans les composants Blade partagés (layouts/app.blade.php,
 * components/kpi-accordion.blade.php, components/toast-container.blade.php)
 * plutôt que portées telles quelles en fonctions globales — c'est le
 * mécanisme idiomatique de la stack cible, sans changer ni le DOM, ni les
 * classes Tailwind, ni le comportement visuel final (Directive Transversale,
 * Document 00 §1).
 *
 * 🔴→✅ TICKET 14.19 — BUG BLOQUANT CORRIGÉ : ALPINE ÉTAIT CHARGÉ DEUX FOIS.
 *
 * Ce fichier importait Alpine (`import Alpine from 'alpinejs'`), l'exposait
 * en `window.Alpine` et appelait `Alpine.start()`. Or **Livewire 3 embarque
 * et démarre sa propre instance d'Alpine** : la stack cible n'attend pas
 * qu'on en amorce une seconde.
 *
 * Conséquence mesurée dans un vrai navigateur (première exécution de la
 * suite Dusk, ticket 14.18) :
 *     "Detected multiple instances of Alpine running"
 *     Uncaught ReferenceError: $wire is not defined
 * `$wire` est la magie Alpine fournie par Livewire ; la seconde instance ne
 * la connaît pas. **Toute interaction Livewire pilotée par Alpine était donc
 * cassée côté navigateur** — un `wire:submit` qui ne part pas, une modale qui
 * ne s'ouvre pas, un `$wire.close()` qui lève une exception. Le formulaire de
 * connexion lui-même ne se soumettait pas.
 *
 * Pourquoi personne ne l'avait vu : les 104 tests Feature passent tous par
 * `Livewire::test()`, qui exécute le composant CÔTÉ SERVEUR sans jamais
 * charger la moindre ligne de JavaScript. Aucun d'eux ne pouvait détecter un
 * défaut qui n'existe que dans le navigateur.
 *
 * Le plugin `collapse` est désormais enregistré sur l'instance Alpine DE
 * LIVEWIRE, via l'événement `alpine:init` que Livewire émet avant de la
 * démarrer — la façon documentée de brancher un plugin sans dupliquer Alpine.
 */
document.addEventListener('alpine:init', () => {
    window.Alpine.plugin(collapse);
});

/**
 * Livewire 3 dispatche $this->dispatch('toast', ...) DIRECTEMENT comme browser event sur window.
 * Le relais Livewire.on('toast') ci-dessous n'est plus nécessaire et causait un doublon :
 * toast-container.blade.php recevait l'event une première fois depuis Livewire 3 (natif),
 * et une seconde fois depuis ce relais — supprimé le 26/10/2026.
 */
document.addEventListener('livewire:init', () => {
    /**
     * Ticket U5 (D-U5) — PAGE EXPIRÉE (419) EN FRANÇAIS.
     *
     * Sur un jeton CSRF expiré, Livewire 3 ouvre une boîte de confirmation ANGLAISE codée en dur
     * dans son JavaScript (« This page has expired. Would you like to refresh the page? »), qu'aucun
     * fichier `lang/` ne peut traduire. On la remplace par la même question, en français ; tout
     * autre échec garde le comportement de Livewire (fenêtre avec la page d'erreur, elle-même en
     * français : `resources/views/errors/`).
     */
    Livewire.hook('request', ({ fail }) => {
        fail(({ status, preventDefault }) => {
            if (status !== 419) {
                return;
            }
            preventDefault();
            if (window.confirm('Cette page a expiré.\nVoulez-vous la recharger ?')) {
                window.location.reload();
            }
        });
    });
});
