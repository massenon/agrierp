/**
 * CAISSE-1 (DV-32) + CAISSE-2 (DV-33) — TEST DE BOUT EN BOUT (Playwright + Chromium, lancé À LA MAIN) :
 *
 *   node tests/Js/e2e/appareil-recu.e2e.mjs            # depuis agrierp_laravel/, après `npm run build`
 *
 * A. Appareil PERSONNEL : PIN de 5 refusé (message français), PIN de 6 accepté ; « Déconnecter cet appareil » efface TOUT (IndexedDB, caches, marqueurs).
 * B. Appareil de l'ENTREPRISE (défaut) : PIN de 4 accepté ; une vente hors ligne reste sur l'appareil (même après rechargement) jusqu'à son envoi ;
 *    « Imprimer le reçu provisoire » : identifiant court + mention exacte, aucun numéro de facture ; après la synchronisation, plus de reçu provisoire.
 * Même sûreté que les autres e2e (php -S, base SQLITE TEMPORAIRE).
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
    \\App\\Models\\CompanySetting::current()->update(['company_name' => 'Ferme E2E', 'ifu' => '3202601234567']);   // MECEF_ACTIF=true + mode jamais réglé = passerelle de démonstration (FakeMecefGateway), aucun appel réel
    \\App\\Models\\Customer::create(['name' => 'Awa KPOGNON', 'phone' => '97000000', 'ifu' => '1234567890123', 'is_active' => true]);
    \\App\\Models\\TreasuryAccount::firstOrCreate(['type' => 'caisse'], ['label' => 'Caisse Principale', 'account_code' => '531', 'balance' => 0, 'is_active' => true]);
`]);
const produits = sql("select id||'|'||name||'|'||stock_qty from products where species_id is null and pricing_mode != 'quote' order by name limit 3").split('\n').map((l) => l.split('|'));
const serveur = spawn('php', ['-S', `127.0.0.1:${port}`, path.join(racine, 'vendor/laravel/framework/src/Illuminate/Foundation/resources/server.php')], { cwd: path.join(racine, 'public'), env, stdio: 'ignore' });
const arreter = () => { try { serveur.kill('SIGTERM'); } catch { /* déjà arrêté */ } };
process.on('exit', arreter);
for (let i = 0; i < 60; i++) { try { if ((await fetch(`${base}/up`)).ok) break; } catch { /* pas prêt */ } await new Promise((r) => setTimeout(r, 250)); }

let navigateur;
let echec = null;
try {
    navigateur = await chromium.launch();
    const nouveauContexte = async () => {
        const contexte = await navigateur.newContext({ viewport: { width: 1280, height: 900 }, deviceScaleFactor: 1, locale: 'fr-FR' });
        const page = await contexte.newPage();
        page.on('pageerror', (e) => console.log('  [erreur page]', e.message));
        await page.goto(`${base}/login`);
        await page.waitForLoadState('networkidle');
        await page.fill('#identifiant', 'caisse');
        await page.fill('#password', 'LogiAgriERP@2026');
        await Promise.all([page.waitForURL('**/dashboard', { timeout: 30000 }), page.click('[dusk=login-submit]')]);
        await page.goto(`${base}/mode-hors-ligne`);
        await page.waitForSelector('#hl-mdp');
        return { contexte, page };
    };
    const ouvrirCaisse = async (page, pin) => {
        await page.goto(`${base}/caisse-hors-ligne.html`);
        await page.waitForSelector('#champ-pin');
        await page.fill('#champ-pin', pin);
        await page.click('#form-pin button');
        await page.waitForSelector('#contenu:not([hidden])');
        await page.waitForFunction(() => /Synchronisé/.test(document.querySelector('#etat-synchro').textContent), null, { timeout: 30000 });
    };

    // ---------------------------------------------------------------- A. appareil PERSONNEL
    {
        const { page } = await nouveauContexte();
        assert.equal(await page.isChecked('#hl-type-entreprise'), true, 'l\'appareil de l\'entreprise est le défaut');
        await page.check('#hl-type-personnel');
        assert.match(await page.textContent('label[for=hl-pin]'), /PIN \(6 chiffres\)/);
        await page.fill('#hl-mdp', 'LogiAgriERP@2026');
        await page.fill('#hl-pin', '48215');
        await page.fill('#hl-pin2', '48215');
        await page.click('#hl-activer');
        await page.waitForFunction(() => /exactement 6 chiffres/.test(document.body.textContent));
        assert.equal(sql("select count(*) from personal_access_tokens where name like 'pwa-%'"), '0', 'aucun jeton créé sur un PIN refusé');
        await page.fill('#hl-pin', '482151');
        await page.fill('#hl-pin2', '482151');
        await page.click('#hl-activer');
        await page.waitForSelector('text=Appareil appairé', { timeout: 30000 });
        assert.match(await page.textContent('#hl-type-actif'), /appareil personnel/);
        ok('appareil personnel : PIN de 5 chiffres refusé (message français, aucun jeton), PIN de 6 accepté');

        await ouvrirCaisse(page, '482151');
        await page.click('#btn-deconnecter');
        await page.waitForSelector('#dlg-deconnexion[open]');
        assert.match(await page.textContent('#deco-texte'), /Appareil personnel : TOUTES les données hors ligne/);
        await page.click('#deco-confirmer');
        await page.waitForSelector('#ecran-inactif:not([hidden])');
        const reste = await page.evaluate(async () => ({
            bases: (await indexedDB.databases()).map((b) => b.name),
            caches: await caches.keys(),
            marqueurs: Object.keys(localStorage).filter((k) => /^agrierp_hors_ligne/.test(k)),
        }));
        assert.ok(!reste.bases.includes('agrierp_hors_ligne'), `IndexedDB effacée (reste : ${reste.bases})`);
        assert.deepEqual(reste.caches, [], 'caches du service worker effacés');
        assert.deepEqual(reste.marqueurs, [], 'marqueurs effacés');
        ok('appareil personnel : « Déconnecter cet appareil » efface le magasin chiffré, la clé, le jeton, les caches et les marqueurs');
        await page.context().close();
    }

    // ---------------------------------------------------------------- B. appareil de l'ENTREPRISE + reçu provisoire
    {
        const { contexte, page } = await nouveauContexte();
        await page.fill('#hl-mdp', 'LogiAgriERP@2026');
        await page.fill('#hl-pin', '4821');
        await page.fill('#hl-pin2', '4821');
        await page.click('#hl-activer');
        await page.waitForSelector('text=Appareil appairé', { timeout: 30000 });
        assert.match(await page.textContent('#hl-type-actif'), /appareil de l'entreprise/);
        ok('appareil de l\'entreprise (défaut) : PIN de 4 chiffres accepté');

        await ouvrirCaisse(page, '4821');
        await page.waitForFunction(() => document.querySelectorAll('#produits .produit').length > 0);
        await contexte.setOffline(true);
        await page.click(`#produits .produit[data-id="${produits[0][0]}"]`);
        await page.fill('#piece-qte', '2');
        await page.fill('#piece-montant', '11800');
        await page.click('#piece-ajouter');
        await page.fill('#recu', '15000');
        await page.click('#btn-valider');
        await page.waitForFunction(() => /Vente enregistrée sur cet appareil/.test(document.querySelector('#avis').textContent));
        await page.waitForSelector('#corps-ventes tr[data-statut="pending"] [data-recu]');
        const idVente = await page.getAttribute('#corps-ventes tr[data-statut="pending"]', 'data-id');
        await page.click('#corps-ventes tr[data-statut="pending"] [data-recu]');
        await page.waitForSelector('#dlg-recu[open] #recu-provisoire');
        const recu = (await page.textContent('#recu-contenu')).replace(/\s+/g, ' ');
        assert.match(recu, /Reçu provisoire/);
        assert.ok(recu.includes(`Vente n° ${idVente.slice(0, 8).toUpperCase()}`), 'identifiant court de la vente en majuscules');
        assert.ok(recu.includes('Facture n° attribué à la synchronisation.'), 'mention exacte');
        assert.ok(recu.includes('Ferme E2E') && recu.includes('Mode de règlement : Espèces') && recu.includes('Montant reçu :'));
        assert.ok(!/FA-|FV-/.test(recu), 'aucun numéro de facture légal');
        assert.equal(await page.textContent('#recu-entete'), 'Ferme E2E');
        await page.click('[data-fermer="dlg-recu"]');
        ok('vente hors ligne : « Imprimer le reçu provisoire » — identifiant court, mention exacte, entête de la ferme, aucun numéro de facture');

        // Les données restent sur l'appareil (entreprise) : rechargement hors ligne, la vente est toujours là, toujours à envoyer.
        await page.reload();
        await page.waitForSelector('#champ-pin');
        await page.fill('#champ-pin', '4821');
        await page.click('#form-pin button');
        await page.waitForSelector('#corps-ventes tr[data-statut="pending"]');
        assert.equal(sql('select count(*) from sales'), '0', 'le serveur n\'a rien reçu');
        await page.click('#btn-deconnecter');
        await page.waitForSelector('#dlg-deconnexion[open]');
        assert.doesNotMatch(await page.textContent('#deco-texte'), /Appareil personnel/);
        assert.match(await page.textContent('#deco-texte'), /ne sont pas encore envoyé/);
        await page.click('#dlg-deconnexion [data-fermer]').catch(() => page.keyboard.press('Escape'));
        ok('appareil de l\'entreprise : la vente reste sur l\'appareil jusqu\'à son envoi (même après rechargement), la déconnexion la protège');

        await contexte.setOffline(false);
        await page.click('#btn-synchroniser');
        await page.waitForFunction(() => document.querySelectorAll('#corps-ventes tr[data-statut="synced"]').length >= 1, null, { timeout: 40000 });
        assert.equal(sql('select count(*) from sales'), '1');
        assert.equal(await page.$('#corps-ventes [data-recu]'), null, 'après la synchronisation : plus de reçu provisoire');
        assert.match(await page.textContent('#corps-ventes tr[data-statut="synced"]'), /Facture numérotée par le serveur/);
        ok('après la synchronisation : le reçu n\'est plus provisoire (la facture porte son numéro au serveur, écran Facturation)');
    }
} catch (e) {
    echec = e;
} finally {
    await navigateur?.close();
    arreter();
}
console.log(`\n${resultats.length} étape(s) réussie(s).`);
if (echec) { console.error(`\nÉCHEC : ${echec.message}`); process.exitCode = 1; }
