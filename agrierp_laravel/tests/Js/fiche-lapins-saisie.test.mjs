import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { AUTONOMIE, LIBELLES, MOTIFS, ROLES_ECRITURE } from '../../resources/js/hors-ligne/fiche-lapins-saisie.js';

/**
 * PWA-3 (fiche lapins, É3) — GARDE DE SOURCES de la saisie : le PHP (`FicheLapins.php`, `ClosedFiscalYearException`) et le Blade sont les MAÎTRES.
 * Les phrases de refus et d'avertissement, les libellés et leur ordre, les colonnes écrites par `saveDay` et le droit d'écriture sont lus
 * dans leurs sources et comparés à ceux du module JavaScript.
 */
const racine = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const lire = (p) => readFileSync(path.join(racine, p), 'utf8');
const norm = (t) => t.replace(/&amp;/g, '&').replace(/\\'/g, "'").replace(/\s+/g, ' ').trim();
const php = norm(lire('app/Livewire/Elevage/FicheLapins.php'));
const exception = norm(lire('app/Exceptions/ClosedFiscalYearException.php'));
const blade = norm(lire('resources/views/livewire/elevage/fiche-lapins.blade.php'));
const saisieSource = lire('resources/js/hors-ligne/fiche-lapins-saisie.js');

test('phrases de refus et d\'avertissement : celles du PHP, mot pour mot', () => {
    assert.ok(php.includes(norm(MOTIFS.aucuneBande)), 'aucune bande');
    assert.ok(php.includes(norm(MOTIFS.dateInvalide)), 'date invalide');
    assert.ok(php.includes(norm(MOTIFS.ancienneFiche)), 'fiche ancienne non ventilée');
    assert.ok(php.includes(norm(MOTIFS.enregistre)), 'jour enregistré');
    assert.ok(exception.includes(MOTIFS.exerciceClos('{$annee}', '{$jourFr}')), 'exercice clos');
    assert.ok(php.includes(MOTIFS.mortsAuDessus('{$morts}', '{$this->previousEffectif}')), 'morts supérieurs à la veille');
    const somme = MOTIFS.somme('JJ', 'S', 'T');
    for (const morceau of ['Avertissement (hors maquette) — fiche du ', "la somme des catégories (", "diffère de l'effectif total (", "Un effectif de catégorie ne descend jamais sous 0 : vérifiez les ventes, morts et dons saisis."]) {
        assert.ok(somme.includes(morceau) && php.includes(norm(morceau)), `avertissement de somme : « ${morceau} »`);
    }
});

test('libellés du formulaire : tous dans le Blade, dans le même ordre', () => {
    for (const [cle, texte] of Object.entries(LIBELLES)) {
        assert.ok(blade.includes(norm(texte)), `« ${texte} » (${cle}) est absent du Blade`);
    }
    assert.ok(blade.includes("Jour antérieur à l'effectif de départ fixé le {{ \\Carbon\\Carbon::parse($cat['depart_date'])->format('d/m/Y') }} : les effectifs par catégorie ne sont pas calculés (—)."));
    assert.equal(MOTIFS.avantDepart('JJ/MM/AAAA'), "Jour antérieur à l'effectif de départ fixé le JJ/MM/AAAA : les effectifs par catégorie ne sont pas calculés (—).");
    assert.ok(blade.includes("Fiche ancienne non ventilée par catégorie : {{ $mortAncienTotal ?? 0 }} mort(s) et {{ $donAncienTotal ?? 0 }} don(s) non ventilé(s) y sont enregistrés. Ventilez-les ci-dessus avant d'enregistrer."));
    const ordre = ['achat', 'ne', 'morts', 'dons', 'passage', 'departSaisissable', 'effectifM', 'effectifF', 'effectifSevres', 'effectifSmeres', 'effectifFinal', 'taux', 'pesee', 'poidsMoyen', 'enregistrer'];
    const dansBlade = ordre.map((k) => blade.indexOf(norm(LIBELLES[k])));
    assert.deepEqual([...dansBlade].sort((a, b) => a - b), dansBlade, 'ordre des libellés dans le Blade');
    const debut = saisieSource.indexOf('const racine = h(');
    const refs = ['L.achat', 'L.ne', 'L.morts', 'L.dons', 'L.passage', 'departZone', 'L.effectifM', 'L.effectifF', 'L.effectifSevres', 'L.effectifSmeres', 'L.effectifFinal', 'L.taux', 'L.pesee', 'L.poidsMoyen'];
    const dansJs = refs.map((r) => saisieSource.indexOf(r, debut));
    assert.ok(dansJs.every((p) => p > 0), 'tous les champs sont dans le formulaire');
    assert.deepEqual([...dansJs].sort((a, b) => a - b), dansJs, 'ordre des champs du formulaire JavaScript');
});

test('colonnes écrites : celles de saveDay (PHP) et de la saisie (JS)', () => {
    const bloc = php.slice(php.indexOf('$donnees = ['), php.indexOf('// Ticket 15.41 — le DÉPART'));
    const colonnes = [...bloc.matchAll(/'(\w+)' =>/g)].map((m) => m[1]);
    assert.ok(colonnes.length >= 19, `colonnes lues : ${colonnes.length}`);
    for (const c of colonnes) assert.ok(new RegExp(`\\b${c}\\b`).test(saisieSource.slice(saisieSource.indexOf('const donnees = {'))), `la colonne « ${c} » de saveDay n'est pas écrite par le JavaScript`);
    for (const c of ['cat_depart_repro', 'cat_depart_sevre', 'cat_depart_jeune']) assert.ok(php.includes(`'${c}' =>`) && saisieSource.includes(c));
});

test('contrôles de saveDay dans le même ordre', () => {
    const ordrePhp = ['authorize(\'manage-elevage\')', 'Aucune bande active', 'Date invalide', 'refusExerciceClos', "$cat['refus_passage']", 'verifierDepart($departSaisi', 'non ventilés par catégorie'].map((m) => php.indexOf(m));
    assert.deepEqual([...ordrePhp].sort((a, b) => a - b), ordrePhp);
    const fonction = saisieSource.slice(saisieSource.indexOf('export function enregistrerJour'));
    const ordreJs = ['ROLES_ECRITURE', 'F.motifs.aucuneBande', 'MOTIFS.dateInvalide', 'refusExerciceClos(', 'refus_passage', 'verifierDepart(', 'F.motifs.ancienneFiche'].map((m) => fonction.indexOf(m));
    assert.ok(ordreJs.every((p) => p >= 0));
    assert.deepEqual([...ordreJs].sort((a, b) => a - b), ordreJs);
    assert.ok(php.includes('recalculerEnCascade($lot->id, $this->selectedDate)') && fonction.includes('recalculerEnCascade('));
});

test('droit d\'écriture : manage-elevage (les rôles du seeder), lecture seule sinon', () => {
    assert.deepEqual(ROLES_ECRITURE, ['admin', 'animalier']);
    const seeder = lire('database/seeders/RolesAndPermissionsSeeder.php');
    for (const role of ['comptable', 'caissier']) {
        const bloc = seeder.slice(seeder.indexOf(`'${role}'`), seeder.indexOf(`'${role}'`) + 900);
        assert.ok(!bloc.slice(0, bloc.indexOf(']')).includes('manage-elevage'), `${role} n'a pas manage-elevage`);
    }
    assert.ok(seeder.includes("'animalier'") && seeder.includes('manage-elevage'));
});

test('autonomie alimentaire : les cinq états et leurs phrases sont ceux du composant Blade', () => {
    const composant = norm(lire('resources/views/components/autonomie-alimentaire.blade.php'));
    const dans = (texte) => assert.ok(composant.includes(norm(texte)), `absent du composant : « ${texte} »`);
    dans(AUTONOMIE.aucunTitre);
    dans(AUTONOMIE.aucunTexte('{{ $filiere }}'));
    dans(AUTONOMIE.ruptureTitre);
    dans(AUTONOMIE.ruptureTexte("{{ $a['product']->name }}", "{{ $a['stock_kg'] }}"));
    dans(AUTONOMIE.inconnu("{{ $a['product']->name }}", "{{ $a['stock_kg'] }}").replace('—', '<strong>—</strong>'));
    dans(AUTONOMIE.critiqueTitre);
    dans(AUTONOMIE.critiqueTexte("{{ $a['product']->name }}", "{{ $a['autonomie_jours'] }}"));
    assert.ok(composant.includes(norm("Autonomie alimentaire : <strong>{{ $a['autonomie_jours'] }} jours</strong> ({{ $a['product']->name }}, {{ $a['stock_kg'] }} Kg en stock).")));
    assert.equal(AUTONOMIE.normal('4.5', 'P', '9'), 'Autonomie alimentaire : 4.5 jours (P, 9 Kg en stock).');
    // Le seuil critique et la formule viennent du service PHP.
    const service = norm(lire('app/Services/AutonomieAlimentaireService.php'));
    assert.ok(service.includes("round($stockKg / $consommationKgJour, 1) : 99") && service.includes("$rupture || $autonomieJours <= "));
    assert.ok(service.includes("'%provende%'") && service.includes("'%aliment%'"));
});

test('rationnement et provende : libellés du tableau dans le Blade', () => {
    for (const k of ['provende', 'categorie', 'effectif', 'ration', 'servie', 'totalProvende']) assert.ok(blade.includes(norm(LIBELLES[k])), `« ${LIBELLES[k]} » absent du Blade`);
});
