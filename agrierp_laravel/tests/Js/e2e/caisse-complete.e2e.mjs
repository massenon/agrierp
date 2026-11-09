/**
 * PWA-1b — TEST DE BOUT EN BOUT de la CAISSE COMPLÈTE hors ligne (Playwright + Chromium, lancé À LA MAIN).
 *
 *   node tests/Js/e2e/caisse-complete.e2e.mjs            # depuis agrierp_laravel/
 *
 * Même sûreté que `hors-ligne.e2e.mjs` (php -S, base SQLITE TEMPORAIRE, refus de démarrer hors du dossier temporaire).
 * Scénario : appairage → caisse → tirage → réseau COUPÉ → « + » crée un client (nom, téléphone, IFU) → vente sur AVANCE de ce
 * client avec LIVRAISON FACTURÉE → rien côté serveur → réseau rétabli → synchronisation : le client est créé AVANT la vente (UUID du
 * navigateur), la vente porte les frais dans son total (`delivery_fee`, `delivery_in_total`) ; un client déjà connu du serveur est
 * FUSIONNÉ et la vente en file passe à la fiche du serveur ; rien n'est envoyé deux fois.
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
const mutation = process.env.E2E_MUTATION ?? '';
const capture = process.env.E2E_CAPTURE ?? path.join(dossier, 'caisse-complete.png');

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
assert.ok(produits.length >= 2, 'au moins deux produits vendables hors sujets vivants');

// MUTATION « html » : sw.js met en cache TOUTES les navigations (HTML authentifié compris). Le fichier du dépôt est modifié
// le temps du test (copie de sauvegarde, restauration garantie) ; le test DOIT alors échouer.
const swChemin = path.join(racine, 'public/sw.js');
const swOriginal = fs.readFileSync(swChemin, 'utf8');
const restaurer = () => { if (fs.readFileSync(swChemin, 'utf8') !== swOriginal) fs.writeFileSync(swChemin, swOriginal); };
if (mutation === 'html') {
    const cible = "fetch(request).catch(() =>\n                caches.match('/offline.html')";
    assert.ok(swOriginal.includes(cible), 'la mutation doit pouvoir s\'appliquer');
    fs.writeFileSync(swChemin, swOriginal.replace(cible, "fetch(request).then((rep) => { const c = rep.clone(); caches.open(CACHE_STATIQUE).then((k) => k.put(request, c)); return rep; }).catch(() =>\n                caches.match('/offline.html')"));
    for (const signal of ['exit', 'SIGINT', 'SIGTERM']) process.on(signal, () => { restaurer(); if (signal !== 'exit') process.exit(1); });
}

const serveur = spawn('php', ['-S', `127.0.0.1:${port}`, path.join(racine, 'vendor/laravel/framework/src/Illuminate/Foundation/resources/server.php')], { cwd: path.join(racine, 'public'), env, stdio: 'ignore' });
const arreter = () => { try { serveur.kill('SIGTERM'); } catch { /* déjà arrêté */ } };
process.on('exit', arreter);
for (let i = 0; i < 60; i++) { try { if ((await fetch(`${base}/up`)).ok) break; } catch { /* pas prêt */ } await new Promise((r) => setTimeout(r, 250)); }

let navigateur;
let echec = null;
try {
    navigateur = await chromium.launch();
    const contexte = await navigateur.newContext({ viewport: { width: 1280, height: 900 }, deviceScaleFactor: 1, locale: 'fr-FR' });
    const page = await contexte.newPage();
    page.on('pageerror', (e) => console.log('  [erreur page]', e.message));
    let jetonClair = null;
    contexte.on('request', (r) => { const a = r.headers()['authorization']; if (a && r.url().includes('/api/sync/')) jetonClair = a.replace('Bearer ', ''); });

    // --- 1. Connexion web (session Laravel) puis appairage ---
    await page.goto(`${base}/login`);
    await page.waitForLoadState('networkidle');
    await page.fill('#identifiant', 'caisse');
    await page.fill('#password', 'LogiAgriERP@2026');
    await Promise.all([page.waitForURL('**/dashboard', { timeout: 30000 }), page.click('[dusk=login-submit]')]);
    ok('connexion web (session Laravel) du compte « caisse »');

    await page.goto(`${base}/mode-hors-ligne`);
    await page.waitForSelector('#hl-mdp');
    await page.fill('#hl-mdp', 'LogiAgriERP@2026');
    await page.fill('#hl-pin', '4821');
    await page.fill('#hl-pin2', '4821');
    await page.click('#hl-activer');
    await page.waitForSelector('text=Appareil appairé', { timeout: 30000 });
    const nomAppareil = (await page.textContent('span.font-mono')).trim();
    assert.match(nomAppareil, /^pwa-[0-9a-f-]{36}$/);
    assert.equal(sql(`select count(*) from personal_access_tokens where name='${nomAppareil}'`), '1');
    ok(`appairage : jeton Sanctum « ${nomAppareil} » créé (un jeton, nommé pwa-<uuid>)`);
    assert.equal(await page.evaluate(() => document.querySelector('#hl-mdp')?.value ?? ''), '', 'le mot de passe est effacé de la page');

    // --- 2. Caisse hors ligne, première synchronisation ---
    await page.goto(`${base}/caisse-hors-ligne.html`);
    await page.waitForSelector('#champ-pin');
    await page.fill('#champ-pin', '0000');
    await page.click('#form-pin button');
    await page.waitForFunction(() => /PIN incorrect/.test(document.querySelector('#erreur-pin').textContent));
    ok('un mauvais PIN est refusé (compteur d\'échecs)');
    await page.fill('#champ-pin', '4821');
    await page.click('#form-pin button');
    await page.waitForSelector('#contenu:not([hidden])');
    await page.waitForFunction(() => document.querySelectorAll('#produits .produit').length > 0, null, { timeout: 30000 });
    await page.waitForFunction(() => /Synchronisé/.test(document.querySelector('#etat-synchro').textContent), null, { timeout: 30000 });
    ok('tirage initial : le catalogue est copié, état « Synchronisé »');

    // --- 3. Hors ligne : client créé par « + », vente sur avance avec livraison facturée ---
    await contexte.setOffline(true);
    await page.waitForFunction(() => document.querySelectorAll('#produits .produit').length > 0);

    const idProduit = produits[0][0];
    const vendre = async (id, qte, montant) => {
        await page.click(`#produits .produit[data-id="${id}"]`);
        await page.fill('#piece-qte', String(qte));
        await page.fill('#piece-montant', String(montant));
        await page.click('#piece-ajouter');
    };
    // Une vente sur avance SANS client : refus, avec la phrase de la caisse web.
    await vendre(idProduit, 1, 5000);
    await page.selectOption('#mode', 'avance');
    await page.click('#btn-valider');
    await page.waitForFunction(() => document.querySelector('#erreur-client').textContent !== '');
    assert.match(await page.textContent('#erreur-client'), /Une vente sur avance exige un client : choisissez-le dans la liste ou créez-le avec le bouton « \+ »\./);
    ok('vente sur avance sans client : refusée avec les mots de la caisse web');

    // Le bouton « + » : refus de saisie puis création.
    await page.click('#btn-nouveau-client');
    await page.waitForSelector('#dlg-client[open]');
    await page.click('#client-enregistrer');
    await page.waitForFunction(() => document.querySelector('#erreur-client-nom').textContent !== '');
    assert.equal(await page.textContent('#erreur-client-nom'), 'Le champ nom est obligatoire.');
    await page.fill('#client-nom', 'ADJOVI Clarisse');
    await page.fill('#client-tel', '0196001122');
    await page.fill('#client-ifu', '3201234567890');
    await page.click('#client-enregistrer');
    await page.waitForFunction(() => /Client ajouté sur cet appareil/.test(document.querySelector('#avis').textContent));
    assert.equal(await page.evaluate(() => document.querySelector('#client').selectedOptions[0].textContent), 'ADJOVI Clarisse', 'le nouveau client est sélectionné');
    assert.equal(sql('select count(*) from customers'), '1', 'rien côté serveur tant que le réseau est coupé');
    ok('client créé hors ligne par « + » : sélectionné, enregistré sur l\'appareil, serveur intact');

    // Livraison facturée : 2 500 FCFA ajoutés au total.
    await page.click('#btn-livraison');
    await page.waitForSelector('#dlg-livraison[open]');
    await page.check('#liv-concernee');
    await page.selectOption('#liv-mode', 'facturee');
    await page.fill('#liv-frais', '2500');
    await page.fill('#liv-adresse', 'Pobè, route de Kétou');
    await page.fill('#liv-contact', '0197000000');
    await page.click('#liv-valider');
    await page.waitForFunction(() => !document.querySelector('#ligne-livraison').hidden);
    assert.equal((await page.textContent('#total')).replace(/\s/g, ' '), '7 500 FCFA'.replace(/\s/g, ' '), 'total = 5 000 + 2 500');
    assert.match(await page.textContent('#frais-livraison'), /2\s500 FCFA/);
    await page.click('#btn-valider');
    await page.waitForFunction(() => /Vente enregistrée sur cet appareil \(7\s500 FCFA\)/.test(document.querySelector('#avis').textContent));
    assert.equal(sql('select count(*) from sales'), '0');
    await page.screenshot({ path: capture, fullPage: false });
    console.log(`  capture : ${capture}`);
    ok('livraison facturée : frais ajoutés au total (7 500 FCFA), vente sur avance du client créé enregistrée hors ligne');

    const brut = await page.evaluate(async () => {
        const db = await new Promise((ok2, ko) => { const r = indexedDB.open('agrierp_hors_ligne'); r.onsuccess = () => ok2(r.result); r.onerror = () => ko(r.error); });
        const sortie = {};
        for (const n of db.objectStoreNames) sortie[n] = await new Promise((ok2) => { const q = db.transaction(n).objectStore(n).getAll(); q.onsuccess = () => ok2(q.result); });
        db.close();
        return JSON.stringify(sortie);
    });
    for (const secret of ['ADJOVI', '0196001122', '3201234567890', 'Pobè, route de Kétou']) assert.ok(!brut.includes(secret), `« ${secret} » ne doit pas être lisible dans IndexedDB`);
    ok('IndexedDB : le client créé et l\'adresse de livraison sont chiffrés (aucun clair)');

    // --- 4. Retour du réseau : client AVANT la vente ---
    await contexte.setOffline(false);
    await page.waitForFunction(() => /Synchronisé/.test(document.querySelector('#etat-synchro').textContent), null, { timeout: 40000 });
    assert.equal(sql("select name||'|'||phone||'|'||ifu from customers where name='ADJOVI Clarisse'"), 'ADJOVI Clarisse|0196001122|3201234567890');
    const v = sql("select payment_mode||'|'||total||'|'||delivery_mode||'|'||delivery_fee||'|'||delivery_in_total||'|'||delivery_address||'|'||delivery_contact from sales");
    const [mode, total, modeLiv, frais, drapeau, adresse, contact] = v.split('|');
    assert.deepEqual([mode, Number(total), modeLiv, Number(frais), drapeau, adresse, contact], ['avance', 7500, 'facturee', 2500, '1', 'Pobè, route de Kétou', '0197000000'], 'la vente porte la livraison facturée');
    assert.equal(sql("select count(*) from sales where customer_id=(select id from customers where name='ADJOVI Clarisse')"), '1', 'la vente est celle du client créé hors ligne');
    assert.equal(sql("select count(*) from customers where name='ADJOVI Clarisse'"), '1');
    ok('reconnexion : client créé AVANT sa vente (UUID du navigateur), vente sur avance avec livraison facturée dans son total, une seule fois');

    // --- 5. Client déjà connu du serveur : fusion, la vente en file passe à la fiche du serveur ---
    await contexte.setOffline(true);
    await page.click('#btn-nouveau-client');
    await page.fill('#client-nom', 'awa kpognon');
    await page.fill('#client-tel', '97000000');
    await page.fill('#client-ifu', '');
    await page.click('#client-enregistrer');
    await page.waitForFunction(() => /Client ajouté sur cet appareil/.test(document.querySelector('#avis').textContent));
    await vendre(idProduit, 1, 3000);
    await page.selectOption('#mode', 'credit');
    await page.click('#btn-valider');
    await page.waitForFunction(() => document.querySelectorAll('#corps-ventes tr').length === 2);
    await contexte.setOffline(false);
    await page.waitForFunction(() => /Synchronisé/.test(document.querySelector('#etat-synchro').textContent), null, { timeout: 40000 });
    assert.equal(sql("select count(*) from customers where phone='97000000'"), '1', 'fusion : aucun doublon de la fiche Awa KPOGNON');
    assert.equal(sql("select count(*) from sales where payment_mode='credit' and customer_id=(select id from customers where phone='97000000')"), '1', 'la vente est rattachée à la fiche du serveur');
    assert.equal(sql("select count(*) from sales"), '2');
    ok('client déjà connu du serveur : fusionné (une seule fiche), la vente à crédit en file est rattachée à la fiche du serveur');

} catch (e) {
    echec = e;
} finally {
    await navigateur?.close();
    arreter();
    restaurer();
}
console.log(`\n${resultats.length} étape(s) réussie(s).`);
if (echec) { console.error(`\nÉCHEC : ${echec.message}`); process.exitCode = 1; }
