/**
 * PWA-3 (fiche lapins, É3) — TEST DE BOUT EN BOUT de la SAISIE d'un jour de la fiche lapins hors ligne (Playwright + Chromium, lancé À LA MAIN).
 *
 *   node tests/Js/e2e/fiche-lapins-saisie.e2e.mjs            # depuis agrierp_laravel/, après `npm run build`
 *
 * Même sûreté que les autres e2e (php -S, base SQLITE TEMPORAIRE). Scénario (compte `admin`, qui a `manage-elevage`) : appairage → tirage →
 * réseau COUPÉ → fiche lapins → saisie d'un jour passé (3 morts) : refus avec la phrase du web (départ faux), puis enregistrement ; l'effectif
 * des jours SUIVANTS change à l'écran (cascade) ; le serveur n'a RIEN reçu ; la page est rechargée HORS LIGNE : la saisie est toujours là,
 * toujours « en attente d'envoi ».
 */
import { createRequire } from 'node:module';
import { spawn, execFileSync } from 'node:child_process';
import net from 'node:net';
import os from 'node:os';
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

const require = createRequire('/opt/node22/lib/node_modules/');
const { chromium } = require('playwright');

const racine = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const dossier = fs.mkdtempSync(path.join(os.tmpdir(), 'agrierp-e2e-'));
const db = path.join(dossier, 'e2e.sqlite');
assert.ok(db.startsWith(os.tmpdir()), 'la base de test doit être dans le dossier temporaire');
fs.writeFileSync(db, '');

const libre = () => new Promise((ok) => { const s = net.createServer(); s.listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => ok(p)); }); });
const port = await libre();
const base = `http://127.0.0.1:${port}`;
const env = { ...process.env, DB_CONNECTION: 'sqlite', DB_DATABASE: db, DB_URL: '', CACHE_STORE: 'file', SESSION_DRIVER: 'file', QUEUE_CONNECTION: 'sync', MAIL_MAILER: 'log', APP_ENV: 'local', APP_DEBUG: 'false', APP_URL: base, MECEF_ACTIF: 'true', PHP_CLI_SERVER_WORKERS: '4' };
const php = (args) => execFileSync('php', args, { cwd: racine, env, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
// Pas de binaire `sqlite3` requis : PDO de PHP lit/écrit la base temporaire.
const sql = (requete) => execFileSync('php', ['-r', "$p = new PDO('sqlite:'.$argv[1]); $p->setAttribute(PDO::ATTR_TIMEOUT, 10); $s = $p->query($argv[2]); if ($s && $s->columnCount()) { foreach ($s->fetchAll(PDO::FETCH_NUM) as $r) { echo implode('|', $r).\"\\n\"; } }", db, requete], { encoding: 'utf8' }).trim();

const resultats = [];
const ok = (nom) => { resultats.push(nom); console.log(`  ✔ ${nom}`); };

console.log(`Base temporaire : ${db}\nServeur : ${base}`);
php(['artisan', 'migrate:fresh', '--seed', '--force']);
php(['artisan', 'tinker', '--execute', `
    $lap = \\App\\Models\\LivestockSpecies::firstOrCreate(['code' => 'cuniculture'], ['label' => 'Cuniculture', 'is_enabled' => true]);
    $lot = \\App\\Models\\LivestockLot::forceCreate(['code' => 'LAP-SAISIE', 'species_id' => $lap->id, 'stage' => 'engraissement', 'initial_quantity' => 40, 'current_quantity' => 40, 'created_date' => '2026-01-01', 'status' => 'actif', 'is_active' => true]);
    foreach ([2, 1, 0] as $k) {
        $f = new \\App\\Models\\LivestockDailyEntry();
        $f->forceFill(['lot_id' => $lot->id, 'entry_date' => now()->setTimezone('Africa/Porto-Novo')->subDays($k)->toDateString(), 'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 0, 'don' => 0, 'effectif_final' => 40]);
        $f->save();
    }
`]);
const lotId = sql("select id from livestock_lots where code='LAP-SAISIE'");

const serveur = spawn('php', ['-S', `127.0.0.1:${port}`, path.join(racine, 'vendor/laravel/framework/src/Illuminate/Foundation/resources/server.php')], { cwd: path.join(racine, 'public'), env, stdio: 'ignore' });
const arreter = () => { try { serveur.kill('SIGTERM'); } catch { /* déjà arrêté */ } };
process.on('exit', arreter);
for (let i = 0; i < 60; i++) { try { if ((await fetch(`${base}/up`)).ok) break; } catch { /* pas prêt */ } await new Promise((r) => setTimeout(r, 250)); }


const effectifsServeur = () => sql("select group_concat(effectif_final, ',') from (select effectif_final from livestock_daily_entries order by entry_date)");
const avant = effectifsServeur();
assert.equal(avant, '40,40,40');

let navigateur;
let echec = null;
try {
    navigateur = await chromium.launch();
    const contexte = await navigateur.newContext({ viewport: { width: 1280, height: 900 }, deviceScaleFactor: 1, locale: 'fr-FR' });
    const page = await contexte.newPage();
    page.on('pageerror', (e) => console.log('  [erreur page]', e.message));

    await page.goto(`${base}/login`);
    await page.waitForLoadState('networkidle');
    await page.fill('#identifiant', 'admin');
    await page.fill('#password', 'LogiAgriERP@2026');
    await Promise.all([page.waitForURL('**/dashboard', { timeout: 30000 }), page.click('[dusk=login-submit]')]);
    await page.goto(`${base}/mode-hors-ligne`);
    await page.waitForSelector('#hl-mdp');
    await page.fill('#hl-mdp', 'LogiAgriERP@2026');
    await page.fill('#hl-pin', '4821');
    await page.fill('#hl-pin2', '4821');
    await page.click('#hl-activer');
    await page.waitForSelector('text=Appareil appairé', { timeout: 30000 });
    ok('connexion web et appairage du compte « admin »');

    await page.goto(`${base}/caisse-hors-ligne.html`);
    await page.waitForSelector('#champ-pin');
    await page.fill('#champ-pin', '4821');
    await page.click('#form-pin button');
    await page.waitForSelector('#contenu:not([hidden])');
    await page.waitForFunction(() => /Synchronisé/.test(document.querySelector('#etat-synchro').textContent), null, { timeout: 30000 });
    await page.waitForSelector('#btn-vue-fiche:not([hidden])');
    ok('tirage initial : la fiche lapins est offerte');

    const colonne = async () => page.$$eval('#fiche-mensuel tbody tr[data-jour] td:nth-child(11)', (t) => t.map((x) => x.textContent).filter((v) => v !== '—'));
    // --- Hors ligne : ouvrir la fiche, choisir hier ---
    await contexte.setOffline(true);
    await page.click('#btn-vue-fiche');
    await page.waitForSelector('#fiche-saisie');
    const hier = sql("select entry_date from livestock_daily_entries order by entry_date limit 1 offset 1");
    const aujourdhui = sql("select entry_date from livestock_daily_entries order by entry_date desc limit 1");
    await page.fill('#fiche-date', hier);
    await page.dispatchEvent('#fiche-date', 'change');
    await page.waitForSelector(`#fiche-mensuel tbody tr.choisi[data-jour="${hier}"]`);
    assert.equal(await page.isDisabled('#saisie-enregistrer'), false, 'le compte admin peut écrire');
    assert.equal(await page.inputValue('#saisie-departJeune'), '40', 'départ proposé d\'après le stade (engraissement = Jeune)');
    ok('fiche ouverte hors ligne sur un jour passé, départ proposé d\'après le stade, bouton « Enregistrer ce Jour » actif');

    // --- Refus : départ faux, avec la phrase du web ; rien d'écrit ---
    await page.fill('#saisie-departJeune', '35');
    await page.waitForFunction(() => /\S/.test(document.querySelector('#saisie-alertes').textContent));
    const motif = await page.textContent('#saisie-alertes');
    assert.match(motif, /somme/i, 'le motif du départ est dit');
    await page.fill('#saisie-mortChair', '3');
    await page.click('#saisie-enregistrer');
    await page.waitForFunction(() => /\S/.test(document.querySelector('#saisie-retour').textContent));
    assert.equal((await page.textContent('#saisie-retour')).trim(), motif.trim(), 'le refus reprend la phrase du web');
    assert.deepEqual(await colonne(), ['40', '40', '40'], 'aucune écriture après un refus');
    ok('départ faux : refus avec la phrase du web, rien n\'est écrit');

    // --- Saisie correcte : 3 morts ---
    await page.fill('#saisie-departJeune', '40');
    await page.click('#saisie-enregistrer');
    await page.waitForFunction(() => /Jour enregistré avec succès\./.test(document.querySelector('#saisie-retour')?.textContent ?? ''));
    assert.match(await page.textContent('#saisie-etat'), /en attente d'envoi/);
    assert.deepEqual(await colonne(), ['40', '37', '37'], 'l\'effectif des jours suivants change (cascade)');
    assert.match(await page.textContent('.fiche-kpi'), /37$/, 'effectif total de la bande');
    assert.equal(effectifsServeur(), avant, 'le serveur n\'a rien reçu');
    ok('saisie enregistrée sur l\'appareil : 37 le jour saisi et le lendemain, « en attente d\'envoi », serveur intact');

    // --- Rechargement HORS LIGNE : la saisie est toujours là ---
    await page.reload();
    await page.waitForSelector('#champ-pin');
    await page.fill('#champ-pin', '4821');
    await page.click('#form-pin button');
    await page.waitForSelector('#btn-vue-fiche:not([hidden])');
    await page.click('#btn-vue-fiche');
    await page.waitForSelector('#fiche-saisie');
    await page.fill('#fiche-date', hier);
    await page.dispatchEvent('#fiche-date', 'change');
    await page.waitForSelector(`#fiche-mensuel tbody tr.choisi[data-jour="${hier}"]`);
    assert.equal(await page.inputValue('#saisie-mortChair'), '3', 'la saisie est rechargée');
    assert.match(await page.textContent('#saisie-etat'), /en attente d'envoi/);
    assert.deepEqual(await colonne(), ['40', '37', '37']);
    assert.equal(effectifsServeur(), avant);
    ok('page rechargée hors ligne : la saisie (3 morts) est toujours là, toujours en attente d\'envoi, effectifs recalculés');
} catch (e) {
    echec = e;
} finally {
    await navigateur?.close();
    arreter();
}
console.log(`\n${resultats.length} étape(s) réussie(s).`);
if (echec) { console.error(`\nÉCHEC : ${echec.message}`); process.exitCode = 1; }
