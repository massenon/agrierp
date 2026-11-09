<div>
    <div class="mb-lg">
        <h2 class="text-xl font-bold text-on-surface flex items-center gap-xs">
            <span class="material-symbols-outlined text-brand-emerald text-[26px]">receipt_long</span>Facturation normalisée (e-MECeF)
        </h2>
        <p class="text-xs text-outline mt-xs">
            Renseignez ici le compte e-MECeF de la ferme pour transmettre ses factures normalisées à la DGI. Une facture normalisée n'est plus modifiable ni annulable : elle se corrige par un avoir. Une facture simple n'est jamais transmise.
        </p>
    </div>

    <form wire:submit="save" class="bg-white border border-outline-variant rounded-lg p-md space-y-md" id="facturation-mecef">
        <div class="bg-info-blue/10 border border-info-blue/20 rounded-lg p-sm text-[11px] text-brand-forest space-y-xs">
            <p class="font-bold">Où trouver le jeton ?</p>
            <p>Le jeton (JWT) est délivré par la DGI pour le compte e-MECeF de votre IFU : connectez-vous au portail e-MECeF de la DGI avec l'IFU de la ferme et copiez-y le jeton. Il est secret : chiffré sur le serveur, jamais affiché, jamais envoyé aux postes.</p>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-md">
            <div class="sm:col-span-2">
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Mode de facturation normalisée</label>
                <select wire:model.live="mecefMode" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm bg-white">
                    @foreach(\App\Support\MecefMode::LIBELLES as $valeur => $libelle)
                        <option value="{{ $valeur }}">{{ $libelle }}</option>
                    @endforeach
                </select>
                @error('mecefMode') <p class="invalid-feedback">{{ $message }}</p> @enderror
                @if($mecefMode === 'boitier')
                    <p class="text-[10px] text-outline mt-xs">Mode boîtier : la transmission se fait par le poste Windows où le boîtier Eltrade CC300 est branché (fonction construite, pas encore essayée avec un vrai boîtier). Tant que le boîtier est absent, les factures restent en attente et partent dès son retour.</p>
                @elseif($mecefMode === 'desactive')
                    <p class="text-[10px] text-outline mt-xs">Aucune facture n'est transmise : la facturation reste un registre avec facture PDF.</p>
                @else
                    <p class="text-[10px] text-outline mt-xs">Les ventes choisies en « Facture normalisée » à l'encaissement sont transmises à la DGI par le serveur.</p>
                @endif
            </div>

            <div class="sm:col-span-2">
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">IFU de l'entreprise</label>
                <input wire:model="ifu" type="text" inputmode="numeric" maxlength="13" placeholder="13 chiffres" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('ifu') ? 'is-invalid' : 'border-outline-variant' }}">
                <p class="text-[10px] text-outline mt-xs">13 chiffres, celui du compte e-MECeF. C'est le même IFU que celui de « Données de l'Entreprise » : une seule saisie.</p>
                @error('ifu') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>

            @if($mecefMode === 'emecef')
                <div class="sm:col-span-2">
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Adresse de l'API e-MECeF</label>
                    <input wire:model="mecefApiUrl" type="url" placeholder="https://…" class="w-full h-11 px-md border rounded-lg text-sm {{ $errors->has('mecefApiUrl') ? 'is-invalid' : 'border-outline-variant' }}">
                    <div class="flex flex-wrap gap-xs mt-xs">
                        @foreach(\App\Support\MecefMode::PREREGLAGES_URL as $cle => [$libellePreset, $adresse])
                            <button type="button" wire:click="choisirUrl('{{ $cle }}')" class="px-sm py-1 rounded-full border border-outline-variant text-[11px] font-bold text-brand-forest hover:bg-surface-zebra">{{ $libellePreset }}</button>
                        @endforeach
                    </div>
                    <p class="text-[10px] text-outline mt-xs">Pour un premier essai sans valeur fiscale, choisissez l'environnement d'essai. Ces deux adresses sont relevées dans le paquet de référence : confirmez-les avec le portail e-MECeF de la DGI.</p>
                    @error('mecefApiUrl') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>

                <div class="sm:col-span-2">
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Jeton e-MECeF (JWT)</label>
                    @if($this->jetonDeConfiguration && ! $remplacerJeton)
                        <div class="flex items-center gap-sm">
                            <span class="flex-1 h-11 px-md border border-outline-variant rounded-lg text-sm bg-surface-zebra flex items-center text-outline">Jeton défini dans la configuration du serveur</span>
                            <button type="button" wire:click="$set('remplacerJeton', true)" class="px-md h-11 rounded-lg border border-outline-variant text-xs font-bold text-brand-forest hover:bg-surface-zebra">Remplacer</button>
                        </div>
                    @elseif($this->jetonConfigure && ! $remplacerJeton)
                        <div class="flex items-center gap-sm">
                            <span class="flex-1 h-11 px-md border border-outline-variant rounded-lg text-sm bg-surface-zebra flex items-center tracking-widest">••••••••••••</span>
                            <button type="button" wire:click="$set('remplacerJeton', true)" class="px-md h-11 rounded-lg border border-outline-variant text-xs font-bold text-brand-forest hover:bg-surface-zebra">Remplacer</button>
                            <button type="button" wire:click="effacerJeton" wire:confirm="Effacer le jeton ? Plus aucune facture ne sera transmise tant qu'un nouveau jeton n'est pas saisi." class="px-md h-11 rounded-lg border border-error-deep/40 text-xs font-bold text-error-deep hover:bg-error-bg">Effacer</button>
                        </div>
                    @else
                        <input wire:model="mecefJeton" type="password" autocomplete="off" placeholder="Collez le jeton délivré par la DGI" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                    @endif
                    @error('mecefJeton') <p class="invalid-feedback">{{ $message }}</p> @enderror
                </div>

                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Identifiant de l'opérateur</label>
                    <input wire:model="mecefOperateurId" type="text" placeholder="{{ $this->repliOperateur['id'] }}" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Nom de l'opérateur (caissier par défaut)</label>
                    <input wire:model="mecefOperateurNom" type="text" placeholder="{{ $this->repliOperateur['nom'] }}" class="w-full h-11 px-md border border-outline-variant rounded-lg text-sm">
                </div>
            @endif
        </div>

        <div class="flex flex-wrap items-center justify-end gap-sm pt-sm border-t border-outline-variant">
            <button type="button" wire:click="tester" wire:loading.attr="disabled" wire:target="tester" dusk="tester-mecef" class="px-md py-sm rounded-lg border border-brand-emerald text-brand-emerald text-sm font-bold hover:bg-brand-emerald/5 disabled:opacity-50 flex items-center gap-xs">
                <span class="material-symbols-outlined text-[18px]">cloud_done</span>Tester la configuration
            </button>
            <button type="submit" class="px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold hover:bg-brand-forest">Enregistrer</button>
        </div>

        @if($resultatTest)
            <div class="rounded-lg border p-md space-y-xs {{ $resultatTest['ok'] ? 'border-brand-emerald/40 bg-brand-emerald/5' : 'border-error-deep/30 bg-error-bg' }}" id="resultat-test-mecef">
                <p class="text-sm font-bold {{ $resultatTest['ok'] ? 'text-brand-emerald' : 'text-error-deep' }} flex items-center gap-xs">
                    <span class="material-symbols-outlined text-[18px]">{{ $resultatTest['ok'] ? 'check_circle' : 'close' }}</span>{{ $resultatTest['resume'] }}
                </p>
                <ul class="text-[11px] text-brand-forest space-y-[2px]">
                    @foreach($resultatTest['lignes'] as $ligne)
                        <li><span class="font-bold">{{ $ligne['ok'] ? 'OK' : 'À corriger' }}</span> — {{ $ligne['libelle'] }} : {{ $ligne['detail'] }}</li>
                    @endforeach
                </ul>
                <p class="text-[10px] text-outline">Le test ne crée aucune facture : il vérifie la configuration puis lit l'état du service e-MECeF.</p>
            </div>
        @endif
    </form>
</div>
