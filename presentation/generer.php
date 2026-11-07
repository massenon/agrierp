<?php

/**
 * CONF-2 — GÉNÈRE les SPÉCIMENS du dossier `presentation/` avec le VRAI code d'AgriERP (jamais dessinés à la main).
 *
 *     php presentation/generer.php            # depuis la racine du monorepo (PHP 8.3, `composer install` fait dans agrierp_laravel/)
 *
 * ⚠️ NE TOUCHE JAMAIS À LA BASE DE DÉVELOPPEMENT : avant de charger l'application, les variables d'environnement sont posées
 * sur une base SQLite EN MÉMOIRE (les variables déjà présentes l'emportent sur le `.env`) ; le script refuse de continuer si la
 * connexion n'est pas `:memory:`. Aucun appel réseau : le module MeCeF n'est JAMAIS appelé, les mentions « normalisée » sont
 * des valeurs FICTIVES écrites à la main dans les données de démonstration.
 *
 * Sorties : facture_simple_A4.pdf, facture_normalisee_A4.pdf, document_A4_exemple.pdf, ticket_essai_mecef.pdf et .json,
 * puis les aperçus PNG de la première page de chaque PDF dans `apercus/` si `pdftoppm` est installé.
 */
if (PHP_SAPI !== 'cli') {
    exit("Ce script se lance en ligne de commande.\n");
}

$racine = dirname(__DIR__);
$laravel = $racine.'/agrierp_laravel';

if (! is_file($laravel.'/vendor/autoload.php')) {
    fwrite(STDERR, "Dépendances absentes : lancer `composer install` dans agrierp_laravel/.\n");
    exit(1);
}

// Base EN MÉMOIRE, posée AVANT le chargement de l'application (le `.env` ne peut pas la contredire).
foreach ([
    'APP_ENV' => 'local', 'APP_DEBUG' => 'false', 'DB_CONNECTION' => 'sqlite', 'DB_DATABASE' => ':memory:', 'DB_URL' => '',
    'CACHE_STORE' => 'array', 'SESSION_DRIVER' => 'array', 'QUEUE_CONNECTION' => 'sync', 'LOG_CHANNEL' => 'null',
    'MAIL_MAILER' => 'array', 'MECEF_ACTIF' => 'true', 'SGMEF_TOKEN' => '', 'SGMEF_API_URL' => '',
] as $cle => $valeur) {
    putenv("$cle=$valeur");
    $_ENV[$cle] = $valeur;
    $_SERVER[$cle] = $valeur;
}

require $laravel.'/vendor/autoload.php';

$app = require $laravel.'/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Models\ChartOfAccount;
use App\Models\CompanySetting;
use App\Models\Customer;
use App\Models\FiscalYear;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\PurchaseOrder;
use App\Models\PurchaseOrderLine;
use App\Models\Sale;
use App\Models\SaleLine;
use App\Models\Supplier;
use App\Models\User;
use App\Services\Mecef\ChargeBoitierEltrade;
use App\Services\Mecef\MecefFactureBuilder;
use App\Services\PdfExportService;
use Barryvdh\DomPDF\Facade\Pdf;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;

if (DB::connection()->getDatabaseName() !== ':memory:') {
    fwrite(STDERR, "REFUS : la connexion n'est pas une base SQLite en mémoire. Rien n'est écrit.\n");
    exit(2);
}

Artisan::call('migrate', ['--force' => true]);

$sortie = $racine.'/presentation';
$dateDemo = Carbon\Carbon::create(2026, 11, 8, 10, 30, 0, 'Africa/Porto-Novo');
Carbon\Carbon::setTestNow($dateDemo); // les en-têtes « Généré le … » et les numéros de facture sont stables d'un lancement à l'autre.

// ── Décor de démonstration (AUCUNE donnée réelle) ──────────────────────────────────────────────────────────────
Auth::setUser(User::create(['name' => 'Démonstration', 'username' => 'demo', 'email' => 'demo@exemple.invalid', 'password' => bcrypt('non-utilise'), 'is_active' => true]));

FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert']);
foreach ([['531', 'Caisse', 5], ['411', 'Clients', 4], ['443', 'TVA facturée', 4], ['701', 'Ventes de produits', 7]] as [$code, $libelle, $classe]) {
    ChartOfAccount::create(['code' => $code, 'label' => $libelle, 'class' => $classe, 'is_active' => true]);
}

$IFU_FICTIF = '9999999999999';
CompanySetting::current()->update([
    'company_name' => 'FERME ÉCOLE OLOUWACHEGOUN', 'ifu' => $IFU_FICTIF, 'mecef_mode' => 'emecef', 'mecef_operateur_id' => '1', 'mecef_operateur_nom' => 'Caissier',
]);

$oeufs = ProductCategory::create(['label' => 'Produits avicoles', 'is_active' => true]);
$cereales = ProductCategory::create(['label' => 'Céréales et aliments', 'is_active' => true]);
$plaquette = Product::create(['sku' => 'OEUF-30', 'name' => "Plaquette de 30 œufs", 'category_id' => $oeufs->id, 'unit' => 'plaquette', 'pricing_mode' => 'fourchette', 'price_min' => 2000, 'price_max' => 2500, 'tva_rate' => 18, 'stock_qty' => 200, 'is_active' => true]);
$poulet = Product::create(['sku' => 'POUL-VIF', 'name' => 'Poulet de chair vivant', 'category_id' => $oeufs->id, 'unit' => 'sujet', 'pricing_mode' => 'fourchette', 'price_min' => 3000, 'price_max' => 4000, 'tva_rate' => 18, 'stock_qty' => 80, 'is_active' => true]);
$mais = Product::create(['sku' => 'MAIS-KG', 'name' => 'Maïs en grains', 'category_id' => $cereales->id, 'unit' => 'kg', 'pricing_mode' => 'fourchette', 'price_min' => 250, 'price_max' => 450, 'tva_rate' => 0, 'stock_qty' => 900, 'is_active' => true]);
$aliment = Product::create(['sku' => 'ALIM-PON', 'name' => 'Aliment pondeuse (sac de 25 kg)', 'category_id' => $cereales->id, 'unit' => 'sac', 'pricing_mode' => 'fourchette', 'price_min' => 11000, 'price_max' => 13000, 'tva_rate' => 18, 'stock_qty' => 60, 'is_active' => true]);

/** Une vente de démonstration (mentions MeCeF fictives en `$mecef`) : identifiant FIXE (numéro de facture stable), lignes en montants entiers. */
function vente(string $id, array $champs, array $lignes, array $mecef = []): Sale
{
    $sousTotal = array_sum(array_column($lignes, 2));
    $v = new Sale($champs + ['subtotal' => $sousTotal, 'delivery_fee' => 0, 'status' => 'validee', 'sold_at' => Carbon\Carbon::now()]);
    $v->forceFill(['id' => $id])->save();
    foreach ($lignes as [$produit, $qte, $montant]) {
        SaleLine::create(['sale_id' => $v->id, 'product_id' => $produit->id, 'qty' => $qte, 'unit_price' => $montant / $qte, 'manual_total_amount' => $montant, 'is_manual_price' => true]);
    }

    // Une vente normalisée est FIGÉE (`Sale::booted`, `SaleLine`) : ses mentions fictives se posent APRÈS ses lignes, comme dans les tests.
    if ($mecef !== []) {
        DB::table('sales')->where('id', $id)->update($mecef);
    }

    return $v->fresh(['lines.product', 'customer']);
}

$cooperative = Customer::create(['name' => 'Coopérative DÉMO des éleveurs', 'phone' => '+229 00 00 00 00', 'city' => 'Porto-Novo', 'is_active' => true]);
$societe = Customer::create(['name' => 'Société DÉMO SARL', 'phone' => '+229 00 00 00 01', 'city' => 'Cotonou', 'ifu' => '8888888888888', 'is_active' => true]);

$pdfs = app(PdfExportService::class);

/** Pose le filigrane et le bandeau « SPÉCIMEN » sur CHAQUE page d'un PDF déjà produit par le vrai code, puis l'écrit. */
function specimen(Barryvdh\DomPDF\PDF $pdf, string $fichier, string $bandeau, bool $etroit = false): void
{
    $pdf->render();
    $canvas = $pdf->getDomPDF()->getCanvas();
    $canvas->page_script(function ($numero, $total, $canvas, $metrics) use ($bandeau, $etroit) {
        $police = $metrics->getFont('DejaVu Sans', 'bold');
        $l = $canvas->get_width();
        $h = $canvas->get_height();

        // Filigrane diagonal, translucide, au centre de la page.
        $taille = $etroit ? 40 : 96;
        $texte = 'SPÉCIMEN';
        $largeur = $metrics->getTextWidth($texte, $police, $taille);
        $angle = 45;
        $cx = $l / 2;
        $cy = $h / 2;
        $canvas->set_opacity(0.13);
        $canvas->text($cx - ($largeur / 2) * cos(deg2rad($angle)) + ($taille / 3) * sin(deg2rad($angle)), $cy + ($largeur / 2) * sin(deg2rad($angle)) + ($taille / 3) * cos(deg2rad($angle)), $texte, $police, $taille, [0.75, 0.05, 0.05], 0, 0, -$angle); // angle négatif : le texte MONTE vers la droite
        $canvas->set_opacity(1);

        // Bandeau en haut de page.
        $t = $etroit ? 5.5 : 8;
        $lb = $metrics->getTextWidth($bandeau, $police, $t);
        $canvas->text(max(4, ($l - $lb) / 2), $etroit ? 3 : 14, $bandeau, $police, $t, [0.75, 0.05, 0.05]);
    });
    file_put_contents($fichier, $pdf->output());
}

$BANDEAU = "SPÉCIMEN DE DÉMONSTRATION — aucune facture réelle, rien n'a été transmis à la DGI";

// ── 1. Facture simple A4 ───────────────────────────────────────────────────────────────────────────────────────
$simple = vente('5a1e0001-0000-4000-8000-000000000001', ['customer_id' => $cooperative->id, 'payment_mode' => 'especes', 'discount' => 0, 'total' => 41500, 'facture_type' => 'simple'],
    [[$plaquette, 10, 22500], [$poulet, 4, 14000], [$mais, 20, 5000]]);
specimen(
    $pdfs->render('exports.facture-vente', ['sale' => $simple], 'Facture '.$simple->numero_facture, 'Du '.$simple->date_effective->format('d/m/Y'), 'portrait'),
    $sortie.'/facture_simple_A4.pdf', $BANDEAU,
);

// ── 2. Facture normalisée A4 : identité de l'acheteur, AIB, QR, mentions FICTIVES ───────────────────────────────
$normalisee = vente('5a1e0002-0000-4000-8000-000000000002', [
    'customer_id' => $societe->id, 'payment_mode' => 'virement', 'discount' => 2000, 'total' => 113500, 'facture_type' => 'normalisee',
    'client_nom_facture' => 'Société DÉMO SARL', 'client_ifu' => '8888888888888', 'aib_taux' => '5%',
], [[$aliment, 5, 62500], [$plaquette, 20, 45000], [$mais, 40, 8000]], [
    // Ce que la DGI renverrait : ICI, des valeurs FICTIVES clairement marquées (aucune transmission n'a lieu).
    'mecef_status' => 'transmise', 'mecef_uid' => 'specimen-uid-0000',
    'mecef_qr_ref' => 'SPECIMEN;NE-PAS-UTILISER;FICTIF;9999999999999;20261108103000',
    'mecef_code' => 'SPECIMEN-FICTIF-0000-0000', 'mecef_nim' => 'ED00000000 (FICTIF)', 'mecef_compteurs' => '0/0 FV (FICTIF)',
    'mecef_normalise_le' => '2026-11-08 10:30:00', 'mecef_aib_montant' => 5675,
]);
specimen(
    $pdfs->render('exports.facture-vente', ['sale' => $normalisee], 'Facture '.$normalisee->numero_facture, 'Du '.$normalisee->date_effective->format('d/m/Y'), 'portrait'),
    $sortie.'/facture_normalisee_A4.pdf', $BANDEAU,
);

// ── 3. Document officiel A4 : un bon de commande (en-tête et logo de la ferme) ─────────────────────────────────
$fournisseur = Supplier::create(['name' => 'Provenderie DÉMO', 'category' => 'Aliments', 'phone' => '+229 00 00 00 02', 'email' => 'contact@provenderie-demo.invalid', 'address' => 'Zone industrielle (démonstration)', 'is_active' => true]);
$bon = new PurchaseOrder(['supplier_id' => $fournisseur->id, 'expected_delivery_date' => '2026-11-20', 'status' => 'envoye']);
$bon->forceFill(['id' => '5a1e0003-0000-4000-8000-000000000003'])->save();
foreach ([[$aliment, 40, 11500], [$mais, 500, 300]] as [$produit, $qte, $pu]) {
    PurchaseOrderLine::create(['purchase_order_id' => $bon->id, 'product_id' => $produit->id, 'qty' => $qte, 'estimated_unit_price' => $pu]);
}
$bon = PurchaseOrder::with(['supplier', 'lines.product'])->find($bon->id);
specimen(
    $pdfs->render('exports.bon-commande', [
        'purchaseOrder' => $bon, 'total' => $bon->lines->sum(fn ($l) => $l->qty * $l->estimated_unit_price), 'statusLabel' => 'Envoyé / En cours',
    ], 'Bon de Commande — '.strtoupper(substr($bon->id, 0, 8)), $bon->created_at->format('d/m/Y'), 'portrait'),
    $sortie.'/document_A4_exemple.pdf', $BANDEAU,
);

// ── 4. Ticket d'essai MeCeF (80 mm) + charge utile du pilote Eltrade CC300 ─────────────────────────────────────
$essai = vente('5a1e0004-0000-4000-8000-000000000004', [
    'customer_id' => $societe->id, 'payment_mode' => 'especes', 'discount' => 0, 'total' => 21300, 'facture_type' => 'normalisee',
    'client_nom_facture' => 'Client ESSAI (spécimen)', 'client_ifu' => '8888888888888', 'aib_taux' => '1%',
], [[$plaquette, 3, 6900], [$poulet, 2, 7000], [$mais, 25, 7400]], [
    'mecef_status' => 'transmise', 'mecef_qr_ref' => 'SPECIMEN;ESSAI-MACHINE;FICTIF;9999999999999;20261108103000',
    'mecef_code' => 'SPECIMEN-FICTIF-ESSAI', 'mecef_nim' => 'ED00000000 (FICTIF)', 'mecef_compteurs' => '0/0 FV (FICTIF)',
]);

$enLigne = (new MecefFactureBuilder)->pourVente($essai, ['ifu' => $IFU_FICTIF, 'operateur_id' => '1', 'operateur_nom' => 'Caissier']);
$charge = (new ChargeBoitierEltrade)->depuisChargeEnLigne($enLigne, 'ESSAI-1', 'ESSAI SPECIMEN');
file_put_contents($sortie.'/ticket_essai_mecef.json', json_encode($charge, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES)."\n");

$hauteur = 480 + 24 * count($charge['products']);
$ticket = Pdf::loadView('exports.ticket-essai-mecef', ['charge' => $charge, 'vente' => $essai, 'ifu' => $IFU_FICTIF, 'date' => Carbon\Carbon::now()])
    ->setPaper([0, 0, 226.77, $hauteur]); // 80 mm de large
specimen($ticket, $sortie.'/ticket_essai_mecef.pdf', 'SPÉCIMEN — ESSAI', true);

// ── Aperçus PNG (première page de chaque PDF) ──────────────────────────────────────────────────────────────────
if (trim((string) shell_exec('command -v pdftoppm')) !== '') {
    foreach (['facture_simple_A4', 'facture_normalisee_A4', 'document_A4_exemple', 'ticket_essai_mecef'] as $nom) {
        $r = $nom === 'ticket_essai_mecef' ? 110 : 75;
        shell_exec('pdftoppm -png -r '.$r.' -f 1 -l 1 -singlefile '.escapeshellarg("$sortie/$nom.pdf").' '.escapeshellarg("$sortie/apercus/$nom"));
    }
} else {
    fwrite(STDERR, "pdftoppm absent : aperçus PNG non régénérés (les PDF le sont).\n");
}

echo "Spécimens écrits dans $sortie (base en mémoire, rien d'autre n'a été modifié).\n";
