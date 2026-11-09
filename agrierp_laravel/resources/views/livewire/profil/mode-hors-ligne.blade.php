<div>
    <div class="border-b border-outline-variant pb-md mb-lg">
        <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
            <span class="material-symbols-outlined text-brand-emerald text-[26px]">cloud_off</span>Mode hors ligne
        </h2>
        <p class="text-xs text-outline mt-xs">Travailler même quand la liaison de la ferme tombe : la caisse (avec le droit des ventes) et les fiches d'élevage (avec le droit d'élevage) sont gardées sur cet appareil, puis envoyées toutes seules au retour du réseau. L'écran suit les droits de votre compte.</p>
    </div>

    {{-- Le formulaire est piloté par Alpine/JavaScript, jamais par Livewire : le mot de passe ne passe jamais par Livewire. --}}
    <div wire:ignore
         x-data="modeHorsLigne({ identifiant: @js($identifiant), urlCaisse: '/caisse-hors-ligne.html' })"
         class="grid grid-cols-1 lg:grid-cols-3 gap-lg">

        <div class="lg:col-span-2 bg-white border border-outline-variant rounded-lg p-lg" data-aide="mode-hors-ligne">
            <p class="text-sm font-bold text-brand-forest uppercase mb-md">État de cet appareil</p>

            <template x-if="!prerequis.ok">
                <p class="text-xs text-error-deep bg-error-bg rounded-lg p-md" x-text="prerequis.motif"></p>
            </template>

            <template x-if="prerequis.ok && chargement">
                <p class="text-xs text-outline">Vérification de cet appareil…</p>
            </template>

            <template x-if="prerequis.ok && !chargement && !actif">
                <form x-on:submit.prevent="activer()" class="space-y-md" autocomplete="off">
                    <p class="text-xs text-outline">Cet appareil n'est pas encore activé. Confirmez votre mot de passe (il n'est pas conservé), puis choisissez un PIN : il protège les données locales et rouvre la caisse hors ligne.</p>
                    <div>
                        <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs" for="hl-mdp">Mot de passe</label>
                        <input id="hl-mdp" type="password" x-model="motDePasse" autocomplete="current-password" class="w-full h-10 px-md border border-outline-variant rounded-lg text-xs">
                    </div>
                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-md">
                        <div>
                            <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs" for="hl-pin">PIN (4 à 6 chiffres)</label>
                            <input id="hl-pin" type="password" inputmode="numeric" maxlength="6" x-model="pin" autocomplete="off" class="w-full h-10 px-md border border-outline-variant rounded-lg text-xs">
                        </div>
                        <div>
                            <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs" for="hl-pin2">Confirmer le PIN</label>
                            <input id="hl-pin2" type="password" inputmode="numeric" maxlength="6" x-model="pin2" autocomplete="off" class="w-full h-10 px-md border border-outline-variant rounded-lg text-xs">
                        </div>
                    </div>
                    <p x-show="erreur" x-text="erreur" class="text-xs text-error-deep bg-error-bg rounded-lg p-sm" role="alert"></p>
                    <button type="submit" id="hl-activer" :disabled="envoi" class="h-10 px-lg bg-brand-emerald text-white rounded-lg text-xs font-bold hover:bg-brand-forest disabled:opacity-50 flex items-center gap-xs">
                        <span class="material-symbols-outlined text-[18px]">cloud_off</span><span x-text="envoi ? 'Activation…' : 'Activer le mode hors ligne'"></span>
                    </button>
                </form>
            </template>

            <template x-if="prerequis.ok && !chargement && actif">
                <div class="space-y-md">
                    <div class="bg-surface-zebra rounded-lg p-md text-xs space-y-xs">
                        <p><span class="font-bold text-brand-forest">Appareil appairé :</span> <span class="font-mono" x-text="nomAppareil"></span></p>
                        <p><span class="font-bold text-brand-forest">Activé le :</span> <span x-text="activeLe"></span></p>
                        <p><span class="font-bold text-brand-forest">Stockage durable :</span> <span x-text="persistant ? 'accordé par le navigateur' : 'non garanti par le navigateur : synchronisez souvent'"></span></p>
                        <p x-show="enAttente > 0" class="text-warn font-bold"><span x-text="enAttente"></span> vente(s) de cet appareil ne sont pas encore envoyées.</p>
                    </div>
                    <p x-show="message" x-text="message" class="text-xs text-brand-emerald bg-surface-zebra rounded-lg p-sm" role="status"></p>
                    <div class="flex flex-wrap gap-sm">
                        <a :href="urlCaisse" class="h-10 px-lg bg-brand-emerald text-white rounded-lg text-xs font-bold hover:bg-brand-forest flex items-center gap-xs"><span class="material-symbols-outlined text-[18px]">point_of_sale</span>Ouvrir la caisse hors ligne</a>
                        <button type="button" x-on:click="desactiver()" class="h-10 px-lg border border-error-deep text-error-deep rounded-lg text-xs font-bold hover:bg-error-bg flex items-center gap-xs"><span class="material-symbols-outlined text-[18px]">logout</span>Désactiver cet appareil</button>
                    </div>
                    <p x-show="erreur" x-text="erreur" class="text-xs text-error-deep bg-error-bg rounded-lg p-sm" role="alert"></p>
                </div>
            </template>
        </div>

        <div class="bg-white border border-outline-variant rounded-lg p-lg text-xs text-outline space-y-sm">
            <p class="text-sm font-bold text-brand-forest uppercase">Ce que couvre ce mode</p>
            <ul class="list-disc pl-md space-y-xs">
                <li>Ventes de caisse (réservées aux comptes qui ont le droit des ventes) : produits du catalogue (sujets vivants avec leur bande source et le contrôle de rémanence vétérinaire), panier, livraison facturée, facture simple ou normalisée, paiement (dont « Déduire de l'avance »).</li>
                <li>Création d'un client avec le bouton « + » (nom, téléphone, IFU facultatif) ; il est envoyé au serveur à la synchronisation, qui peut le rapprocher d'une fiche déjà connue.</li>
                <li>Consultation du catalogue et des clients copiés sur l'appareil.</li>
            </ul>
            <p class="text-sm font-bold text-brand-forest uppercase pt-sm">Ce qu'il ne couvre pas</p>
            <ul class="list-disc pl-md space-y-xs">
                <li>Comptabilité, élevage, achats, paie : ces écrans exigent le réseau.</li>
            </ul>
            <p class="text-sm font-bold text-brand-forest uppercase pt-sm">À savoir</p>
            <ul class="list-disc pl-md space-y-xs">
                <li>Le navigateur peut vider son stockage : un compteur « en attente » reste affiché, synchronisez souvent.</li>
                <li>Sur iPhone / iPad, l'envoi automatique en arrière-plan n'existe pas : il part à l'ouverture de la caisse.</li>
                <li>Une seule fenêtre à la fois peut saisir des ventes sur cet appareil.</li>
                <li>Un PIN de 4 à 6 chiffres protège contre le curieux, pas contre un attaquant équipé : n'activez que sur un appareil qui vous est propre.</li>
                <li>Un administrateur peut révoquer cet appareil dans Paramètres, onglet « Postes &amp; Appairage ».</li>
            </ul>
        </div>
    </div>
</div>
