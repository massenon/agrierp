<div class="mt-md space-y-md">
    <div class="flex flex-col gap-sm lg:flex-row lg:items-center lg:justify-between border-b border-outline-variant pb-md">
        <div>
            <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">database</span>Sauvegardes de la Base de Données
            </h2>
            <p class="text-xs lg:text-sm text-outline mt-xs">
                Une sauvegarde automatique est générée chaque nuit et conservée 30 jours. Téléchargez-la régulièrement : un fichier resté sur le serveur ne protège de rien si le serveur tombe.
            </p>
        </div>
        <button type="button" wire:click="genererComplete" wire:loading.attr="disabled" wire:target="genererComplete"
            class="flex items-center justify-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm rounded-full shadow-sm disabled:opacity-50">
            <span class="material-symbols-outlined text-[18px]">backup</span>Générer une sauvegarde
        </button>
    </div>

    <div class="bg-white border border-outline-variant rounded-lg p-md">
        <p class="text-xs font-bold text-brand-forest uppercase mb-sm">Exporter un module seul</p>
        <div class="flex flex-wrap items-end gap-sm">
            <div class="flex-1 min-w-[220px]">
                <select wire:model="moduleAExporter" class="w-full h-10 px-md border rounded-lg text-xs bg-white {{ $errors->has('moduleAExporter') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Choisir un module --</option>
                    @foreach($this->modules as $cle => $definition)
                        <option value="{{ $cle }}">{{ $definition['libelle'] }}</option>
                    @endforeach
                </select>
                @error('moduleAExporter') <p class="invalid-feedback">{{ $message }}</p> @enderror
            </div>
            <button type="button" wire:click="genererModule" wire:loading.attr="disabled" wire:target="genererModule"
                class="flex items-center gap-xs border border-outline-variant hover:bg-surface-zebra text-brand-forest font-bold text-xs px-md py-2 rounded-full disabled:opacity-50">
                <span class="material-symbols-outlined text-[16px]">download</span>Exporter ce module
            </button>
        </div>
        <p class="text-[10px] text-outline mt-sm">
            Un export de module contient les <strong>données</strong> de ce module uniquement, sans le schéma : il sert à transmettre ou à analyser, jamais à restaurer une exploitation complète.
        </p>
    </div>

    <div class="bg-white border border-outline-variant rounded-lg p-md">
        <p class="text-xs font-bold text-brand-forest uppercase mb-sm">Importer un module</p>

        <div class="bg-info-blue/10 border border-info-blue/20 rounded-lg p-sm text-[11px] text-brand-forest mb-sm">
            <span class="material-symbols-outlined text-[14px] align-middle mr-xs">shield</span>
            Le fichier est <strong>analysé</strong>, jamais exécuté : seules les insertions vers les tables du module choisi sont retenues. Toute autre instruction est refusée et signalée.
        </div>

        <div class="flex flex-wrap items-end gap-sm">
            <div class="flex-1 min-w-[220px]">
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Sauvegarde</label>
                <select wire:model="fichierAImporter" class="w-full h-10 px-md border rounded-lg text-xs bg-white {{ $errors->has('fichierAImporter') ? 'is-invalid' : 'border-outline-variant' }}">
                    <option value="">-- Choisir un fichier --</option>
                    @foreach($this->fichiers as $f)
                        <option value="{{ $f['fichier'] }}">{{ $f['fichier'] }}</option>
                    @endforeach
                </select>
            </div>
            <div class="flex-1 min-w-[200px]">
                <label class="block text-[10px] text-brand-forest font-bold uppercase mb-xs">Module cible</label>
                <select wire:model="moduleAImporter" class="w-full h-10 px-md border border-outline-variant rounded-lg text-xs bg-white">
                    <option value="">-- Choisir un module --</option>
                    @foreach($this->modules as $cle => $definition)
                        <option value="{{ $cle }}">{{ $definition['libelle'] }}</option>
                    @endforeach
                </select>
            </div>
            <button type="button" x-on:click="$dispatch('open-modal', { name: 'modal-import' })"
                class="flex items-center gap-xs border border-error-deep/40 hover:bg-error-bg text-error-deep font-bold text-xs px-md py-2 rounded-full">
                <span class="material-symbols-outlined text-[16px]">upload</span>Importer
            </button>
        </div>
        @error('fichierAImporter') <p class="invalid-feedback">{{ $message }}</p> @enderror
    </div>

    <x-modal name="modal-import" max-width="md">
        <div class="text-center">
            <span class="material-symbols-outlined text-error-deep" style="font-size:48px;">warning</span>
            <h3 class="font-bold text-lg text-brand-forest mt-sm">Remplacer les données de ce module ?</h3>
            <p class="text-xs text-outline mt-sm">
                Les données actuelles du module sélectionné seront <strong>supprimées</strong> puis remplacées par celles du fichier. Les enregistrements d'autres modules qui y font référence peuvent devenir orphelins.
                <br><br>
                Générez une sauvegarde complète avant de poursuivre.
            </p>
        </div>
        <div class="flex justify-end gap-sm pt-md mt-md border-t border-outline-variant">
            <button type="button" x-on:click="$dispatch('close-modal', { name: 'modal-import' })"
                class="px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold text-outline hover:bg-surface-zebra">
                Annuler
            </button>
            <button type="button" wire:click="importerModule" wire:loading.attr="disabled"
                class="px-md py-sm rounded-lg bg-error-red hover:bg-error-deep text-white text-sm font-bold disabled:opacity-50">
                Confirmer l'import
            </button>
        </div>
    </x-modal>

    <div class="bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden">
        <div class="overflow-x-auto">
            <table class="w-full rtable">
                <thead class="bg-surface-zebra border-b border-outline-variant">
                    <tr>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Fichier</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Date</th>
                        <th class="px-md py-sm text-left text-[10px] text-outline font-bold uppercase">Table</th>
                        <th class="px-md py-sm text-right text-[10px] text-outline font-bold uppercase">Action</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($this->fichiers as $i => $fichier)
                        <tr class="rrow border-b border-outline-variant {{ $i % 2 === 1 ? 'bg-surface-zebra' : 'bg-white' }}">
                            <td data-label="Fichier" class="px-md py-sm text-xs font-mono">{{ $fichier['fichier'] }}</td>
                            <td data-label="Date" class="px-md py-sm text-xs text-outline">{{ $fichier['date']->format('d/m/Y à H:i') }}</td>
                            <td data-label="Table" class="px-md py-sm text-xs font-bold text-brand-forest">{{ $fichier['portee'] }}</td>
                            <td data-label="Action" class="px-md py-sm text-right whitespace-nowrap">
                                <button type="button" wire:click="telecharger('{{ $fichier['fichier'] }}')"
                                    class="inline-flex items-center gap-xs text-xs font-bold text-brand-emerald hover:text-brand-forest">
                                    <span class="material-symbols-outlined text-[16px]">download</span>Télécharger
                                    <span class="text-outline font-normal">({{ number_format($fichier['taille'] / 1024, 0, ',', ' ') }} Ko)</span>
                                </button>
                            </td>
                        </tr>
                    @empty
                        <tr>
                            <td colspan="4" class="px-md py-lg text-center text-outline text-xs">
                                Aucune sauvegarde pour le moment — générez-en une avec le bouton ci-dessus.
                            </td>
                        </tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>
</div>
