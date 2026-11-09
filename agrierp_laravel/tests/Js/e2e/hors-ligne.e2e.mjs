/**
 * PWA-1 — TEST DE BOUT EN BOUT (Playwright + Chromium, lancé À LA MAIN, jamais par `node --test tests/Js/*.test.mjs`).
 *
 *   node tests/Js/e2e/hors-ligne.e2e.mjs            # depuis agrierp_laravel/
 *   E2E_CAPTURE=/chemin/caisse.png node …           # chemin de la capture d'écran (deviceScaleFactor 1)
 *   E2E_MUTATION=html node …                          # contrôle par MUTATION : sw.js « cache toutes les navigations » (doit ÉCHOUER)
 *   (l'idempotence se mute côté serveur : retirer `unique:sales,id` de SyncController::pushSales, voir CLAUDE.md « PWA-1 »)
 *
 * SÛRETÉ : le serveur est `php -S` (le routeur de `php artisan serve`) sur un port libre, avec une base SQLITE TEMPORAIRE
 * dans le dossier temporaire du système. ⚠️ `php artisan serve` IGNORE les variables d'environnement exportées et relit
 * `.env` (MySQL de développement !) : on lance donc `php -S` directement, qui hérite de l'environnement, où les variables
 * réelles priment sur `.env`. Le script REFUSE de démarrer si la base n'est pas dans le dossier temporaire.
 *
 * Scénario : connexion web → « Mode hors ligne » (appairage, PIN) → caisse hors ligne → première synchro (tirage) →
 * `setOffline(true)` → rechargement de la page depuis le service worker → 2 ventes (dont une facture normalisée) +
 * 1 refus de saisie → `setOffline(false)` → synchronisation AUTOMATIQUE → la base contient chaque vente UNE fois ;
 * réponse perdue après traitement serveur → renvoi → toujours UNE fois ; jeton révoqué → 401 → suspension ; aucun HTML
 * authentifié ni jeton dans les caches / stockages ; CONF-3 : catalogue vieilli à 1, 4 puis 8 jours (rien / bandeau /
 * confirmation avant chaque vente, jamais un refus) ; déconnexion = purge.
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
const capture = process.env.E2E_CAPTURE ?? path.join(dossier, 'caisse-hors-ligne.png');

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

    // Service worker actif et enveloppe en cache.
    await page.evaluate(() => navigator.serviceWorker.ready);
    await page.reload();
    await page.waitForSelector('#champ-pin');
    const controle = await page.evaluate(() => Boolean(navigator.serviceWorker.controller));
    assert.ok(controle, 'la page est contrôlée par le service worker');
    const caches1 = await page.evaluate(async () => { const r = {}; for (const n of await caches.keys()) r[n] = (await (await caches.open(n)).keys()).map((q) => new URL(q.url).pathname); return r; });
    const tous = Object.values(caches1).flat();
    assert.ok(tous.includes('/caisse-hors-ligne.html') && tous.includes('/assets/hors-ligne/caisse.js'), 'enveloppe de la caisse en cache');
    ok('service worker : enveloppe statique de la caisse en cache');

    // --- 3. Hors ligne : rechargement depuis le cache, 2 ventes ---
    await page.fill('#champ-pin', '4821');
    await page.click('#form-pin button');
    await page.waitForSelector('#contenu:not([hidden])');
    await contexte.setOffline(true);
    await page.reload();                                                    // servi par le service worker, réseau coupé
    await page.waitForSelector('#champ-pin');
    await page.fill('#champ-pin', '4821');
    await page.click('#form-pin button');
    await page.waitForSelector('#contenu:not([hidden])');
    await page.waitForFunction(() => document.querySelectorAll('#produits .produit').length > 0);
    await page.waitForFunction(() => /^Hors ligne/.test(document.querySelector('#etat-synchro').textContent), null, { timeout: 15000 });
    assert.match(await page.getAttribute('#etat-synchro', 'class'), /neutre/, 'hors ligne n\'est pas une erreur rouge');
    ok('hors ligne : la page de caisse se charge depuis le service worker, catalogue lu dans IndexedDB');

    const vendre = async (id, qte, montant) => {
        await page.click(`#produits .produit[data-id="${id}"]`);
        await page.fill('#piece-qte', String(qte));
        await page.fill('#piece-montant', String(montant));
        await page.click('#piece-ajouter');
    };
    // Vente 1 : espèces, facture simple.
    await vendre(produits[0][0], 2, 11800);
    await page.fill('#recu', '15000');
    await page.click('#btn-valider');
    await page.waitForFunction(() => /Vente enregistrée sur cet appareil/.test(document.querySelector('#avis').textContent));
    // Refus de saisie : crédit sans client — les mêmes mots que le web.
    await vendre(produits[1][0], 1, 5000);
    await page.selectOption('#mode', 'credit');
    await page.click('#btn-valider');
    await page.waitForFunction(() => document.querySelector('#erreur-client').textContent !== '');
    assert.match(await page.textContent('#erreur-client'), /Une vente à crédit exige un client : choisissez-le dans la liste ou créez-le avec le bouton « \+ »\./);
    await page.selectOption('#mode', 'especes');
    await page.click('#btn-valider');       // 5 000 espèces sans montant reçu : encaisse le total
    await page.waitForFunction(() => document.querySelector('#erreur-client').textContent === '');
    // Vente 3 : facture normalisée, client avec IFU.
    await page.waitForFunction(() => document.querySelectorAll('#corps-ventes tr').length === 2);
    await vendre(produits[1][0], 1, 4000);
    await page.selectOption('#client', { label: 'Awa KPOGNON' });
    await page.selectOption('#facture-type', 'normalisee');
    await page.waitForSelector('#dlg-facture[open]');
    await page.fill('#facture-nom', '');
    await page.click('#facture-valider');
    await page.waitForFunction(() => document.querySelector('#erreur-facture-nom').textContent !== '');
    assert.match(await page.textContent('#erreur-facture-nom'), /Le nom et prénom du client sont obligatoires/);
    await page.fill('#facture-nom', 'KPOGNON Séraphin');
    await page.fill('#facture-ifu', '1234567890123');
    await page.selectOption('#facture-aib', '1%');
    await page.click('#facture-valider');
    await page.click('#btn-valider');
    await page.waitForFunction(() => document.querySelectorAll('#corps-ventes tr').length === 3);
    await page.waitForFunction(() => /En attente \(3\)|Hors ligne — 3 en attente/.test(document.querySelector('#etat-synchro').textContent));
    assert.equal(sql('select count(*) from sales'), '0', 'aucune vente côté serveur tant que le réseau est coupé');
    ok('hors ligne : 3 ventes enregistrées sur l\'appareil (une facture normalisée), compteur « 3 en attente », serveur intact');
    await page.screenshot({ path: capture, fullPage: false });
    console.log(`  capture : ${capture}`);

    // Clé de chiffrement : aucune donnée de la ferme lisible dans IndexedDB.
    const brut = await page.evaluate(async () => {
        const db = await new Promise((ok2, ko) => { const r = indexedDB.open('agrierp_hors_ligne'); r.onsuccess = () => ok2(r.result); r.onerror = () => ko(r.error); });
        const sortie = {};
        for (const n of db.objectStoreNames) sortie[n] = await new Promise((ok2) => { const q = db.transaction(n).objectStore(n).getAll(); q.onsuccess = () => ok2(q.result); });
        db.close();
        return JSON.stringify(sortie);
    });
    for (const secret of ['KPOGNON', 'Awa KPOGNON', produits[0][1], '11800', '1234567890123']) assert.ok(!brut.includes(secret), `« ${secret} » ne doit pas être lisible dans IndexedDB`);
    ok('IndexedDB : aucun nom de produit, de client ni montant en clair');

    // --- 4. Retour du réseau : synchronisation AUTOMATIQUE ---
    await contexte.setOffline(false);
    await page.waitForFunction(() => /Synchronisé/.test(document.querySelector('#etat-synchro').textContent), null, { timeout: 40000 });
    assert.equal(sql('select count(*) from sales'), '3');
    assert.equal(sql('select count(distinct id) from sales'), '3');
    const ventes = sql("select total||'|'||payment_mode||'|'||facture_type||'|'||ifnull(client_nom_facture,'')||'|'||ifnull(aib_taux,'') from sales order by sold_at").split('\n');
    assert.deepEqual(ventes, ['11800|especes|simple||', '5000|especes|simple||', '4000|especes|normalisee|KPOGNON Séraphin|1%']);
    assert.equal(sql("select count(*) from sales where mecef_status='transmise'"), '1', 'la normalisée est transmise par le serveur, la simple jamais');
    assert.equal(sql('select count(*) from accounting_entries where source_type=\'sale\''), '3');
    const stock = sql(`select stock_qty from products where id='${produits[0][0]}'`);
    assert.equal(Number(stock), Number(produits[0][2]) - 2, 'le stock a été décrémenté par le serveur');
    assert.equal(sql(`select count(*) from sales where id in (${(await page.evaluate(() => [...document.querySelectorAll('#corps-ventes tr')].map((t) => `'${t.dataset.id}'`)))?.join(',')})`), '3', 'les UUID du navigateur sont ceux du serveur');
    await page.waitForFunction(() => [...document.querySelectorAll('#corps-ventes tr')].every((t) => t.dataset.statut === 'synced'));
    ok('reconnexion : synchronisation automatique, 3 ventes en base UNE fois (UUID du navigateur), stock et comptabilité faits par le serveur, normalisée transmise (MeCeF)');

    // --- 5. Réponse perdue après traitement serveur : renvoi sans doublon ---
    await vendre(produits[0][0], 1, 6000);
    let reponseCoupee;
    const coupee = new Promise((r) => { reponseCoupee = r; });
    await page.route('**/api/sync/push', async (route) => { await route.fetch(); await route.abort('failed'); reponseCoupee(); });   // le serveur TRAITE, la réponse est perdue
    await page.click('#btn-valider');
    await coupee;
    await page.waitForFunction(() => /Hors ligne|En attente/.test(document.querySelector('#etat-synchro').textContent), null, { timeout: 30000 });
    assert.equal(sql('select count(*) from sales'), '4', 'le serveur a bien traité la vente');
    assert.ok((await page.evaluate(() => [...document.querySelectorAll('#corps-ventes tr')].some((t) => t.dataset.statut === 'pending'))), 'sans accusé : jamais « synced »');
    await page.unroute('**/api/sync/push');
    await page.click('#btn-synchroniser');
    await page.waitForFunction(() => /Synchronisé/.test(document.querySelector('#etat-synchro').textContent), null, { timeout: 30000 });
    assert.equal(sql('select count(*) from sales'), '4', 'toujours UNE vente par UUID');
    assert.equal(sql('select count(distinct id) from sales'), '4');
    ok('réponse perdue puis renvoi : UNE vente par UUID côté serveur, file « synced »');

    // --- 6. Refus motivé du serveur : le client de la vente a disparu du serveur (vente à crédit) ---
    await vendre(produits[1][0], 1, 2500);
    await page.selectOption('#client', { label: 'Awa KPOGNON' });
    await page.selectOption('#mode', 'credit');
    await contexte.setOffline(true);
    await page.click('#btn-valider');
    await page.waitForFunction(() => document.querySelectorAll('#corps-ventes tr').length === 5);
    sql('delete from customers');                    // supprimé au bureau pendant ce temps
    const avant = sql('select count(*) from sales');
    await contexte.setOffline(false);
    await page.waitForFunction(() => /Refus \(1\)/.test(document.querySelector('#etat-synchro').textContent), null, { timeout: 40000 });
    assert.equal(sql('select count(*) from sales'), avant, 'la vente refusée n\'est PAS écrite');
    const refus = await page.evaluate(() => { const t = document.querySelector('#corps-ventes tr[data-statut=conflict]'); return { motif: t.children[3].textContent, boutons: [...t.querySelectorAll('button')].map((b) => b.textContent) }; });
    assert.match(refus.motif, /Client inconnu du serveur/);
    assert.deepEqual(refus.boutons, ['Remettre en file', 'Abandonner']);
    assert.match(await page.getAttribute('#etat-synchro', 'class'), /erreur/);
    ok('refus du serveur : état « Refus (1) », motif français affiché, « Remettre en file » / « Abandonner » proposés, vente jamais perdue ni écrite');

    // --- 7. Jeton révoqué (401) : suspension, ventes conservées ---
    sql("delete from personal_access_tokens where name like 'pwa-%'");   // l'administrateur révoque l'appareil (Postes & Appairage)
    await page.selectOption('#mode', 'especes');
    await vendre(produits[0][0], 1, 3000);
    await page.click('#btn-valider');
    await page.waitForFunction(() => /Reconnexion requise/.test(document.querySelector('#etat-synchro').textContent), null, { timeout: 30000 });
    assert.match(await page.textContent('#avis'), /reconnectez-vous/);
    const st = await page.evaluate(() => [...document.querySelectorAll('#corps-ventes tr')].map((t) => t.dataset.statut));
    assert.ok(st.includes('pending'), `la vente reste sur l'appareil (statuts : ${st})`);
    ok('jeton révoqué : 401, synchronisation suspendue, « Reconnexion requise », vente conservée');

    // --- 8. Aucun HTML authentifié ni jeton dans les caches et stockages ---
    await page.goto(`${base}/dashboard`).catch(() => {});
    const inspection = await page.evaluate(async () => {
        const sortie = { caches: [], html: [], ls: JSON.stringify({ ...localStorage }), ss: JSON.stringify({ ...sessionStorage }) };
        for (const n of await caches.keys()) {
            const c = await caches.open(n);
            for (const q of await c.keys()) {
                const r = await c.match(q); const t = (r.headers.get('content-type') || '');
                sortie.caches.push(new URL(q.url).pathname);
                if (/html/.test(t)) sortie.html.push(new URL(q.url).pathname);
            }
        }
        return sortie;
    });
    assert.deepEqual(inspection.html.sort(), ['/caisse-hors-ligne.html', '/offline.html'], 'seules les deux pages statiques sont du HTML en cache');
    assert.ok(!inspection.caches.some((p) => /dashboard|livewire|api|mode-hors-ligne|mon-profil/.test(p)), 'aucune page authentifiée, aucune API en cache');
    assert.ok(jetonClair, 'jeton observé dans une requête');
    for (const [nom, contenu] of [['localStorage', inspection.ls], ['sessionStorage', inspection.ss], ['IndexedDB', brut]]) assert.ok(!contenu.includes(jetonClair), `le jeton n'est pas en clair dans ${nom}`);
    ok('caches : seulement les 2 pages HTML statiques ; jeton jamais en clair (localStorage, sessionStorage, IndexedDB, caches)');

    // --- 8b. CONF-3 (DV-21) : prix périmés — 4 jours = bandeau d'avertissement ; 8 jours = confirmation avant CHAQUE vente ---
    // L'âge se lit sur le curseur du dernier tirage RÉUSSI gardé en IndexedDB : on le vieillit à la main, réseau coupé (sinon la
    // synchro de l'ouverture re-tirerait le catalogue et remettrait l'âge à zéro).
    const vieillirLeTirage = async (jours) => {
        await page.evaluate(async (j) => {
            const db = await new Promise((ok2, ko) => { const r = indexedDB.open('agrierp_hors_ligne'); r.onsuccess = () => ok2(r.result); r.onerror = () => ko(r.error); });
            const tx = db.transaction('meta', 'readwrite');
            tx.objectStore('meta').put({ cle: 'curseur', valeur: new Date(Date.now() - j * 86_400_000).toISOString() });
            tx.objectStore('meta').put({ cle: 'decalage_horloge_ms', valeur: 0 });
            await new Promise((ok2) => { tx.oncomplete = ok2; });
            db.close();
        }, jours);
        await contexte.setOffline(true);
        await page.reload();
        await page.fill('#champ-pin', '4821');
        await page.click('#form-pin button');
        await page.waitForSelector('#contenu:not([hidden])');
        await page.waitForFunction(() => document.querySelectorAll('#produits .produit').length > 0);
    };
    const ventesServeurAvant = sql('select count(*) from sales');
    const ventesAffichees = () => page.evaluate(() => document.querySelectorAll('#corps-ventes tr').length);
    await page.goto(`${base}/caisse-hors-ligne.html`);
    await page.fill('#champ-pin', '4821');
    await page.click('#form-pin button');
    await page.waitForSelector('#contenu:not([hidden])');

    await vieillirLeTirage(1);
    assert.equal(await page.isHidden('#bandeau-prix'), true, 'catalogue d\'hier : aucun bandeau, aucun « 0 jour »');

    await vieillirLeTirage(4);
    await page.waitForSelector('#bandeau-prix:not([hidden])');
    assert.equal((await page.textContent('#bandeau-prix')).trim(), 'Prix tirés il y a 4 jours : reconnectez-vous pour les actualiser.');
    assert.equal(await page.getAttribute('#bandeau-prix', 'data-niveau'), 'avertissement');
    const avant4 = await ventesAffichees();
    await vendre(produits[0][0], 1, 3000);
    await page.click('#btn-valider');
    await page.waitForFunction((n) => document.querySelectorAll('#corps-ventes tr').length === n + 1, avant4);
    assert.equal(await page.evaluate(() => document.querySelector('#dlg-prix-perimes').open), false, 'à 4 jours, aucune confirmation : l\'avertissement ne bloque jamais');

    await vieillirLeTirage(8);
    await page.waitForSelector('#bandeau-prix:not([hidden])');
    assert.match(await page.textContent('#bandeau-prix'), /^Attention : les prix datent de 8 jours et peuvent être périmés\./);
    assert.equal(await page.getAttribute('#bandeau-prix', 'data-niveau'), 'confirmation');
    const avant8 = await ventesAffichees();
    await vendre(produits[0][0], 1, 3000);
    await page.click('#btn-valider');
    await page.waitForSelector('#dlg-prix-perimes[open]');
    assert.equal((await page.textContent('#prix-perimes-texte')).trim(), 'Les prix datent de 8 jours et peuvent être périmés. Confirmer la vente ?');
    await page.click('#prix-perimes-annuler');
    await page.waitForFunction(() => !document.querySelector('#dlg-prix-perimes').open);
    assert.equal(await ventesAffichees(), avant8, 'Annuler : aucune vente enregistrée');
    assert.equal(await page.evaluate(() => document.querySelectorAll('#corps-panier tr').length), 1, 'Annuler : le panier est gardé');
    await page.click('#btn-valider');
    await page.waitForSelector('#dlg-prix-perimes[open]');
    await page.click('#prix-perimes-confirmer');
    await page.waitForFunction((n) => document.querySelectorAll('#corps-ventes tr').length === n + 1, avant8);
    await vendre(produits[0][0], 1, 3000);
    await page.click('#btn-valider');
    await page.waitForSelector('#dlg-prix-perimes[open]');
    await page.click('#prix-perimes-confirmer');
    await page.waitForFunction((n) => document.querySelectorAll('#corps-ventes tr').length === n + 2, avant8);
    assert.equal(sql('select count(*) from sales'), ventesServeurAvant, 'le serveur n\'a rien reçu : réseau coupé, la confirmation ne remplace pas la synchronisation');
    await contexte.setOffline(false);
    ok('prix périmés (CONF-3) : 1 jour = rien ; 4 jours = bandeau sans blocage ; 8 jours = confirmation avant CHAQUE vente (Annuler garde le panier, Confirmer enregistre), jamais un refus');

    // --- 9. Déconnexion = purge ---
    await page.goto(`${base}/caisse-hors-ligne.html`);
    await page.fill('#champ-pin', '4821');
    await page.click('#form-pin button');
    await page.waitForSelector('#contenu:not([hidden])');
    await page.click('#btn-deconnecter');
    await page.waitForSelector('#dlg-deconnexion[open]');
    await page.click('#deco-confirmer');
    await page.waitForFunction(() => document.querySelector('#deco-erreur').textContent !== '');
    assert.match(await page.textContent('#deco-erreur'), /Saisissez le nombre exact d'éléments à abandonner/);
    const n = await page.evaluate(() => [...document.querySelectorAll('#corps-ventes tr')].filter((t) => t.dataset.statut !== 'synced').length);
    await page.fill('#deco-n', String(n));
    await page.click('#deco-confirmer');
    await page.waitForSelector('#ecran-inactif:not([hidden])');
    const apres = await page.evaluate(async () => ({ dbs: (await indexedDB.databases()).map((d) => d.name), caches: await caches.keys(), marqueur: localStorage.getItem('agrierp_hors_ligne_active') }));
    assert.deepEqual(apres.dbs.filter((x) => x === 'agrierp_hors_ligne'), []);
    assert.equal(apres.marqueur, null);
    ok(`déconnexion refusée sans le nombre exact (${n}), puis IndexedDB + caches + marqueurs effacés`);
} catch (e) {
    echec = e;
} finally {
    await navigateur?.close();
    arreter();
    restaurer();
}
console.log(`\n${resultats.length} étape(s) réussie(s).`);
if (echec) { console.error(`\nÉCHEC : ${echec.message}`); process.exitCode = 1; }
