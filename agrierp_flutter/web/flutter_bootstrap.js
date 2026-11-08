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

if ('serviceWorker' in navigator) {
  window.addEventListener('load', function () {
    navigator.serviceWorker
      .register('poste_sw.js', { scope: './' })
      .catch(function (e) { console.warn('poste_sw.js non enregistré :', e); });
  });
}
