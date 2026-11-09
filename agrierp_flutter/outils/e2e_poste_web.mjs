/**
 * PWA-2 — PREUVE DANS CHROMIUM du poste Flutter compilé pour le web (Playwright, lancé À LA MAIN, jamais par `flutter test`).
 *
 *   # 1. construire le poste et le déposer dans agrierp_laravel/public/poste/ (dossier ignoré par git)
 *   agrierp_flutter/outils/construire_poste_web.sh
 *   # 2. lancer le scénario (Node 22 + Playwright + Chromium préinstallés ; NODE_PATH ou /opt/node22/lib/node_modules)
 *   node agrierp_flutter/outils/e2e_poste_web.mjs
 *
 *   Variables : E2E_CAPTURES=<dossier des captures> (défaut : dossier temporaire), AGRIERP_LARAVEL=<chemin de agrierp_laravel>,
 *   E2E_MODULES=<chemin de node_modules contenant playwright>.
 *
 * SÛRETÉ : serveur `php -S` (routeur de Laravel) sur un port libre, base SQLITE TEMPORAIRE dans le dossier temporaire du
 * système (le script REFUSE toute autre base ; jamais le `.env`, jamais MySQL). ⚠️ `php artisan serve` ignore les variables
 * exportées : on lance `php -S` directement. Le serveur sert LE MÊME `/poste/` que la production (même origine, aucun CORS).
 *
 * Scénario : démarrage à froid → connexion → PIN → tirage complet → service worker actif → RECHARGEMENT HORS LIGNE (le critère
 * de réussite du socle) → saisie d'un fournisseur hors ligne → reconnexion → synchronisation unique (une ligne côté serveur)
 * → fermeture et réouverture du navigateur (données conservées) → démarrage hors ligne à froid. Mesures imprimées en JSON.
 *
 * Flutter dessine dans un canvas : le script active l'arbre de sémantique (`flt-semantics-placeholder`) pour LIRE les textes ;
 * les clics se font à coordonnées fixes (fenêtre 1280×900, deviceScaleFactor 1) et attendent après chaque focus (une saisie
 * immédiate perd le premier caractère).
 */
import { createRequire } from 'node:module';
import { spawn, execFileSync } from 'node:child_process';
import net from 'node:net';
import os from 'node:os';
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

const require = createRequire((process.env.E2E_MODULES ?? '/opt/node22/lib/node_modules') + '/');
const { chromium } = require('playwright');

const ici = path.dirname(fileURLToPath(import.meta.url));
const laravel = path.resolve(process.env.AGRIERP_LARAVEL ?? path.join(ici, '../../agrierp_laravel'));
assert.ok(fs.existsSync(path.join(laravel, 'public/poste/index.html')), 'public/poste/ absent : lancer outils/construire_poste_web.sh');

const dossier = fs.mkdtempSync(path.join(os.tmpdir(), 'agrierp-poste-e2e-'));
const captures = process.env.E2E_CAPTURES ?? dossier;
fs.mkdirSync(captures, { recursive: true });
const db = path.join(dossier, 'e2e.sqlite');
assert.ok(db.startsWith(os.tmpdir()), 'la base de test doit être dans le dossier temporaire');
fs.writeFileSync(db, '');

const libre = () => new Promise((ok) => { const s = net.createServer(); s.listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => ok(p)); }); });
const port = await libre();
const base = `http://127.0.0.1:${port}`;
const env = { ...process.env, DB_CONNECTION: 'sqlite', DB_DATABASE: db, DB_URL: '', CACHE_STORE: 'file', SESSION_DRIVER: 'file', QUEUE_CONNECTION: 'sync', MAIL_MAILER: 'log', APP_ENV: 'local', APP_DEBUG: 'false', APP_URL: base, PHP_CLI_SERVER_WORKERS: '4' };
const php = (args) => execFileSync('php', args, { cwd: laravel, env, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
const sql = (requete) => execFileSync('php', ['-r', "$p = new PDO('sqlite:'.$argv[1]); $p->setAttribute(PDO::ATTR_TIMEOUT, 10); $s = $p->query($argv[2]); if ($s && $s->columnCount()) { foreach ($s->fetchAll(PDO::FETCH_NUM) as $r) { echo implode('|', $r).\"\\n\"; } }", db, requete], { encoding: 'utf8' }).trim();

const mesures = {};
const ok = (nom) => console.log(`  ✔ ${nom}`);
const pause = (ms) => new Promise((r) => setTimeout(r, ms));

console.log(`Base temporaire : ${db}\nServeur : ${base}`);
if (process.env.E2E_BASE_PRETE) {
  // Gain de temps (la graine de démonstration prend plusieurs minutes) : une COPIE d'une base déjà semée, jamais l'original.
  assert.ok(path.resolve(process.env.E2E_BASE_PRETE).startsWith(os.tmpdir()), 'la base prête doit être dans le dossier temporaire');
  fs.copyFileSync(process.env.E2E_BASE_PRETE, db);
} else {
  php(['artisan', 'migrate:fresh', '--seed', '--force']);
  php(['artisan', 'db:seed', '--class=DemoDataSeeder', '--force']);
}

const serveur = spawn('php', ['-S', `127.0.0.1:${port}`, path.join(laravel, 'vendor/laravel/framework/src/Illuminate/Foundation/resources/server.php')], { cwd: path.join(laravel, 'public'), env, stdio: 'ignore' });
const arreter = () => { try { serveur.kill('SIGTERM'); } catch { /* déjà arrêté */ } };
process.on('exit', arreter);
for (let i = 0; i < 60; i++) { try { if ((await fetch(`${base}/up`)).ok) break; } catch { /* pas prêt */ } await pause(250); }

const profil = path.join(dossier, 'profil');
let contexteHorsLigne = false;
const NOM = 'Fournisseur Hors Ligne E2E';
let contexte;
let page;
let echec = null;
let pulls = 0;

const ouvrir = async (horsLigne = false) => {
  contexte = await chromium.launchPersistentContext(profil, { headless: true, args: ['--no-sandbox'], viewport: { width: 1280, height: 900 }, deviceScaleFactor: 1, locale: 'fr-FR', timezoneId: 'Africa/Porto-Novo' });
  contexteHorsLigne = horsLigne;
  if (horsLigne) await contexte.setOffline(true);
  const page = contexte.pages()[0] ?? await contexte.newPage();
  page.on('pageerror', (e) => console.log('  [erreur page]', e.message.slice(0, 200)));
  if (process.env.E2E_DEBUG) page.on('console', (m) => console.log('  [console]', m.type(), m.text().slice(0, 300)));
  page.on('requestfailed', (r) => { if (!contexteHorsLigne) console.log('  [requête échouée]', r.url().slice(0, 120), r.failure()?.errorText); });
  return page;
};
const textes = (page) => page.evaluate(() => [...document.querySelectorAll('flt-semantics')].map((e) => (e.getAttribute('aria-label') || e.textContent || '').trim()).filter(Boolean).join(' || '));
const semantique = async (page) => {
  // Un seul clic sur le marqueur, une fois le moteur prêt (des clics répétés ne servent à rien) ; relance lente en cas d'échec.
  for (let i = 0; i < 6; i++) {
    await pause(i === 0 ? 2500 : 4000);
    const etat = await page.evaluate(() => { const p = document.querySelector('flt-semantics-placeholder'); p?.click(); return { placeholder: !!p, noeuds: document.querySelectorAll('flt-semantics').length }; });
    await pause(800);
    if (process.env.E2E_DEBUG) console.log('  [sémantique]', i, JSON.stringify(etat));
    if ((await textes(page)).length > 0) return;
  }
};
const attendreTexte = async (page, motif, ms = 60000) => { const fin = Date.now() + ms; while (Date.now() < fin) { if (motif.test(await textes(page))) return; await pause(400); } throw new Error(`Texte attendu absent : ${motif} — vu : ${(await textes(page)).slice(0, 300)}`); };
const charger = async (page, url, horsLigne = false) => {
  const t0 = Date.now();
  await page.goto(url, { waitUntil: 'domcontentloaded' });
  await page.waitForSelector('flutter-view, flt-glass-pane', { timeout: 90000 });
  await semantique(page);
  await attendreTexte(page, horsLigne ? /verrouillée|SE CONNECTER|Bienvenue/ : /SE CONNECTER|verrouillée|Bienvenue/);
  return Date.now() - t0;
};
const touches = async (page, premiereLigneY, pasY) => { for (const [x, ligne] of [[880, 0], [960, 0], [1040, 0], [880, 1]]) { await page.mouse.click(x, premiereLigneY + ligne * pasY); await pause(250); } };
const deverrouiller = async (page) => { await touches(page, 476, 60); await page.mouse.click(960, 728); };
const fermerRappels = async (page) => {
  // La fenêtre « Rappels du jour » s'ouvre quelques secondes après le tableau de bord (bandes lues en base) et n'apparaît pas
  // toujours dans l'arbre de sémantique : on attend, puis on clique « Plus tard » (sans effet si elle n'est pas ouverte).
  await pause(7000);
  await page.mouse.click(956, 627);
  await pause(1200);
};
const versFournisseurs = async (page) => { await page.mouse.click(92, 570); await attendreTexte(page, /Fournisseurs — Ajout|FOURNISSEURS ACTIFS/); await pause(1000); };
const capture = (page, nom) => page.screenshot({ path: path.join(captures, nom) });

try {
  // ─── 1. Démarrage à froid, connexion, PIN, tirage ───
  page = await ouvrir();
  pulls = 0; let pushes = [];
  const surReponse = (r) => { const u = r.url(); if (process.env.E2E_DEBUG && u.includes('/api/')) console.log('  [api]', new Date().toISOString().slice(14, 23), r.status(), r.request().method(), u.replace(base, '').slice(0, 60)); if (u.includes('/api/sync/pull')) pulls++; if (u.includes('/api/sync/push')) pushes.push(r.status()); };
  page.on('response', surReponse);
  mesures.demarrage_froid_ms = await charger(page, `${base}/poste/`);
  ok(`démarrage à froid : écran de connexion en ${mesures.demarrage_froid_ms} ms`);
  await capture(page, '1_connexion.png');

  await page.mouse.click(960, 486); await pause(600); await page.keyboard.type('admin', { delay: 40 });
  await page.mouse.click(940, 568); await pause(600); await page.keyboard.type('AgriERP@2026', { delay: 40 });
  const t1 = Date.now();
  await page.mouse.click(960, 664);
  await attendreTexte(page, /Définir votre code PIN/, 30000);
  await touches(page, 500, 60); await page.mouse.click(960, 752); await pause(2500);
  await touches(page, 500, 60); await page.mouse.click(960, 752);
  await attendreTexte(page, /Bienvenue/, 60000);
  while (pulls < 7 && Date.now() - t1 < 120000) await pause(500);
  await pause(4000);
  mesures.connexion_pin_tirage_ms = Date.now() - t1;
  mesures.pages_de_tirage = pulls;
  assert.ok(pulls >= 7, `tirage incomplet (${pulls} pages)`);
  ok(`connexion + PIN + tirage complet (${pulls} pages) en ${mesures.connexion_pin_tirage_ms} ms`);
  // PWA-2b — le tableau de bord affiché PENDANT le tirage se rafraîchit SEUL à la fin du tirage (aucun changement d'écran).
  { const t = Date.now(); while (!/312/.test(await textes(page)) && Date.now() - t < 40000) await pause(500); mesures.tableau_de_bord_rafraichi_seul_ms = Date.now() - t; }
  await fermerRappels(page);
  await capture(page, '2_tableau_de_bord.png');
  assert.match(await textes(page), /312/, 'les données du serveur sont affichées (312 têtes)');
  ok(`le tableau de bord affiche les données du serveur (effectif 312) SANS changer d'écran (${mesures.tableau_de_bord_rafraichi_seul_ms} ms après la fin du tirage)`);

  // ─── 2. Service worker du poste ───
  const sw = await page.evaluate(async () => {
    const pret = await navigator.serviceWorker.ready;
    const noms = await caches.keys();
    const cles = {};
    for (const n of noms) cles[n] = (await (await caches.open(n)).keys()).map((q) => new URL(q.url).pathname);
    return { portee: pret.scope, etat: pret.active?.state, controle: Boolean(navigator.serviceWorker.controller), cles };
  });
  assert.equal(new URL(sw.portee).pathname, '/poste/');
  assert.equal(sw.etat, 'activated');
  const enveloppe = Object.values(sw.cles)[0];
  for (const f of ['index.html', 'main.dart.js', 'sqlite3.wasm', 'drift_worker.js', 'flutter.js', 'manifest.json']) assert.ok(enveloppe.includes('/poste/' + f), `${f} précaché`);
  const interdits = enveloppe.filter((p) => /\/(api|livewire|login|storage)\b/.test(p));
  assert.deepEqual(interdits, [], 'aucune donnée ni page authentifiée dans le cache');
  assert.equal(Object.keys(sw.cles).length, 1, 'un seul cache (anciennes versions purgées)');
  mesures.fichiers_precaches = enveloppe.length;
  ok(`service worker /poste/ actif, ${enveloppe.length} fichiers précachés, aucun /api ni /livewire dans le cache`);

  await versFournisseurs(page);
  assert.match(await textes(page), /Provenderie du Plateau/);
  await capture(page, '3_fournisseurs_en_ligne.png');
  ok('Fournisseurs : les 6 fournisseurs du serveur sont dans la base locale');
  mesures.stockage = await page.evaluate(async () => { const e = await navigator.storage.estimate(); return { indexedDB_o: e.usageDetails?.indexedDB, caches_o: e.usageDetails?.caches }; });

  // ─── 3. RECHARGEMENT HORS LIGNE ───
  contexteHorsLigne = true;
  await contexte.setOffline(true);
  const t2 = Date.now();
  await page.reload({ waitUntil: 'domcontentloaded' });
  await page.waitForSelector('flutter-view, flt-glass-pane', { timeout: 60000 });
  await semantique(page);
  await attendreTexte(page, /verrouillée|Bienvenue/, 60000);
  mesures.rechargement_hors_ligne_ms = Date.now() - t2;
  ok(`RECHARGEMENT HORS LIGNE : l'application se recharge depuis le service worker en ${mesures.rechargement_hors_ligne_ms} ms`);
  await capture(page, '4_hors_ligne_apres_rechargement.png');
  if (/verrouillée/.test(await textes(page))) { await deverrouiller(page); await attendreTexte(page, /Bienvenue/, 30000); }
  await fermerRappels(page);
  assert.match(await textes(page), /312/, 'données locales affichées hors ligne');
  ok('hors ligne, après rechargement et déverrouillage : les données locales sont affichées (312 têtes)');
  await versFournisseurs(page);
  assert.match(await textes(page), /SODIVET/);
  await capture(page, '5_fournisseurs_hors_ligne.png');

  // ─── 4. Saisie hors ligne ───
  await page.mouse.click(1158, 348); await attendreTexte(page, /Nom du fournisseur/);
  await page.mouse.click(640, 339); await pause(500); await page.keyboard.type(NOM, { delay: 30 });
  await page.mouse.click(640, 410); await pause(500); await page.keyboard.type('+22990001122', { delay: 30 });
  await page.mouse.click(640, 482); await pause(800); await page.mouse.click(640, 530); await pause(500);
  await capture(page, '6_saisie_hors_ligne.png');
  await page.mouse.click(790, 629);
  await attendreTexte(page, new RegExp(NOM), 15000);
  assert.equal(sql(`select count(*) from suppliers where name='${NOM}'`), '0', 'rien côté serveur tant que hors ligne');
  ok('fournisseur créé HORS LIGNE : visible dans la liste locale, absent du serveur');
  await capture(page, '7_fournisseur_cree_hors_ligne.png');


  // ─── 4b. VENTE DE CAISSE hors ligne (PWA-2b) : produit « Cage galvanisée 4 compartiments » (vente à la pièce, montant global) ───
  const avant = {
    ventes: Number(sql("select count(*) from sales")),
    stock: Number(sql("select stock_qty from products where sku='EQP-001'")),
    caisse: Number(sql("select balance from treasury_accounts where label='Caisse Principale'")),
    mouvements: Number(sql("select count(*) from stock_movements")),
  };
  await page.mouse.click(92, 148); await pause(2500); // Tableau de bord
  await page.mouse.click(1050, 117); await attendreTexte(page, /Panier de Vente/, 15000); await pause(1500);
  await page.mouse.click(613, 480); await attendreTexte(page, /Ajouter au panier/, 10000); await pause(800);
  await page.mouse.click(640, 484); await pause(600); await page.keyboard.type('25000', { delay: 40 }); await pause(600);
  await page.mouse.click(770, 549); await pause(1500);
  await capture(page, '7d_vente_panier_hors_ligne.png');
  await page.mouse.click(1110, 861);
  await attendreTexte(page, /Vente Enregistrée/, 20000);
  await capture(page, '7e_vente_enregistree_hors_ligne.png');
  assert.equal(sql("select count(*) from sales"), String(avant.ventes), 'aucune vente côté serveur tant que hors ligne');
  ok('VENTE DE CAISSE créée HORS LIGNE (produit, quantité, montant, espèces) : « Vente Enregistrée », absente du serveur');
  await page.mouse.click(640, 566); await pause(800); // « Nouvelle Vente »

  // ─── 5. Reconnexion et synchronisation unique ───
  pushes = [];
  contexteHorsLigne = false;
  await contexte.setOffline(false);
  const t3 = Date.now();
  let poussee = false;
  for (let i = 0; i < 360 && !poussee; i++) { if (pushes.includes(200)) poussee = true; else await pause(500); }
  if (!poussee) { await page.mouse.click(909, 32); await pause(2000); await capture(page, '7b_synchronisation.png'); await page.mouse.click(777, 597); for (let i = 0; i < 240 && !pushes.includes(200); i++) await pause(500); mesures.synchro = 'manuelle (« Synchroniser maintenant »)'; await pause(2500); await capture(page, '7c_apres_synchronisation.png'); await page.mouse.click(518, 597); await pause(500); } else mesures.synchro = 'automatique (événement navigateur « online »)';
  assert.ok(pushes.includes(200), `aucun POST /api/sync/push réussi (${JSON.stringify(pushes)})`);
  mesures.reconnexion_vers_push_ms = Date.now() - t3;
  // « synchronisé » = les deux lignes sont chez le serveur ET le tirage de la même passe est fini
  for (let i = 0; i < 120 && sql("select count(*) from sales") === String(avant.ventes); i++) await pause(500);
  mesures.reconnexion_vers_synchronise_ms = Date.now() - t3;
  await pause(1500);
  assert.equal(sql(`select count(*) from suppliers where name='${NOM}'`), '1', 'exactement UNE ligne côté serveur');
  ok(`reconnexion : synchronisation ${mesures.synchro}, UNE ligne « ${NOM} » côté serveur (envoi en ${mesures.reconnexion_vers_push_ms} ms, tout synchronisé en ${mesures.reconnexion_vers_synchronise_ms} ms)`);
  // La vente de caisse : UNE vente, stock et trésorerie mis à jour PAR LE SERVEUR
  const apres = () => ({
    ventes: Number(sql("select count(*) from sales")),
    stock: Number(sql("select stock_qty from products where sku='EQP-001'")),
    caisse: Number(sql("select balance from treasury_accounts where label='Caisse Principale'")),
    mouvements: Number(sql("select count(*) from stock_movements")),
  });
  const a1 = apres();
  assert.equal(a1.ventes, avant.ventes + 1, 'exactement UNE vente de plus côté serveur');
  assert.equal(a1.stock, avant.stock - 1, 'stock décrémenté par le serveur');
  assert.ok(Math.abs(a1.caisse - (avant.caisse + 25000)) < 0.01, `trésorerie créditée de 25 000 (avant ${avant.caisse}, après ${a1.caisse})`);
  assert.ok(a1.mouvements >= avant.mouvements + 1, 'un mouvement de stock écrit par le serveur');
  mesures.vente_hors_ligne = { avant, apres: a1 };
  ok(`vente de caisse hors ligne synchronisée : ventes ${avant.ventes} → ${a1.ventes}, stock ${avant.stock} → ${a1.stock}, Caisse Principale ${avant.caisse} → ${a1.caisse}`);
  await capture(page, '7f_apres_synchronisation_vente.png');
  await page.mouse.click(909, 32); await pause(1500); await page.mouse.click(777, 597); await pause(8000); await page.mouse.click(518, 597); await pause(500); // une synchro de plus ne doit rien dupliquer
  assert.equal(sql(`select count(*) from suppliers where name='${NOM}'`), '1', 'toujours UNE ligne');
  assert.deepEqual(apres(), a1, 'un second « synchroniser » ne double ni la vente, ni le stock, ni la trésorerie');
  ok('une synchronisation supplémentaire ne double rien (vente, stock, trésorerie, fournisseur)');

  // ─── 5b. Retour de focus de l'onglet (visibilitychange) : anti-rebond de 30 s, puis nouvelle synchronisation ───
  // Chromium sans fenêtre ne change pas la visibilité : l'événement est émis à la main (la même écoute que le vrai).
  const focus = () => page.evaluate(() => { Object.defineProperty(document, 'visibilityState', { value: 'visible', configurable: true }); document.dispatchEvent(new Event('visibilitychange')); });
  await pause(32000); // > 30 s depuis la dernière tentative automatique
  const p0 = pulls;
  await focus();
  for (let i = 0; i < 60 && pulls === p0; i++) await pause(500);
  assert.ok(pulls > p0, 'retour de focus après plus de 30 s : une synchronisation part');
  ok('retour de focus après plus de 30 s : une synchronisation automatique part (pull puis push)');
  await pause(15000); // laisse finir le tirage (plusieurs pages)
  const p1 = pulls;
  await focus(); await pause(4000);
  assert.equal(pulls, p1, 'retour de focus moins de 30 s après cette synchronisation : anti-rebond, aucun tirage');
  ok('retour de focus moins de 30 s après une synchronisation : retenu par l\'anti-rebond');

  // ─── 6. Fermeture / réouverture du navigateur ───
  await contexte.close();
  page = await ouvrir();
  mesures.reouverture_en_ligne_ms = await charger(page, `${base}/poste/`);
  if (/verrouillée/.test(await textes(page))) { await deverrouiller(page); await attendreTexte(page, /Bienvenue/, 30000); }
  await fermerRappels(page);
  await versFournisseurs(page);
  assert.match(await textes(page), new RegExp(NOM));
  await capture(page, '8_apres_reouverture.png');
  ok(`navigateur fermé puis rouvert (${mesures.reouverture_en_ligne_ms} ms) : session, PIN et fournisseur conservés`);

  // ─── 7. Démarrage hors ligne à froid (navigateur neuf, mêmes données) ───
  await contexte.close();
  page = await ouvrir(true);
  mesures.demarrage_hors_ligne_froid_ms = await charger(page, `${base}/poste/`, true);
  ok(`navigateur rouvert SANS réseau : l'application démarre en ${mesures.demarrage_hors_ligne_froid_ms} ms`);
  if (/verrouillée/.test(await textes(page))) { await deverrouiller(page); await attendreTexte(page, /Bienvenue/, 30000); }
  await fermerRappels(page);
  await versFournisseurs(page);
  assert.match(await textes(page), new RegExp(NOM));
  await capture(page, '9_demarrage_hors_ligne.png');
  ok('démarrage hors ligne à froid : les données (dont le fournisseur saisi) sont là');
  console.log('\nMESURES ' + JSON.stringify(mesures, null, 2));
} catch (e) {
  echec = e;
  console.log('\nÉCHEC : ' + (e?.stack ?? e));
  try { await page.screenshot({ path: path.join(captures, 'echec.png') }); console.log('Aspect DOM : ' + (await page.evaluate(() => document.body.innerHTML.slice(0, 400)))); } catch { /* page fermée */ }
  console.log('MESURES (partielles) ' + JSON.stringify(mesures, null, 2));
} finally {
  try { await contexte?.close(); } catch { /* déjà fermé */ }
  arreter();
  console.log(`Captures : ${captures}`);
  if (!process.env.E2E_CAPTURES) console.log(`Dossier temporaire à supprimer : ${dossier}`);
  else fs.rmSync(dossier, { recursive: true, force: true });
}
process.exit(echec ? 1 : 0);
