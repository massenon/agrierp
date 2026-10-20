{{-- Ticket H11 — filtre d'espèce de l'onglet GMQ (ajout du poste, `_filtreEspece`) : il ne filtre que le tableau. --}}
<select wire:model.live="espece" class="h-10 px-md border border-outline-variant rounded-lg text-xs font-bold bg-white">
    <option value="all">Toutes les Espèces</option>
    <option value="cuniculture">Cuniculture (Lapins)</option>
    <option value="aviculture">Aviculture (Volailles)</option>
    <option value="porciculture">Porciculture (Porcs)</option>
</select>
