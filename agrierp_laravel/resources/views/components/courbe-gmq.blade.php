@props([
    'series' => [],   // ['cle' => [?float, ...]] — une valeur `null` est une semaine sans deux pesées
])
@php
    /*
     * Ticket H11 — courbes de GMQ hebdomadaire du poste (`_CourbesGmqPainter`, dashboard_elevage_screen.dart), en SVG
     * comme les graphiques du tableau de bord. Mêmes règles que le poste :
     * - UNE SEMAINE SANS DEUX PESÉES NE TRACE RIEN : le segment est absent, jamais relié par-dessus le trou (ce serait
     *   dessiner une croissance qui n'a pas été mesurée) ;
     * - échelle sur le maximum de toutes les séries, axe des abscisses S1..Sn.
     * Couleurs des traits : attributs SVG (pas des classes Tailwind), tableau statique par clé de série.
     */
    $couleurs = [
        'cuniculture' => '#065f46',   // brand-emerald
        'aviculture' => '#2563EB',    // info-blue
        'porciculture' => '#FFD55F',  // accent-yellow
        'suivie' => '#065f46',
    ];
    $largeur = 600;
    $hauteur = 192;
    $base = $hauteur - 24;
    $toutes = collect($series)->flatten()->filter(fn ($v) => $v !== null);
    $longueur = collect($series)->map(fn ($s) => count($s))->max() ?? 0;
    $maximum = $toutes->isEmpty() ? 0 : $toutes->max();
    $pas = $longueur <= 1 ? 0 : ($largeur - 30) / ($longueur - 1);
    $x = fn (int $i) => round(15 + $pas * $i, 1);
    $y = fn (float $v) => round($maximum <= 0 ? $base - 10 : $base - ($v / $maximum) * ($base - 15), 1);
@endphp
<svg viewBox="0 0 {{ $largeur }} {{ $hauteur }}" class="w-full h-48" role="img">
    <line x1="0" y1="{{ $base }}" x2="{{ $largeur }}" y2="{{ $base }}" stroke="#bec9c2" stroke-width="1"/>
    @if($toutes->isEmpty())
        <text x="{{ $largeur / 2 }}" y="{{ $base / 2 }}" text-anchor="middle" font-size="13" font-style="italic" fill="#6f7973">— Pas encore assez de pesées pour tracer une courbe —</text>
    @else
        @foreach($series as $cle => $valeurs)
            @php $couleur = $couleurs[$cle] ?? '#6f7973'; @endphp
            @for($i = 0; $i < count($valeurs) - 1; $i++)
                @if($valeurs[$i] !== null && $valeurs[$i + 1] !== null)
                    <line x1="{{ $x($i) }}" y1="{{ $y($valeurs[$i]) }}" x2="{{ $x($i + 1) }}" y2="{{ $y($valeurs[$i + 1]) }}" stroke="{{ $couleur }}" stroke-width="2.5"/>
                @endif
            @endfor
            @foreach($valeurs as $i => $v)
                @if($v !== null)
                    <circle cx="{{ $x($i) }}" cy="{{ $y($v) }}" r="3.5" fill="{{ $couleur }}"/>
                @endif
            @endforeach
        @endforeach
        <g font-size="9" fill="#6f7973" text-anchor="middle">
            @for($i = 0; $i < $longueur; $i++)
                <text x="{{ $x($i) }}" y="{{ $base + 15 }}">S{{ $i + 1 }}</text>
            @endfor
        </g>
    @endif
</svg>
