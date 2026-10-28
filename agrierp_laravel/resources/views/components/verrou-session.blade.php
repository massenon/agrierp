{{--
    Sprint VW (VW2) — ÉCRAN DE VERROUILLAGE de l'application web, et sa minuterie d'inactivité.

    Posé UNE fois dans `layouts/app.blade.php` (jamais dans `guest` : ni connexion ni pages publiques) ; la page
    `/verrouillage` le rend aussi, en `page=true`. Présentation = celle de la page de connexion
    (`livewire/auth/login.blade.php` : image, logo, titre). Le secret est le MOT DE PASSE du compte.

    ⚠️ SURCOUCHE, PAS REMPLACEMENT : l'écran recouvre l'application sans la démonter. Un formulaire Livewire non
    enregistré garde sa saisie ; au déverrouillage rien n'est re-rendu. Ce n'est PAS ce qui protège les données : c'est
    `SessionVerrouillee`, qui refuse côté serveur toute requête tant que la session est verrouillée.

    Textes COMMUNS avec le poste (garde-fou `verrou_parite_web_test.dart`) : « Application verrouillée », « NOM
    D'UTILISATEUR », « DÉVERROUILLER », « Session de … Saisissez votre … », « Trop d'essais. Réessayez dans … ».
--}}
@props(['page' => false, 'verrouille' => false, 'minutes' => 5, 'nom' => null, 'identifiant' => null])
@php
    $utilisateur = auth()->user();
    $nom ??= $utilisateur->name;
    $identifiant ??= $utilisateur->username ?: $utilisateur->email;
@endphp
<div
    data-verrou-minutes="{{ (int) $minutes }}"
    dusk="ecran-verrouillage"
    x-data="verrouSession(@js([
        'minutes' => (int) $minutes,
        'verrouille' => (bool) $verrouille,
        'page' => (bool) $page,
        'erreur' => (string) ($errors->first('password') ?? ''),
        'urlVerrouiller' => route('session.verrouiller'),
        'urlDeverrouiller' => route('session.deverrouiller'),
        'urlConnexion' => route('login'),
        'jeton' => csrf_token(),
    ]))"
    x-show="verrouille"
    @unless($verrouille) x-cloak @endunless
    role="dialog" aria-modal="true" aria-label="Application verrouillée"
    class="fixed inset-0 z-[300] w-full overflow-y-auto bg-white flex flex-col lg:flex-row">

    <aside class="relative hidden lg:flex lg:w-[50%] flex-col justify-between p-8 overflow-hidden" style="background: linear-gradient(180deg, rgba(5,46,22,0.10) 0%, rgba(0,33,13,0.55) 100%), url('{{ asset('assets/images/image_login.png') }}'); background-size: cover; background-position: center;">
        <div class="relative z-10 flex items-center gap-2">
            <span class="material-symbols-outlined text-accent-yellow" style="font-size:26px;">agriculture</span>
            <span class="text-white font-extrabold text-lg">Agri<span class="text-brand-maize">ERP</span></span>
        </div>
        <div class="relative z-10 flex-1"></div>
        <div class="relative z-10 text-center space-y-1 border-t border-white/10 pt-4">
            <p class="text-white/70 text-[10px] uppercase tracking-widest font-bold">Projet d'Appui à l'Entrepreneuriat au Bénin (PAEB)</p>
            <p class="text-white/50 text-[10px] uppercase tracking-widest font-semibold">PAEB &nbsp;&middot;&nbsp; CABINET FAGUEZ SARL</p>
        </div>
    </aside>

    <main class="flex-1 flex flex-col justify-between p-6 lg:p-8 bg-white">
        <div class="flex justify-end text-xs text-outline"><span class="font-bold tracking-wider px-2">v1.0.0</span></div>

        <div class="my-auto mx-auto w-full max-w-[440px] space-y-5">
            <div class="flex flex-col items-center text-center gap-1">
                <div class="flex items-center gap-2">
                    <span class="material-symbols-outlined text-brand-emerald" style="font-size:38px;">agriculture</span>
                    <div class="flex flex-col items-start leading-none">
                        <span class="text-[22px] font-black text-brand-forest tracking-tight">Agri<span class="text-brand-maize-ink">ERP</span></span>
                        <span class="text-[9px] uppercase tracking-widest text-brand-emerald font-extrabold mt-0.5">Ferme Olouwachegoun</span>
                    </div>
                </div>
                <p class="text-[10px] text-brand-emerald font-bold uppercase tracking-[0.15em] border-t border-brand-emerald/10 pt-2 mt-1 w-full">Votre logiciel de gestion intégrée</p>
            </div>

            <div class="space-y-2">
                <h2 class="text-brand-forest text-xl font-bold leading-tight flex items-center gap-2"><span class="material-symbols-outlined text-brand-emerald">lock</span>Application verrouillée</h2>
                <p class="text-outline text-xs leading-relaxed">Session de {{ $nom }}. Saisissez votre mot de passe pour reprendre votre travail.</p>
            </div>

            <div x-show="erreur" x-cloak dusk="verrou-message" role="alert"
                class="bg-error-bg border border-error-deep/30 text-error-deep text-xs rounded-lg px-4 py-2 flex items-center gap-2">
                <span class="material-symbols-outlined text-[18px]">lock_clock</span>
                <span x-text="attente > 0 ? ('Trop d\'essais. Réessayez dans ' + formaterAttente(attente) + '.') : erreur">{{ $errors->first('password') }}</span>
            </div>

            <form method="POST" action="{{ route('session.deverrouiller') }}" @submit.prevent="soumettre()" class="space-y-4" novalidate>
                @csrf
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold tracking-wider mb-1" for="verrou-identifiant">NOM D'UTILISATEUR</label>
                    <div class="relative">
                        <span class="material-symbols-outlined absolute left-4 top-1/2 -translate-y-1/2 text-outline text-[18px]">person</span>
                        <input id="verrou-identifiant" type="text" value="{{ $identifiant }}" readonly tabindex="-1"
                            class="w-full pl-11 pr-4 py-2.5 border border-outline-variant rounded-lg bg-surface-zebra text-outline outline-none text-xs h-11">
                    </div>
                </div>
                <div>
                    <label class="block text-[10px] text-brand-forest font-bold tracking-wider mb-1" for="verrou-password">MOT DE PASSE</label>
                    <div class="relative" x-data="{ visible: false }">
                        <span class="material-symbols-outlined absolute left-4 top-1/2 -translate-y-1/2 text-outline text-[18px]">lock</span>
                        <input x-ref="champ" x-model="motDePasse" id="verrou-password" name="password" dusk="verrou-password"
                            :type="visible ? 'text' : 'password'" autocomplete="current-password" placeholder="••••••••"
                            class="w-full pl-11 pr-11 py-2.5 border border-outline-variant rounded-lg focus:ring-2 focus:ring-brand-emerald outline-none text-xs h-11">
                        <button type="button" @click="visible = !visible" class="absolute right-4 top-1/2 -translate-y-1/2 text-outline hover:text-brand-forest">
                            <span class="material-symbols-outlined text-[18px]" x-text="visible ? 'visibility_off' : 'visibility'">visibility</span>
                        </button>
                    </div>
                </div>
                <button type="submit" dusk="verrou-deverrouiller" :disabled="envoi || attente > 0"
                    class="w-full bg-brand-emerald hover:bg-brand-forest disabled:opacity-50 text-white font-bold h-11 rounded-lg shadow-sm active:scale-[0.98] transition-all flex items-center justify-center gap-2 text-xs uppercase tracking-wider">
                    <span x-show="!envoi" class="material-symbols-outlined text-[16px]">lock_open</span>
                    <span x-show="envoi" x-cloak class="material-symbols-outlined text-[16px] animate-spin">progress_activity</span>
                    <span>DÉVERROUILLER</span>
                </button>
            </form>

            <form method="POST" action="{{ route('logout') }}" class="text-center">
                @csrf
                <button type="submit" dusk="verrou-deconnexion" class="text-xs font-semibold text-brand-emerald hover:underline">Se déconnecter</button>
            </form>
        </div>

        <div class="border-t border-outline-variant/40 pt-4 flex items-center justify-center text-[10px] text-outline">
            <span>© {{ now()->year }} AgriERP — Projet d'Appui à l'Entrepreneuriat au Bénin (PAEB) — Accompagnement : Cabinet FAGUEZ SARL — Édité par Dr&nbsp;MASSENON&nbsp;Rhodes</span>
        </div>
    </main>
</div>
