/**
 * PWA-2b — PREUVE DANS CHROMIUM de la MISE À JOUR CONTRÔLÉE du service worker du poste (lancé À LA MAIN).
 *
 *   agrierp_flutter/outils/construire_poste_web.sh && node agrierp_flutter/outils/e2e_poste_mise_a_jour.mjs
 *
 * Scénario : page ouverte et contrôlée par poste_sw.js (version A) → une version B est « déployée » (VERSION modifiée dans
 * public/poste/poste_sw.js, restaurée à la fin) → la page se réinterroge → le bandeau « Nouvelle version disponible — Recharger »
 * apparaît SANS recharger la page (un marqueur posé dans la page survit) → clic « Recharger » → la page repart sur la version B.
 * Serveur : `php -S` (routeur de Laravel), fichiers statiques de /poste/ seulement (aucune base utilisée).
 */
import { createRequire } from 'node:module';
import { spawn } from 'node:child_process';
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
const sw = path.join(laravel, 'public/poste/poste_sw.js');
assert.ok(fs.existsSync(sw), 'public/poste/ absent : lancer outils/construire_poste_web.sh');
const original = fs.readFileSync(sw, 'utf8');
const versionA = /const VERSION = '([^']+)'/.exec(original)[1];
const dossier = fs.mkdtempSync(path.join(os.tmpdir(), 'agrierp-poste-maj-'));
fs.writeFileSync(path.join(dossier, 'vide.sqlite'), '');
const libre = () => new Promise((ok) => { const s = net.createServer(); s.listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => ok(p)); }); });
const port = await libre();
const base = `http://127.0.0.1:${port}`;
const env = { ...process.env, DB_CONNECTION: 'sqlite', DB_DATABASE: path.join(dossier, 'vide.sqlite'), APP_ENV: 'local', APP_DEBUG: 'false', CACHE_STORE: 'file', SESSION_DRIVER: 'file' };
const serveur = spawn('php', ['-S', `127.0.0.1:${port}`, path.join(laravel, 'vendor/laravel/framework/src/Illuminate/Foundation/resources/server.php')], { cwd: path.join(laravel, 'public'), env, stdio: 'ignore' });
const pause = (ms) => new Promise((r) => setTimeout(r, ms));
const ok = (nom) => console.log(`  ✔ ${nom}`);
let contexte; let echec = null;
try {
  for (let i = 0; i < 60; i++) { try { if ((await fetch(`${base}/up`)).ok) break; } catch { /* pas prêt */ } await pause(250); }
  contexte = await chromium.launchPersistentContext(path.join(dossier, 'profil'), { headless: true, args: ['--no-sandbox'], viewport: { width: 1280, height: 900 } });
  const page = contexte.pages()[0] ?? await contexte.newPage();
  await page.goto(`${base}/poste/`, { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => navigator.serviceWorker.ready.then(() => true), null, { timeout: 60000 });
  await page.reload({ waitUntil: 'domcontentloaded' }); // la page est désormais CONTRÔLÉE (sinon : première installation)
  await page.waitForFunction(() => Boolean(navigator.serviceWorker.controller) && typeof window.__verifierMiseAJour === 'function', null, { timeout: 60000 });
  await page.evaluate(() => { window.__marque = 'saisie en cours'; });
  const versionDe = (p) => p.evaluate(() => new Promise((res) => { navigator.serviceWorker.addEventListener('message', (e) => res(e.data.version), { once: true }); navigator.serviceWorker.controller.postMessage('VERSION'); }));
  assert.equal(await versionDe(page), versionA);
  ok(`page contrôlée par poste_sw.js version A (${versionA})`);
  assert.equal(await page.locator('#nouvelle-version').count(), 0, 'pas de bandeau sans nouvelle version');

  // « Déploiement » de la version B.
  const versionB = 'b' + versionA.slice(1);
  fs.writeFileSync(sw, original.replace(`'${versionA}'`, `'${versionB}'`));
  await page.evaluate(() => window.__verifierMiseAJour());
  await page.waitForSelector('#nouvelle-version', { timeout: 30000 });
  assert.equal(await page.evaluate(() => window.__marque), 'saisie en cours', 'la page N\'A PAS été rechargée : aucune saisie perdue');
  assert.equal(await versionDe(page), versionA, 'la version A contrôle toujours la page tant qu\'on ne clique pas');
  assert.match(await page.locator('#nouvelle-version').innerText(), /Nouvelle version disponible/);
  await page.screenshot({ path: path.join(process.env.E2E_CAPTURES ?? dossier, 'maj_bandeau.png') });
  ok('bandeau « Nouvelle version disponible — Recharger » affiché, page NON rechargée (marqueur de saisie intact)');

  // « Plus tard » ne recharge rien non plus.
  await page.locator('#nouvelle-version button', { hasText: 'Plus tard' }).click();
  assert.equal(await page.locator('#nouvelle-version').count(), 0);
  assert.equal(await page.evaluate(() => window.__marque), 'saisie en cours');
  ok('« Plus tard » masque le bandeau sans rien recharger');

  // Clic « Recharger » : la nouvelle version s'active et la page repart.
  await page.evaluate(() => window.__verifierMiseAJour());
  await page.evaluate(() => navigator.serviceWorker.getRegistration().then((r) => r.waiting && true));
  await page.waitForSelector('#nouvelle-version-recharger', { timeout: 30000 });
  await Promise.all([page.waitForEvent('load', { timeout: 30000 }), page.click('#nouvelle-version-recharger')]);
  await page.waitForFunction(() => Boolean(navigator.serviceWorker.controller), null, { timeout: 30000 });
  assert.equal(await page.evaluate(() => window.__marque), undefined, 'page rechargée après le clic');
  assert.equal(await versionDe(page), versionB);
  ok(`clic « Recharger » : la page repart sur la version B (${versionB})`);
} catch (e) {
  echec = e;
  console.log('\nÉCHEC : ' + (e?.stack ?? e));
} finally {
  fs.writeFileSync(sw, original);
  try { await contexte?.close(); } catch { /* déjà fermé */ }
  try { serveur.kill('SIGTERM'); } catch { /* déjà arrêté */ }
  fs.rmSync(dossier, { recursive: true, force: true });
}
process.exit(echec ? 1 : 0);
