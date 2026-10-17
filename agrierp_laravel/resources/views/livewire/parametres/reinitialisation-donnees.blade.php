<div class="mt-md space-y-md">
    <div class="border-b border-outline-variant pb-md">
        <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
            <span class="material-symbols-outlined text-error-deep text-[26px]">restart_alt</span>Réinitialisation des Données
        </h2>
        <p class="text-xs lg:text-sm text-outline mt-xs">
            Vide les données d'activité pour repartir d'une base propre après une démonstration.
        </p>
    </div>

    <div class="bg-white border border-outline-variant rounded-lg p-md">
        <div class="flex items-start justify-between gap-md">
            <div class="flex-1">
                <p class="text-sm font-bold text-brand-forest">Mode démonstration</p>
                <p class="text-xs text-outline mt-xs">
                    Tant qu'il est désactivé, aucune réinitialisation n'est possible — c'est ce qui protège
                    une exploitation en production d'un effacement accidentel.
                </p>
            </div>
            <button type="button" wire:click="basculerModeDemo"
                class="flex items-center gap-xs px-md py-2 rounded-full text-xs font-bold border transition-all
                    {{ $this->modeDemoActif
                        ? 'bg-accent-yellow text-brand-forest border-accent-yellow'
                        : 'bg-white text-outline border-outline-variant hover:bg-surface-zebra' }}">
                <span class="material-symbols-outlined text-[16px]">
                    {{ $this->modeDemoActif ? 'toggle_on' : 'toggle_off' }}
                </span>
                {{ $this->modeDemoActif ? 'Activé' : 'Désactivé' }}
            </button>
        </div>
    </div>

    @if($this->modeDemoActif)
        <div class="bg-error-bg border border-error-deep/30 rounded-lg p-md">
            <p class="text-sm font-bold text-error-deep flex items-center gap-xs">
                <span class="material-symbols-outlined text-[18px]">warning</span>
                Cette opération vide TOUTES les données d'activité
            </p>
            <p class="text-xs text-error-deep mt-xs">
                L'application ne peut pas distinguer une vente de démonstration d'une vente réelle : elles
                vivent dans la même table, avec la même forme. Ventes, achats, dépenses, mouvements de stock,
                fiches d'élevage, soins, paies et écritures comptables seront supprimés — qu'ils viennent
                d'une démonstration ou d'une activité réelle.
            </p>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-md">
            <div class="bg-white border border-outline-variant rounded-lg p-md">
                <p class="text-xs font-bold text-error-deep uppercase mb-sm flex items-center gap-xs">
                    <span class="material-symbols-outlined text-[16px]">delete_sweep</span>Supprimé
                </p>
                <p class="text-xs text-outline leading-relaxed">
                    Ventes et clients · Achats et fournisseurs · Dépenses · Mouvements de stock ·
                    Bandes, fiches journalières, transferts et soins vétérinaires · Employés, paies et stages ·
                    Écritures comptables, clôtures et immobilisations · Courriers, archives et documents
                    administratifs · Notifications
                </p>
                <p class="text-xs text-outline leading-relaxed mt-xs">
                    Les postes Windows effacent aussi leurs données d'activité à leur prochaine synchronisation ;
                    leurs saisies non encore envoyées sont perdues.
                </p>
            </div>
            <div class="bg-white border border-outline-variant rounded-lg p-md">
                <p class="text-xs font-bold text-brand-emerald uppercase mb-sm flex items-center gap-xs">
                    <span class="material-symbols-outlined text-[16px]">shield</span>Conservé
                </p>
                <p class="text-xs text-outline leading-relaxed">
                    Comptes utilisateurs et rôles · Réglages de l'entreprise · Plan comptable ·
                    Exercices et comptes de trésorerie · Catalogue produits · Espèces, rations,
                    protocoles prophylactiques, normes de croissance · Centres de coût · Barème ITS ·
                    Modèles d'attestation · Numérotation de l'élevage ·
                    <strong>Journal d'audit</strong>
                </p>
            </div>
        </div>

        <button type="button" x-on:click="$dispatch('open-modal', { name: 'modal-reinitialisation' })"
            class="flex items-center justify-center gap-xs bg-error-red hover:bg-error-deep text-white font-bold text-xs px-md py-sm rounded-full shadow-sm">
            <span class="material-symbols-outlined text-[18px]">restart_alt</span>Réinitialiser les données
        </button>

        <x-modal name="modal-reinitialisation" max-width="md">
            <div class="text-center">
                <span class="material-symbols-outlined text-error-deep" style="font-size:48px;">warning</span>
                <h3 class="font-bold text-lg text-brand-forest mt-sm">Réinitialiser toutes les données d'activité ?</h3>
                <p class="text-xs text-outline mt-sm">
                    Cette action est <strong>irréversible</strong> : les enregistrements supprimés ne passent
                    pas par la corbeille et ne pourront pas être restaurés. Assurez-vous d'avoir généré une
                    sauvegarde de la base au préalable.
                </p>
            </div>

            <div class="mt-md">
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">
                    Saisissez REINITIALISER pour confirmer
                </label>
                <input wire:model="confirmation" type="text" placeholder="REINITIALISER"
                    class="w-full h-11 px-md border rounded-lg text-sm font-bold tracking-wider {{ $errors->has('confirmation') ? 'is-invalid' : 'border-outline-variant' }}">
                @error('confirmation') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>

            <div class="flex justify-end gap-sm pt-md mt-md border-t border-outline-variant">
                <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-reinitialisation' })"
                    class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">
                    Annuler
                </button>
                <button type="button" wire:click="reinitialiser" wire:loading.attr="disabled"
                    class="px-md py-sm rounded-lg bg-error-red hover:bg-error-deep text-white text-sm font-bold disabled:opacity-50">
                    Confirmer la réinitialisation
                </button>
            </div>
        </x-modal>
    @else
        <div class="bg-surface-zebra border border-outline-variant rounded-lg p-lg text-center">
            <span class="material-symbols-outlined text-outline-variant text-[44px]">lock</span>
            <p class="text-sm font-semibold text-on-surface mt-sm">Réinitialisation verrouillée</p>
            <p class="text-xs text-outline mt-xs">
                Activez le mode démonstration ci-dessus pour y accéder.
            </p>
        </div>
    @endif
</div>
