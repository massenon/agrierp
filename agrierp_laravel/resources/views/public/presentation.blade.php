@verbatim
<style>
.text-xs{font-size:0.85rem !important;}
body{font-family:'Inter',sans-serif;}
.material-symbols-outlined{font-variation-settings:'FILL' 0,'wght' 400,'GRAD' 0,'opsz' 24;}
.hero-bg{background:linear-gradient(160deg,#052e16 0%,#00210d 100%);}
.module-card{transition:transform .25s ease, box-shadow .25s ease;}
.module-card:hover{transform:translateY(-4px); box-shadow:0 12px 24px rgba(5,46,22,0.12);}
</style>
@endverbatim

<div class="bg-white text-[#191c1d]">
<!-- NAV -->
<header class="sticky top-0 z-50 bg-white/90 backdrop-blur border-b border-[#bec9c2]/40">
    <div class="max-w-7xl mx-auto flex items-center justify-between px-4 md:px-8 py-3">
        <div class="flex items-center gap-2">
            <span class="material-symbols-outlined text-[#065f46]" style="font-size:26px;">agriculture</span>
            <span class="font-black text-lg text-[#052e16]">Agri<span class="text-[#FFD55F]">ERP</span></span>
        </div>
        <nav class="hidden md:flex items-center gap-6 text-xs font-semibold text-[#6f7973]">
            <a href="#modules" class="hover:text-[#065f46]">Modules</a>
            <a href="#features" class="hover:text-[#065f46]">Fonctionnalités</a>
            <a href="#architecture" class="hover:text-[#065f46]">Architecture</a>
        </nav>
        <div class="flex items-center gap-2">
            <a wire:navigate href="{{ route('public.welcome') }}" class="hidden sm:inline text-xs font-semibold text-[#6f7973] hover:text-[#065f46] px-3 py-2">Retour</a>
            <a wire:navigate href="{{ route('login') }}" class="text-xs font-bold bg-[#065f46] hover:bg-[#052e16] text-white px-5 py-2.5 rounded-full transition-colors">Se connecter</a>
        </div>
    </div>
</header>

<!-- HERO -->
<section class="hero-bg text-white">
    <div class="max-w-5xl mx-auto text-center px-4 py-20 md:py-28">
        <span class="inline-block text-[10px] font-bold uppercase tracking-widest bg-white/10 border border-white/20 rounded-full px-4 py-1.5 mb-6">AgriERP · Votre logiciel de gestion intégrée</span>
        <h1 class="text-3xl md:text-5xl font-extrabold leading-tight">Une plateforme unique pour piloter <span class="text-[#FFD55F]">toute votre exploitation agricole</span>.</h1>
        <p class="text-white/70 text-sm md:text-base mt-6 max-w-2xl mx-auto leading-relaxed">
            Centralisez vos ventes, votre comptabilité, vos stocks, votre élevage, vos finances et votre administration dans une seule solution, pensée pour les exploitations agro-pastorales africaines.
        </p>
        <div class="flex flex-col sm:flex-row items-center justify-center gap-3 mt-10">
            <a href="#modules" class="w-56 sm:w-auto px-8 py-3 rounded-full bg-[#FFD55F] text-[#052e16] font-bold text-sm hover:bg-yellow-400 transition-colors">Voir les Modules</a>
            <a wire:navigate href="{{ route('login') }}" class="w-56 sm:w-auto px-8 py-3 rounded-full border border-white/40 text-white font-bold text-sm hover:bg-white/10 transition-colors">Se connecter</a>
        </div>
    </div>
</section>

<!-- MODULES -->
<section id="modules" class="max-w-7xl mx-auto px-4 md:px-8 py-16 md:py-24">
    <div class="text-center mb-12">
        <span class="text-[11px] font-bold uppercase tracking-widest text-[#065f46]">Modules</span>
        <h2 class="text-2xl md:text-3xl font-extrabold text-[#052e16] mt-2">Tout ce dont votre ferme a besoin</h2>
    </div>
    <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
        <div class="module-card bg-white border border-[#bec9c2]/50 rounded-xl p-5 text-center">
            <span class="material-symbols-outlined text-[#065f46]" style="font-size:32px;">account_balance</span>
            <p class="text-xs font-bold mt-3">Comptabilité SYSCOHADA</p>
        </div>
        <div class="module-card bg-white border border-[#bec9c2]/50 rounded-xl p-5 text-center">
            <span class="material-symbols-outlined text-[#065f46]" style="font-size:32px;">point_of_sale</span>
            <p class="text-xs font-bold mt-3">POS &amp; Devis</p>
        </div>
        <div class="module-card bg-white border border-[#bec9c2]/50 rounded-xl p-5 text-center">
            <span class="material-symbols-outlined text-[#065f46]" style="font-size:32px;">pets</span>
            <p class="text-xs font-bold mt-3">Élevage &amp; Soins</p>
        </div>
        <div class="module-card bg-white border border-[#bec9c2]/50 rounded-xl p-5 text-center">
            <span class="material-symbols-outlined text-[#065f46]" style="font-size:32px;">inventory_2</span>
            <p class="text-xs font-bold mt-3">Stocks</p>
        </div>
        <div class="module-card bg-white border border-[#bec9c2]/50 rounded-xl p-5 text-center">
            <span class="material-symbols-outlined text-[#065f46]" style="font-size:32px;">payments</span>
            <p class="text-xs font-bold mt-3">Finance</p>
        </div>
        <div class="module-card bg-white border border-[#bec9c2]/50 rounded-xl p-5 text-center">
            <span class="material-symbols-outlined text-[#065f46]" style="font-size:32px;">summarize</span>
            <p class="text-xs font-bold mt-3">Rapports</p>
        </div>
        <div class="module-card bg-white border border-[#bec9c2]/50 rounded-xl p-5 text-center">
            <span class="material-symbols-outlined text-[#065f46]" style="font-size:32px;">badge</span>
            <p class="text-xs font-bold mt-3">Administration &amp; RH</p>
        </div>
        <div class="module-card bg-white border border-[#bec9c2]/50 rounded-xl p-5 text-center">
            <span class="material-symbols-outlined text-[#065f46]" style="font-size:32px;">sync</span>
            <p class="text-xs font-bold mt-3">Synchronisation Offline</p>
        </div>
    </div>
</section>

<!-- SCREENSHOTS -->
<section class="bg-[#F8F9FA] py-16 md:py-24">
    <div class="max-w-7xl mx-auto px-4 md:px-8">
        <div class="text-center mb-12">
            <span class="text-[11px] font-bold uppercase tracking-widest text-[#065f46]">Aperçu</span>
            <h2 class="text-2xl md:text-3xl font-extrabold text-[#052e16] mt-2">Une interface pensée pour le terrain</h2>
        </div>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
            <div class="bg-white rounded-xl border border-[#bec9c2]/50 overflow-hidden shadow-sm">
                <div class="h-40 bg-[#f3f4f5] flex items-center justify-center p-3">
                    <svg viewBox="0 0 240 140" class="w-full h-full" xmlns="http://www.w3.org/2000/svg">
                        <rect x="0" y="0" width="240" height="140" rx="6" fill="#ffffff" stroke="#bec9c2" stroke-width="1"/>
                        <rect x="0" y="0" width="52" height="140" rx="6" fill="#052e16"/>
                        <rect x="10" y="14" width="32" height="6" rx="2" fill="#FFD55F"/>
                        <rect x="10" y="32" width="32" height="4" rx="2" fill="#ffffff" opacity="0.5"/>
                        <rect x="10" y="42" width="32" height="4" rx="2" fill="#ffffff" opacity="0.35"/>
                        <rect x="10" y="52" width="32" height="4" rx="2" fill="#ffffff" opacity="0.35"/>
                        <rect x="10" y="62" width="32" height="4" rx="2" fill="#ffffff" opacity="0.35"/>
                        <rect x="62" y="10" width="168" height="10" rx="3" fill="#e5e7eb"/>
                        <rect x="62" y="30" width="38" height="26" rx="4" fill="#065f46" opacity="0.12"/>
                        <rect x="106" y="30" width="38" height="26" rx="4" fill="#2563EB" opacity="0.12"/>
                        <rect x="150" y="30" width="38" height="26" rx="4" fill="#FFD55F" opacity="0.25"/>
                        <rect x="194" y="30" width="36" height="26" rx="4" fill="#BA1A1A" opacity="0.10"/>
                        <rect x="62" y="66" width="102" height="62" rx="4" fill="#ffffff" stroke="#e5e7eb" stroke-width="1"/>
                        <polyline points="70,110 90,95 110,100 130,80 150,88 165,72" fill="none" stroke="#065f46" stroke-width="2"/>
                        <rect x="170" y="66" width="60" height="62" rx="4" fill="#ffffff" stroke="#e5e7eb" stroke-width="1"/>
                        <rect x="178" y="74" width="44" height="6" rx="2" fill="#f3f4f5"/>
                        <rect x="178" y="86" width="44" height="6" rx="2" fill="#f3f4f5"/>
                        <rect x="178" y="98" width="44" height="6" rx="2" fill="#f3f4f5"/>
                    </svg>
                </div>
                <p class="text-xs font-bold p-4">Tableau de bord Desktop</p>
            </div>
            <div class="bg-white rounded-xl border border-[#bec9c2]/50 overflow-hidden shadow-sm">
                <div class="h-40 bg-[#f3f4f5] flex items-center justify-center p-3">
                    <svg viewBox="0 0 240 140" class="w-full h-full" xmlns="http://www.w3.org/2000/svg">
                        <rect x="0" y="0" width="240" height="140" rx="6" fill="#ffffff" stroke="#bec9c2" stroke-width="1"/>
                        <rect x="8" y="8" width="150" height="10" rx="3" fill="#e5e7eb"/>
                        <rect x="8" y="26" width="46" height="36" rx="4" fill="#065f46" opacity="0.10"/>
                        <rect x="58" y="26" width="46" height="36" rx="4" fill="#065f46" opacity="0.10"/>
                        <rect x="108" y="26" width="46" height="36" rx="4" fill="#065f46" opacity="0.10"/>
                        <rect x="8" y="68" width="46" height="36" rx="4" fill="#065f46" opacity="0.10"/>
                        <rect x="58" y="68" width="46" height="36" rx="4" fill="#065f46" opacity="0.10"/>
                        <rect x="108" y="68" width="46" height="36" rx="4" fill="#065f46" opacity="0.10"/>
                        <rect x="164" y="8" width="68" height="124" rx="4" fill="#052e16"/>
                        <rect x="172" y="18" width="52" height="6" rx="2" fill="#ffffff" opacity="0.6"/>
                        <rect x="172" y="30" width="52" height="1" fill="#ffffff" opacity="0.2"/>
                        <rect x="172" y="38" width="34" height="5" rx="2" fill="#ffffff" opacity="0.4"/>
                        <rect x="172" y="48" width="34" height="5" rx="2" fill="#ffffff" opacity="0.4"/>
                        <rect x="172" y="58" width="34" height="5" rx="2" fill="#ffffff" opacity="0.4"/>
                        <rect x="172" y="100" width="52" height="20" rx="4" fill="#FFD55F"/>
                    </svg>
                </div>
                <p class="text-xs font-bold p-4">Caisse POS</p>
            </div>
            <div class="bg-white rounded-xl border border-[#bec9c2]/50 overflow-hidden shadow-sm">
                <div class="h-40 bg-[#f3f4f5] flex items-center justify-center p-3">
                    <svg viewBox="0 0 240 140" class="h-full" xmlns="http://www.w3.org/2000/svg">
                        <rect x="88" y="4" width="64" height="132" rx="10" fill="#052e16"/>
                        <rect x="93" y="12" width="54" height="108" rx="3" fill="#ffffff"/>
                        <rect x="93" y="12" width="54" height="16" rx="3" fill="#065f46"/>
                        <rect x="99" y="17" width="20" height="5" rx="2" fill="#ffffff" opacity="0.8"/>
                        <rect x="99" y="34" width="42" height="12" rx="3" fill="#065f46" opacity="0.10"/>
                        <rect x="99" y="50" width="42" height="12" rx="3" fill="#065f46" opacity="0.10"/>
                        <rect x="99" y="66" width="42" height="12" rx="3" fill="#065f46" opacity="0.10"/>
                        <rect x="99" y="86" width="42" height="26" rx="3" fill="#f3f4f5"/>
                        <rect x="119" y="123" width="14" height="3" rx="1.5" fill="#bec9c2"/>
                    </svg>
                </div>
                <p class="text-xs font-bold p-4">Application Mobile</p>
            </div>
        </div>
    </div>
</section>

<!-- FEATURES -->
<section id="features" class="max-w-7xl mx-auto px-4 md:px-8 py-16 md:py-24">
    <div class="text-center mb-12">
        <span class="text-[11px] font-bold uppercase tracking-widest text-[#065f46]">Fonctionnalités</span>
        <h2 class="text-2xl md:text-3xl font-extrabold text-[#052e16] mt-2">Conçu pour la fiabilité et la conformité</h2>
    </div>
    <div class="grid grid-cols-2 md:grid-cols-4 gap-4 text-xs font-semibold">
        <div class="flex items-center gap-2 bg-white border border-[#bec9c2]/50 rounded-lg p-4"><span class="material-symbols-outlined text-[#065f46] text-[20px]">cloud_off</span>Offline First</div>
        <div class="flex items-center gap-2 bg-white border border-[#bec9c2]/50 rounded-lg p-4"><span class="material-symbols-outlined text-[#065f46] text-[20px]">sync</span>Synchronisation automatique</div>
        <div class="flex items-center gap-2 bg-white border border-[#bec9c2]/50 rounded-lg p-4"><span class="material-symbols-outlined text-[#065f46] text-[20px]">account_balance</span>SYSCOHADA</div>
        <div class="flex items-center gap-2 bg-white border border-[#bec9c2]/50 rounded-lg p-4"><span class="material-symbols-outlined text-[#065f46] text-[20px]">picture_as_pdf</span>Rapports PDF</div>
        <div class="flex items-center gap-2 bg-white border border-[#bec9c2]/50 rounded-lg p-4"><span class="material-symbols-outlined text-[#065f46] text-[20px]">table_view</span>Export Excel</div>
        <div class="flex items-center gap-2 bg-white border border-[#bec9c2]/50 rounded-lg p-4"><span class="material-symbols-outlined text-[#065f46] text-[20px]">group</span>Multi-utilisateurs</div>
        <div class="flex items-center gap-2 bg-white border border-[#bec9c2]/50 rounded-lg p-4"><span class="material-symbols-outlined text-[#065f46] text-[20px]">receipt_long</span>Facturation normalisée</div>
        <div class="flex items-center gap-2 bg-white border border-[#bec9c2]/50 rounded-lg p-4"><span class="material-symbols-outlined text-[#065f46] text-[20px]">smartphone</span>Mobile Money</div>
    </div>
</section>

<!-- ARCHITECTURE -->
<section id="architecture" class="bg-[#052e16] text-white py-16 md:py-24">
    <div class="max-w-7xl mx-auto px-4 md:px-8 text-center">
        <span class="text-[11px] font-bold uppercase tracking-widest text-[#a6f2d1]">Architecture</span>
        <h2 class="text-2xl md:text-3xl font-extrabold mt-2 mb-10">Une stack moderne et robuste</h2>
        <div class="grid grid-cols-2 md:grid-cols-4 gap-4 text-xs font-bold">
            <div class="bg-white/5 border border-white/10 rounded-lg p-4">Flutter Desktop</div>
            <div class="bg-white/5 border border-white/10 rounded-lg p-4">Flutter Mobile</div>
            <div class="bg-white/5 border border-white/10 rounded-lg p-4">Laravel / Livewire</div>
            <div class="bg-white/5 border border-white/10 rounded-lg p-4">SQLite / PostgreSQL</div>
        </div>
        <p class="text-white/50 text-[11px] mt-6">Clean Architecture — API REST — Offline-first Sync Engine</p>
    </div>
</section>

<!-- CTA FINAL -->
<section class="py-16 text-center px-4">
    <h2 class="text-xl md:text-2xl font-extrabold text-[#052e16]">Prêt à moderniser la gestion de votre ferme ?</h2>
    <a wire:navigate href="{{ route('login') }}" class="inline-block mt-6 px-8 py-3 rounded-full bg-[#065f46] hover:bg-[#052e16] text-white font-bold text-sm transition-colors">Se connecter à AgriERP</a>
</section>

<footer class="border-t border-[#bec9c2]/40 py-8 text-center text-[10px] text-[#6f7973]">
    Version 1.0.0 &nbsp;•&nbsp; Projet PAEB &nbsp;•&nbsp; Cabinet FAGUEZ SARL &nbsp;•&nbsp; Dr MASSENON Rhodes
</footer>
</div>
