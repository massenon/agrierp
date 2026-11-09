{{flutter_js}}
{{flutter_build_config}}

// PWA-2 — gabarit de démarrage du poste web (remplace celui que Flutter génère).
//
// ⚠️ AUCUN réglage de service worker Flutter (ni option de chargeur) : le `flutter_service_worker.js` de Flutter 3.47 est un stub de 784 octets qui se
// DÉSINSCRIT (étude 45, bloquant n°1). Le poste enregistre à la place `poste_sw.js` (portée /poste/), ci-dessous.
_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    const moteur = await engineInitializer.initializeEngine();
    await moteur.runApp();
    const attente = document.getElementById('attente');
    if (attente) attente.remove();
  },
});

// PWA-2b — MISE À JOUR CONTRÔLÉE. Une nouvelle `VERSION` de poste_sw.js s'installe en arrière-plan puis ATTEND (aucun
// `skipWaiting` automatique, aucun rechargement forcé : une saisie en cours n'est jamais perdue). Un bandeau, HORS du canevas
// Flutter, propose « Recharger » ; seul ce clic active la nouvelle version, puis recharge la page. Le worker est réinterrogé à
// chaque retour de focus et toutes les heures.
function proposerMiseAJour(attente) {
  if (document.getElementById('nouvelle-version')) return;
  var bandeau = document.createElement('div');
  bandeau.id = 'nouvelle-version';
  bandeau.setAttribute('role', 'status');
  bandeau.style.cssText = 'position:fixed;left:50%;bottom:16px;transform:translateX(-50%);z-index:2147483647;display:flex;gap:12px;align-items:center;' +
    'padding:10px 16px;border-radius:10px;background:#052E16;color:#fff;font:14px system-ui,sans-serif;box-shadow:0 4px 16px rgba(0,0,0,.35)';
  var texte = document.createElement('span');
  texte.textContent = 'Nouvelle version disponible \u2014 ';
  var bouton = document.createElement('button');
  bouton.id = 'nouvelle-version-recharger';
  bouton.textContent = 'Recharger';
  bouton.style.cssText = 'padding:6px 12px;border:0;border-radius:6px;background:#F5C518;color:#052E16;font-weight:700;cursor:pointer';
  bouton.onclick = function () { window.__rechargerApresMiseAJour = true; attente.postMessage('SKIP_WAITING'); };
  var plusTard = document.createElement('button');
  plusTard.textContent = 'Plus tard';
  plusTard.style.cssText = 'padding:6px 8px;border:0;background:transparent;color:#cbd5c8;cursor:pointer';
  plusTard.onclick = function () { bandeau.remove(); };
  bandeau.append(texte, bouton, plusTard);
  document.body.appendChild(bandeau);
}

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.addEventListener('controllerchange', function () {
    if (window.__rechargerApresMiseAJour) window.location.reload();
  });
  window.addEventListener('load', function () {
    navigator.serviceWorker
      .register('poste_sw.js', { scope: './' })
      .then(function (reg) {
        // Une mise à jour n'est « une mise à jour » que si un worker contrôle déjà la page (sinon : première installation).
        if (reg.waiting && navigator.serviceWorker.controller) proposerMiseAJour(reg.waiting);
        reg.addEventListener('updatefound', function () {
          var nouveau = reg.installing;
          if (!nouveau) return;
          nouveau.addEventListener('statechange', function () {
            if (nouveau.state === 'installed' && navigator.serviceWorker.controller) proposerMiseAJour(nouveau);
          });
        });
        var verifier = function () {
          reg.update().then(function () {
            // « Plus tard » n'oublie pas la mise à jour : elle est reproposée au prochain retour de focus.
            if (reg.waiting && navigator.serviceWorker.controller) proposerMiseAJour(reg.waiting);
          }).catch(function () { /* hors ligne : rien à faire */ });
        };
        document.addEventListener('visibilitychange', function () { if (document.visibilityState === 'visible') verifier(); });
        setInterval(verifier, 3600000);
        window.__verifierMiseAJour = verifier;
      })
      .catch(function (e) { console.warn('poste_sw.js non enregistré :', e); });
  });
}
