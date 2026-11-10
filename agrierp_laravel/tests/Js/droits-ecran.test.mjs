import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { droitsDeLEcran } from '../../resources/js/hors-ligne/droits-ecran.js';

/**
 * CAISSE-1 (volet animalier) — l'écran de la PWA suit les DROITS du compte ; le Gate `utiliser-mode-hors-ligne` est UNIQUE.
 */
const racine = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const lire = (p) => readFileSync(path.join(racine, p), 'utf8');

test('droits de l\'écran : caisse = manage-ventes, fiches = view-elevage, écriture = manage-elevage', () => {
    assert.deepEqual(droitsDeLEcran({ role: 'animalier', droits: ['view-elevage', 'manage-elevage'] }), { caisse: false, fiches: true, ecritureFiches: true });
    assert.deepEqual(droitsDeLEcran({ role: 'caissier', droits: ['manage-ventes'] }), { caisse: true, fiches: false, ecritureFiches: false });
    assert.deepEqual(droitsDeLEcran({ role: 'admin', droits: ['manage-ventes', 'view-elevage', 'manage-elevage'] }), { caisse: true, fiches: true, ecritureFiches: true });
    assert.deepEqual(droitsDeLEcran({ role: 'x', droits: ['manage-ventes', 'view-elevage'] }), { caisse: true, fiches: true, ecritureFiches: false }, 'lecture seule sans manage-elevage');
    assert.deepEqual(droitsDeLEcran({ role: 'x', droits: [] }), { caisse: false, fiches: false, ecritureFiches: false });
});

test('appareil appairé avant le changement (pas de droits) : ancien comportement', () => {
    assert.deepEqual(droitsDeLEcran({ role: 'admin' }), { caisse: true, fiches: true, ecritureFiches: true });
    assert.deepEqual(droitsDeLEcran({ role: 'caissier' }), { caisse: true, fiches: true, ecritureFiches: false });
    assert.deepEqual(droitsDeLEcran(null), { caisse: true, fiches: true, ecritureFiches: false });
});

test('garde de sources : UN Gate, lu par la page, la route et le menu ; l\'écran n\'est pas lié au nom du rôle', () => {
    const gates = lire('app/Providers/AppServiceProvider.php');
    assert.equal([...gates.matchAll(/Gate::define\('utiliser-mode-hors-ligne'/g)].length, 1);
    assert.ok(gates.includes("canAny(['manage-ventes', 'manage-elevage'])"));
    assert.ok(lire('routes/web.php').includes("->middleware(['auth', 'can:utiliser-mode-hors-ligne'])"));
    assert.ok(lire('app/Livewire/Profil/ModeHorsLigne.php').includes("Gate::allows('utiliser-mode-hors-ligne')"));
    assert.ok(lire('resources/views/layouts/app.blade.php').includes("@can('utiliser-mode-hors-ligne')"));
    for (const f of ['app/Livewire/Profil/ModeHorsLigne.php', 'routes/web.php']) assert.ok(!/profil\.mode-hors-ligne[\s\S]{0,80}manage-ventes/.test(lire(f)) && !lire(f).includes("Gate::allows('manage-ventes')"), `${f} : plus de droit des ventes seul`);
    const app = lire('resources/js/hors-ligne/caisse-app.js');
    assert.ok(!/ROLES_ECRITURE\.includes\(app\.role\)/.test(app) && !/role: app\.role/.test(app), 'l\'écriture des fiches suit manage-elevage, pas le nom du rôle');
    assert.ok(app.includes('if (famille === null && !app.droits.caisse) return;'));
    assert.ok(lire('app/Http/Controllers/Api/AuthController.php').includes("'droits' => array_values(array_filter(['manage-ventes', 'view-elevage', 'manage-elevage']"));
});
