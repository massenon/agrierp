<div>
    <div class="border-b border-outline-variant pb-md mb-lg">
        <h2 class="text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs">
            <span class="material-symbols-outlined text-brand-emerald text-[26px]">help</span>Aide &amp; À Propos
        </h2>
        <p class="text-xs text-outline mt-xs">Documentation complète, guide des modules et foire aux questions.</p>
    </div>

    <div class="bg-white border border-outline-variant rounded-lg p-lg mb-lg flex flex-col md:flex-row items-center gap-lg">
        <span class="material-symbols-outlined text-brand-emerald flex-shrink-0" style="font-size:64px;">agriculture</span>
        <div>
            <p class="font-black text-brand-forest text-lg">AgriERP <span class="text-outline text-xs font-normal">v1.0.0</span></p>
            <p class="text-xs text-outline mt-xs">Logiciel de gestion intégrée pour la Ferme École OLOUWACHEGOUN (Attan-Ewé, Ikpinlè, Adja-Ouèrè, Bénin), développé dans le cadre du Projet d'Appui à l'Entrepreneuriat au Bénin (PAEB), avec l'accompagnement du Cabinet FAGUEZ SARL. Édité par Dr MASSENON Rhodes, Docteur en Génie Logiciel et IA.</p>
            <p class="text-xs text-outline mt-xs">AgriERP couvre l'ensemble du cycle d'exploitation : élevage (cuniculture, aviculture, porciculture), ventes et POS, stocks, comptabilité SYSCOHADA, ressources humaines et facturation normalisée MeCeF.</p>
        </div>
    </div>

    <h3 class="text-sm font-bold text-brand-forest uppercase mb-md">Modules du Logiciel</h3>
    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-md mb-xl">
        @foreach($this->modules as $module)
            <a href="{{ $module['href'] }}" class="bg-white border border-outline-variant rounded-lg p-md hover:border-brand-emerald hover:shadow-md transition-all flex flex-col gap-xs">
                <span class="material-symbols-outlined text-brand-emerald text-[26px]">{{ $module['icon'] }}</span>
                <p class="text-sm font-bold text-brand-forest">{{ $module['title'] }}</p>
                <p class="text-xs text-outline">{{ $module['description'] }}</p>
            </a>
        @endforeach
    </div>

    <div x-data="{
            search: '',
            openIndex: null,
            faqs: {{ Js::from($this->faqs) }},
            get filtered() {
                const term = this.search.toLowerCase().trim();
                if (!term) return this.faqs.map((f, i) => ({ ...f, i }));
                return this.faqs
                    .map((f, i) => ({ ...f, i }))
                    .filter(f => f.question.toLowerCase().includes(term) || f.answer.toLowerCase().includes(term));
            },
        }">
        <h3 class="text-sm font-bold text-brand-forest uppercase mb-md">Foire Aux Questions</h3>
        <div class="bg-white border border-outline-variant rounded-lg p-md mb-md">
            <div class="relative">
                <span class="material-symbols-outlined absolute left-sm top-1/2 -translate-y-1/2 text-outline text-[18px]">search</span>
                <input x-model="search" type="text" placeholder="Rechercher dans l'aide (ex : facture, stock, paie...)" class="w-full pl-9 pr-md py-2.5 border border-outline-variant rounded-lg text-sm bg-white outline-none focus:ring-2 focus:ring-brand-emerald">
            </div>
        </div>
        <div class="bg-white border border-outline-variant rounded-lg px-md">
            <template x-for="faq in filtered" :key="faq.i">
                <div class="faq-item border-b border-outline-variant">
                    <button type="button" @click="openIndex = (openIndex === faq.i ? null : faq.i)" class="w-full flex items-center justify-between py-md text-left">
                        <span class="text-sm font-semibold text-brand-forest" x-text="faq.question"></span>
                        <span class="material-symbols-outlined text-outline kpi-chev" :class="{ 'rot': openIndex === faq.i }">expand_more</span>
                    </button>
                    <div x-show="openIndex === faq.i" x-cloak class="pb-md text-xs text-outline" x-text="faq.answer"></div>
                </div>
            </template>
            <p x-show="filtered.length === 0" x-cloak class="py-lg text-center text-xs text-outline">Aucun résultat pour cette recherche.</p>
        </div>
    </div>

    <div class="mt-xl text-center">
        <a href="/contact-editeur" class="inline-flex items-center gap-xs text-xs font-bold text-brand-emerald hover:underline">
            <span class="material-symbols-outlined text-[18px]">support_agent</span>Vous ne trouvez pas de réponse ? Contactez l'éditeur
        </a>
    </div>
</div>
