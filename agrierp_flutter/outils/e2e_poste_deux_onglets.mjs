/**
 * PWA-2c — PREUVE DANS CHROMIUM de DEUX VRAIS ONGLETS concurrents du poste web (Playwright, lancé À LA MAIN).
 *
 *   agrierp_flutter/outils/construire_poste_web.sh && node agrierp_flutter/outils/e2e_poste_deux_onglets.mjs
 *
 * UN SEUL contexte de navigateur (profil persistant : IndexedDB, localStorage et service worker PARTAGÉS), DEUX pages sur
 * `/poste/`. Scénario :
 *   1. verrou `navigator.locks` : l'événement `online` est émis dans les deux onglets au même instant → une seule synchronisation
 *      à la fois (aucune requête /api/sync/pull|push d'un onglet ne chevauche celle de l'autre), l'autre onglet attend (verrou en attente observé) ;
 *   2. une saisie de l'onglet A (fournisseur) apparaît dans l'onglet B après rechargement ;
 *   3. deux saisies SIMULTANÉES (même table, deux onglets) : ni perdues ni doublées, au poste comme au serveur ;
 *   4. mise à jour du service worker avec deux onglets ouverts : bandeau dans l'un, clic « Recharger » → l'autre est PRÉVENU (jamais
 *      rechargé de force), et les saisies déjà faites sont intactes.
 * Même sûreté que `e2e_poste_web.mjs` : `php -S`, base SQLITE TEMPORAIRE, jamais le `.env`.
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


const sw = path.join(laravel, 'public/poste/poste_sw.js');
const swOriginal = fs.readFileSync(sw, 'utf8');
let A; let B;
const NOM_A = 'Fournisseur Onglet Premier';
const NOM_B1 = 'Fournisseur Onglet Troisieme simultane';
const NOM_A2 = 'Fournisseur Onglet Deuxieme simultane';
const trace = []; // requêtes /api/sync/pull|push : {onglet, t0, t1, url}
const suivre = (page, nom) => {
  page.on('pageerror', (e) => console.log(`  [erreur page ${nom}]`, e.message.slice(0, 200)));
  page.on('console', (m) => { if (m.type() === 'error' && !/favicon|Failed to load resource/.test(m.text())) console.log(`  [console ${nom}]`, m.text().slice(0, 200)); });
  const debuts = new Map();
  page.on('request', (r) => { if (/\/api\/sync\/(pull|push)/.test(r.url())) debuts.set(r, Date.now()); });
  const fin = (r) => { if (debuts.has(r)) trace.push({ onglet: nom, t0: debuts.get(r), t1: Date.now(), url: r.url().replace(base, '').slice(0, 60) }); };
  page.on('requestfinished', fin);
  page.on('requestfailed', fin);
};
const sondeVerrou = (page) => page.evaluate(() => {
  window.__verrou = [];
  setInterval(async () => { try { const q = await navigator.locks.query(); window.__verrou.push({ tenus: q.held.filter((l) => l.name === 'agrierp-synchro').length, attente: q.pending.filter((l) => l.name === 'agrierp-synchro').length }); } catch { /* sans verrous */ } }, 40);
});
const compte = (texte, nom) => (texte.match(new RegExp(nom, 'g')) ?? []).length;
const ouvrirFournisseur = async (page, nom) => {
  await page.bringToFront();
  await page.mouse.click(1158, 348); await attendreTexte(page, /Nom du fournisseur/);
  await page.mouse.click(640, 339); await pause(500); await page.keyboard.type(nom, { delay: 30 });
  await page.mouse.click(640, 410); await pause(500); await page.keyboard.type('+22990001122', { delay: 30 });
  await page.mouse.click(640, 482); await pause(800); await page.mouse.click(640, 530); await pause(500);
};
const enregistrerFournisseur = (page) => page.mouse.click(790, 629);
const demarrerOnglet = async (page, premier) => {
  await page.bringToFront();
  await charger(page, `${base}/poste/`);
  if (/verrouillée/.test(await textes(page))) { await deverrouiller(page); await attendreTexte(page, /Bienvenue/, 30000); }
  await fermerRappels(page);
};

try {
  // ─── 0. Onglet A : connexion, PIN, tirage ───
  contexte = await chromium.launchPersistentContext(profil, { headless: true, args: ['--no-sandbox'], viewport: { width: 1280, height: 900 }, deviceScaleFactor: 1, locale: 'fr-FR', timezoneId: 'Africa/Porto-Novo' });
  A = contexte.pages()[0] ?? await contexte.newPage();
  suivre(A, 'A');
  let pulls = 0;
  A.on('response', (r) => { if (r.url().includes('/api/sync/pull')) pulls++; });
  await charger(A, `${base}/poste/`);
  await A.mouse.click(960, 486); await pause(600); await A.keyboard.type('admin', { delay: 40 });
  await A.mouse.click(940, 568); await pause(600); await A.keyboard.type('LogiAgriERP@2026', { delay: 40 });
  const t1 = Date.now();
  await A.mouse.click(960, 664);
  await attendreTexte(A, /Définir votre code PIN/, 30000);
  await touches(A, 500, 60); await A.mouse.click(960, 752); await pause(2500);
  await touches(A, 500, 60); await A.mouse.click(960, 752);
  await attendreTexte(A, /Bienvenue/, 60000);
  while (pulls < 7 && Date.now() - t1 < 120000) await pause(500);
  await pause(4000);
  assert.ok(pulls >= 7, `tirage incomplet (${pulls} pages)`);
  await fermerRappels(A);
  ok(`onglet A : connexion + tirage complet (${pulls} pages)`);
  await A.evaluate(async () => { await navigator.serviceWorker.ready; });

  // ─── 0b. Onglet B : DEUXIÈME VRAIE PAGE du même contexte, même origine, même base du navigateur ───
  B = await contexte.newPage();
  suivre(B, 'B');
  await demarrerOnglet(B);
  assert.match(await textes(B), /312/, 'B lit la base partagée avec A : 312 têtes');
  ok('onglet B : ouvert sur la même base (session restaurée, PIN, 312 têtes lus)');
  const dbShared = await B.evaluate(async () => ({ bases: (await indexedDB.databases()).map((d) => d.name) }));
  mesures.bases_indexeddb = dbShared.bases;
  await capture(B, 'onglets_B_ouvert.png');

  // ─── 1. VERROU navigator.locks : deux `online` simultanés ───
  await sondeVerrou(A); await sondeVerrou(B);
  trace.length = 0;
  await Promise.all([A.evaluate(() => window.dispatchEvent(new Event('online'))), B.evaluate(() => window.dispatchEvent(new Event('online')))]);
  const debut = Date.now();
  const pages1 = () => trace.filter((t) => /page=1(&|$)/.test(t.url) && t.url.includes('pull'));
  while (new Set(pages1().map((t) => t.onglet)).size < 2 && Date.now() - debut < 180000) await pause(500);
  assert.equal(new Set(pages1().map((t) => t.onglet)).size, 2, 'chaque onglet a fini par synchroniser une fois');
  await pause(6000);
  const chevauche = [];
  for (const a of trace.filter((t) => t.onglet === 'A')) for (const b of trace.filter((t) => t.onglet === 'B')) if (a.t0 < b.t1 && b.t0 < a.t1) chevauche.push([a.url, b.url]);
  const verrouA = await A.evaluate(() => window.__verrou); const verrouB = await B.evaluate(() => window.__verrou);
  const tousVerrous = [...verrouA, ...verrouB];
  mesures.verrou = { requetes_sync: trace.length, tenus_max: Math.max(...tousVerrous.map((v) => v.tenus)), attente_max: Math.max(...tousVerrous.map((v) => v.attente)), chevauchements: chevauche.length };
  assert.deepEqual(chevauche, [], 'aucune requête de synchronisation d\'un onglet ne chevauche celle de l\'autre');
  assert.ok(mesures.verrou.tenus_max <= 1, 'jamais deux détenteurs du verrou');
  assert.ok(mesures.verrou.attente_max >= 1, 'l\'autre onglet a ATTENDU le verrou');
  ok(`verrou navigator.locks : ${trace.length} requêtes de synchro, jamais de chevauchement entre onglets, un onglet a attendu l'autre (${JSON.stringify(mesures.verrou)})`);

  // ─── 2. Saisie en A → visible en B ───
  await A.bringToFront();
  await versFournisseurs(A);
  await ouvrirFournisseur(A, NOM_A);
  await enregistrerFournisseur(A);
  await attendreTexte(A, new RegExp(NOM_A), 15000);
  ok(`onglet A : « ${NOM_A} » créé`);
  await B.bringToFront();
  await B.reload({ waitUntil: 'domcontentloaded' });
  await B.waitForSelector('flutter-view, flt-glass-pane', { timeout: 60000 });
  await semantique(B);
  await attendreTexte(B, /verrouillée|Bienvenue/, 60000);
  if (/verrouillée/.test(await textes(B))) { await deverrouiller(B); await attendreTexte(B, /Bienvenue/, 30000); }
  await fermerRappels(B);
  await versFournisseurs(B);
  await attendreTexte(B, new RegExp(NOM_A), 15000);
  ok(`onglet B (rechargé) : « ${NOM_A} » saisi dans A est visible`);
  // … et il part UNE fois au serveur (quel que soit l'onglet qui synchronise)
  for (let i = 0; i < 120 && sql(`select count(*) from suppliers where name='${NOM_A}'`) === '0'; i++) await pause(1000);
  assert.equal(sql(`select count(*) from suppliers where name='${NOM_A}'`), '1', 'exactement une ligne serveur');
  ok('le fournisseur de A est arrivé UNE fois au serveur');

  // ─── 3. Deux saisies SIMULTANÉES (même table) ───
  await sondeVerrou(A); await sondeVerrou(B);
  await ouvrirFournisseur(B, NOM_B1);
  await A.bringToFront();
  await A.reload({ waitUntil: 'domcontentloaded' });
  await A.waitForSelector('flutter-view, flt-glass-pane', { timeout: 60000 });
  await semantique(A);
  await attendreTexte(A, /verrouillée|Bienvenue/, 60000);
  if (/verrouillée/.test(await textes(A))) { await deverrouiller(A); await attendreTexte(A, /Bienvenue/, 30000); }
  await fermerRappels(A);
  await versFournisseurs(A);
  await ouvrirFournisseur(A, NOM_A2);
  await Promise.all([enregistrerFournisseur(A), enregistrerFournisseur(B)]);
  await attendreTexte(A, new RegExp(NOM_A2), 15000);
  await attendreTexte(B, new RegExp(NOM_B1), 15000);
  ok('deux saisies simultanées dans la même table : chacune visible dans son onglet');
  // Aucun geste ne déclenche seul une synchronisation (minuterie de 5 min) : le retour en ligne est émis dans LES DEUX onglets
  // au même instant ; les deux saisies (A et B) partent, une seule fois, sous le verrou.
  await Promise.all([A.evaluate(() => window.dispatchEvent(new Event('online'))), B.evaluate(() => window.dispatchEvent(new Event('online')))]);
  for (let i = 0; i < 180 && (sql(`select count(*) from suppliers where name in ('${NOM_A2}','${NOM_B1}')`) !== '2'); i++) await pause(1000);
  await pause(8000); // laisse passer les synchronisations éventuelles des deux onglets
  assert.equal(sql(`select count(*) from suppliers where name='${NOM_A2}'`), '1', 'A : une seule ligne serveur');
  assert.equal(sql(`select count(*) from suppliers where name='${NOM_B1}'`), '1', 'B : une seule ligne serveur');
  assert.equal(sql("select count(*) from suppliers where name like 'Fournisseur Onglet%'"), '3', 'trois fournisseurs, ni perdus ni doublés');
  // au poste : chaque onglet, rechargé, voit les trois, UNE fois chacun
  for (const [page, nom] of [[A, 'A'], [B, 'B']]) {
    await page.bringToFront();
    await page.reload({ waitUntil: 'domcontentloaded' });
    await page.waitForSelector('flutter-view, flt-glass-pane', { timeout: 60000 });
    await semantique(page);
    await attendreTexte(page, /verrouillée|Bienvenue/, 60000);
    if (/verrouillée/.test(await textes(page))) { await deverrouiller(page); await attendreTexte(page, /Bienvenue/, 30000); }
    await fermerRappels(page);
    await versFournisseurs(page);
    const t = await textes(page);
    for (const n of [NOM_A, NOM_A2, NOM_B1]) assert.ok(compte(t, n) >= 1, `onglet ${nom} : ${n} présent`);
    // L'arbre de sémantique répète le libellé d'une ligne (nœuds imbriqués) : l'unicité se prouve par COMPARAISON avec une ligne
    // connue pour être unique (créée une seule fois, « Premier »), jamais par un compte absolu.
    assert.equal(compte(t, NOM_B1), compte(t, NOM_A), `onglet ${nom} : « ${NOM_B1} » autant de fois qu'une ligne unique`);
    assert.equal(compte(t, NOM_A2), compte(t, NOM_A), `onglet ${nom} : « ${NOM_A2} » autant de fois qu'une ligne unique`);
  }
  await capture(B, 'onglets_apres_saisies_simultanees.png');
  ok('au poste, chaque onglet (rechargé) voit les trois fournisseurs, une seule fois chacun ; au serveur : 3 lignes distinctes');

  // ─── 4. Mise à jour du service worker avec DEUX onglets ouverts ───
  await A.evaluate(() => { window.__marque = 'saisie A'; }); await B.evaluate(() => { window.__marque = 'saisie B'; });
  await A.waitForFunction(() => Boolean(navigator.serviceWorker.controller) && typeof window.__verifierMiseAJour === 'function', null, { timeout: 60000 });
  await B.waitForFunction(() => Boolean(navigator.serviceWorker.controller) && typeof window.__verifierMiseAJour === 'function', null, { timeout: 60000 });
  const versionA = /const VERSION = '([^']+)'/.exec(swOriginal)[1];
  const versionB = 'b' + versionA.slice(1);
  fs.writeFileSync(sw, swOriginal.replace(`'${versionA}'`, `'${versionB}'`));
  await Promise.all([A.evaluate(() => window.__verifierMiseAJour()), B.evaluate(() => window.__verifierMiseAJour())]);
  await A.waitForSelector('#nouvelle-version', { timeout: 30000 }); await B.waitForSelector('#nouvelle-version', { timeout: 30000 });
  assert.equal(await A.evaluate(() => window.__marque), 'saisie A'); assert.equal(await B.evaluate(() => window.__marque), 'saisie B');
  ok('la nouvelle version est proposée dans les DEUX onglets, aucun rechargé (marqueurs de saisie intacts)');
  // un clic « Recharger » dans A active la version B pour le navigateur ENTIER : B est prévenu, jamais rechargé de force
  await Promise.all([A.waitForEvent('load', { timeout: 30000 }), A.click('#nouvelle-version-recharger')]);
  await B.waitForFunction(() => document.getElementById('nouvelle-version')?.innerText.includes('autre onglet'), null, { timeout: 30000 });
  assert.equal(await B.evaluate(() => window.__marque), 'saisie B', 'B n\'a PAS été rechargé de force : sa saisie est intacte');
  ok('A a rechargé ; B affiche « La version a changé dans un autre onglet — Recharger » sans être rechargé');
  // rien perdu : B, rechargé à la demande, retrouve ses données
  await Promise.all([B.waitForEvent('load', { timeout: 30000 }), B.click('#nouvelle-version-recharger')]);
  await B.waitForSelector('flutter-view, flt-glass-pane', { timeout: 60000 });
  await semantique(B);
  await attendreTexte(B, /verrouillée|Bienvenue/, 60000);
  if (/verrouillée/.test(await textes(B))) { await deverrouiller(B); await attendreTexte(B, /Bienvenue/, 30000); }
  await fermerRappels(B);
  await versFournisseurs(B);
  const tB = await textes(B);
  for (const n of [NOM_A, NOM_A2, NOM_B1]) assert.ok(tB.includes(n), `après la mise à jour, « ${n} » est toujours là`);
  assert.equal(sql("select count(*) from suppliers where name like 'Fournisseur Onglet%'"), '3');
  ok('après la mise à jour à deux onglets : toutes les données sont intactes (poste et serveur)');
  console.log('\nMESURES ' + JSON.stringify(mesures, null, 2));
} catch (e) {
  echec = e;
  console.log('\nÉCHEC : ' + (e?.stack ?? e));
  for (const [p, n] of [[A, 'A'], [B, 'B']]) { try { await p.screenshot({ path: path.join(captures, `echec_${n}.png`) }); console.log(`Texte ${n} : ` + (await textes(p)).slice(0, 300)); } catch { /* page fermée */ } }
  console.log('MESURES (partielles) ' + JSON.stringify(mesures, null, 2));
} finally {
  fs.writeFileSync(sw, swOriginal);
  try { await contexte?.close(); } catch { /* déjà fermé */ }
  arreter();
  console.log(`Captures : ${captures}`);
  if (!process.env.E2E_CAPTURES) console.log(`Dossier temporaire à supprimer : ${dossier}`);
  else fs.rmSync(dossier, { recursive: true, force: true });
}
process.exit(echec ? 1 : 0);
