@verbatim
<style>
.text-xs{font-size:0.85rem !important;}
body{font-family:'Inter',sans-serif;}
.material-symbols-outlined{font-variation-settings:'FILL' 0,'wght' 400,'GRAD' 0,'opsz' 24;}
.welcome-bg{background:linear-gradient(160deg,#052e16 0%,#00210d 100%);}
.fade-up{animation:fadeUp .8s ease-out forwards;opacity:0;}
.fade-up.d1{animation-delay:.1s;} .fade-up.d2{animation-delay:.25s;}
.fade-up.d3{animation-delay:.4s;} .fade-up.d4{animation-delay:.55s;}
@keyframes fadeUp{from{opacity:0;transform:translateY(14px);}to{opacity:1;transform:translateY(0);}}
</style>
@endverbatim

<div class="welcome-bg min-h-screen w-full flex flex-col text-white">
<header class="flex items-center justify-between px-4 md:px-10 py-4">
    <div class="flex items-center gap-2"><span class="material-symbols-outlined text-[#a6f2d1] text-[22px]">agriculture</span><span class="font-bold text-sm">LogiAgri<span class="text-[#FFD55F]">ERP</span></span></div>
    <div class="flex items-center gap-3 text-xs text-white/70">
        <span class="flex items-center gap-1"><span class="material-symbols-outlined text-[16px]">translate</span>Français</span>
        <span class="font-bold tracking-wider">v1.0.0</span>
    </div>
</header>
<main class="flex-1 flex flex-col items-center justify-center text-center px-4 py-10">
    <div class="fade-up d1 w-24 h-24 md:w-28 md:h-28 rounded-full bg-white/5 border border-white/20 flex items-center justify-center mb-6">
        <span class="material-symbols-outlined text-[#a6f2d1]" style="font-size:56px;">agriculture</span>
    </div>
    <h1 class="fade-up d2 font-extrabold text-3xl md:text-5xl leading-tight max-w-3xl">Bienvenue sur <span class="text-[#FFD55F]">Agri</span>ERP</h1>
    <p class="fade-up d3 text-white/70 text-sm md:text-base max-w-xl mt-4 leading-relaxed">
        La solution intégrée pour gérer votre exploitation agricole : ventes, stocks, comptabilité SYSCOHADA et élevage — au comptoir comme au champ.
    </p>
    <div class="fade-up d4 flex flex-col sm:flex-row items-center gap-3 mt-8">
        <a wire:navigate href="{{ route('public.presentation') }}" class="w-64 sm:w-auto text-center px-8 py-2.5 rounded-full bg-[#065f46] hover:bg-[#054d3a] font-bold text-sm shadow-lg transition-all active:scale-[0.98]">Voir les Fonctionnalités</a>
        <a wire:navigate href="{{ route('login') }}" class="w-64 sm:w-auto text-center px-8 py-2.5 rounded-full border border-white/40 hover:bg-white/10 font-bold text-sm transition-all active:scale-[0.98]">Se connecter</a>
    </div>
    <div class="fade-up d4 grid grid-cols-2 md:grid-cols-4 gap-3 mt-12 max-w-2xl w-full">
        <div class="flex flex-col items-center gap-1 bg-white/5 border border-white/10 rounded-lg py-4"><span class="material-symbols-outlined text-[#a6f2d1] text-[22px]">point_of_sale</span><span class="text-[10px] font-bold uppercase tracking-wide text-white/70">POS &amp; Devis</span></div>
        <div class="flex flex-col items-center gap-1 bg-white/5 border border-white/10 rounded-lg py-4"><span class="material-symbols-outlined text-[#a6f2d1] text-[22px]">inventory_2</span><span class="text-[10px] font-bold uppercase tracking-wide text-white/70">Stocks</span></div>
        <div class="flex flex-col items-center gap-1 bg-white/5 border border-white/10 rounded-lg py-4"><span class="material-symbols-outlined text-[#a6f2d1] text-[22px]">pets</span><span class="text-[10px] font-bold uppercase tracking-wide text-white/70">Élevage &amp; Soins</span></div>
        <div class="flex flex-col items-center gap-1 bg-white/5 border border-white/10 rounded-lg py-4"><span class="material-symbols-outlined text-[#a6f2d1] text-[22px]">account_balance</span><span class="text-[10px] font-bold uppercase tracking-wide text-white/70">Comptabilité</span></div>
    </div>
</main>
<footer class="text-center pb-6 text-[10px] text-white/40 tracking-wider">Version 1.0.0 &nbsp;•&nbsp; Projet PAEB &nbsp;•&nbsp; Cabinet FAGUEZ SARL &nbsp;•&nbsp; Dr MASSENON Rhodes</footer>
</div>
