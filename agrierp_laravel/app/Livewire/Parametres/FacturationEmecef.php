<?php

namespace App\Livewire\Parametres;

use App\Models\CompanySetting;
use App\Services\Mecef\MecefConfigurationTesteur;
use App\Services\Mecef\MecefReglage;
use App\Services\Mecef\MecefReglageService;
use App\Support\MecefMode;
use Illuminate\Validation\ValidationException;
use Illuminate\Support\Facades\Gate;
use Livewire\Component;

/**
 * Paramètres > « Facturation normalisée (e-MECeF) » — LE formulaire où la ferme renseigne le mode, l'IFU, l'adresse de l'API,
 * l'opérateur et le JETON de son compte e-MECeF, puis TESTE sa configuration avant le premier essai réel.
 *
 * Avant (MECEF-1) ces champs étaient une carte au milieu de « Données de l'Entreprise » ; le client voulait « le formulaire qui
 * me permet de renseigner jeton et IFU » : il a maintenant son onglet, ses explications et son bouton « Tester la configuration ».
 * Toutes les écritures passent par `MecefReglageService` (le même point que la demande `entreprise` du poste).
 *
 * ⚠️ Le jeton n'est JAMAIS relu : l'écran montre « •••• » et deux boutons (« Remplacer », « Effacer ») ; la saisie ne vit dans
 * l'état Livewire que le temps de la frappe et est vidée à l'enregistrement. Il ne se saisit qu'au WEB (jamais au poste).
 */
class FacturationEmecef extends Component
{
    public string $mecefMode = MecefMode::DESACTIVE;

    public string $ifu = '';

    public string $mecefApiUrl = '';

    public string $mecefOperateurId = '';

    public string $mecefOperateurNom = '';

    /** Saisie d'un nouveau jeton (vidée dès l'enregistrement, jamais relue de la base). */
    public string $mecefJeton = '';

    public bool $remplacerJeton = false;

    /** @var array{ok: bool, resume: string, lignes: array<int, array{ok: bool, libelle: string, detail: string}>}|null */
    public ?array $resultatTest = null;

    public function mount(): void
    {
        // CONF-1 : jamais d'ouverture sans le droit (jeton configuré, IFU, adresse : réservés à `manage-parametres`).
        abort_unless(Gate::allows('manage-parametres'), 403);

        $settings = CompanySetting::current();
        $reglage = app(MecefReglage::class);

        // Le mode effectif (le mode `simule` des environnements de développement s'affiche « Désactivé »).
        $this->mecefMode = in_array($reglage->mode(), MecefMode::REGLABLES, true) ? $reglage->mode() : MecefMode::DESACTIVE;
        $this->ifu = (string) $settings->ifu;
        // CONF-1 : l'adresse en service (saisie, sinon `SGMEF_API_URL`, sinon l'environnement d'essai) ; le jeton de `.env` n'est jamais lu ici.
        $this->mecefApiUrl = $reglage->emecef()['url'];
        $this->mecefOperateurId = (string) $settings->mecef_operateur_id;
        $this->mecefOperateurNom = (string) $settings->mecef_operateur_nom;
    }

    /** Un jeton est-il enregistré ? (le seul fait que l'écran connaît du secret) */
    public function getJetonConfigureProperty(): bool
    {
        return app(MecefReglage::class)->jetonConfigure();
    }

    /** CONF-1 — le jeton en service vient de la configuration du serveur (`.env`), pas de l'écran. */
    public function getJetonDeConfigurationProperty(): bool
    {
        return app(MecefReglage::class)->jetonDepuisConfiguration();
    }

    /** CONF-1 — valeurs de repli (`SGMEF_DEFAULT_OPERATOR_*`) montrées en indice des champs opérateur. */
    public function getRepliOperateurProperty(): array
    {
        $e = app(MecefReglage::class)->emecef();

        return ['id' => $e['operateur_id'], 'nom' => $e['operateur_nom']];
    }

    /** Préréglage de l'adresse de l'API (production / essai). */
    public function choisirUrl(string $cle): void
    {
        if (isset(MecefMode::PREREGLAGES_URL[$cle])) {
            $this->mecefApiUrl = MecefMode::PREREGLAGES_URL[$cle][1];
            $this->resultatTest = null;
        }
    }

    public function save(): void
    {
        $this->authorize('manage-parametres');

        $service = app(MecefReglageService::class);
        $this->validate($service->regles(), MecefReglageService::MESSAGES);

        try {
            $service->enregistrer([
                'mecefMode' => $this->mecefMode, 'mecefApiUrl' => $this->mecefApiUrl, 'mecefOperateurId' => $this->mecefOperateurId,
                'mecefOperateurNom' => $this->mecefOperateurNom, 'mecefJeton' => $this->mecefJeton, 'ifu' => $this->ifu,
            ], auth()->user());
        } catch (ValidationException $e) {
            foreach ($e->errors() as $champ => $messages) {
                $this->addError($champ, $messages[0]);
            }

            return;
        }

        $this->reset(['mecefJeton', 'remplacerJeton', 'resultatTest']);
        $this->dispatch('toast', message: 'Réglage de la facturation normalisée enregistré.', type: 'success');
    }

    public function effacerJeton(): void
    {
        $this->authorize('manage-parametres');

        app(MecefReglageService::class)->effacerJeton();

        $this->reset(['mecefJeton', 'remplacerJeton', 'resultatTest']);
        $this->dispatch('toast', message: 'Jeton effacé : rien ne part plus à la DGI tant qu\'un nouveau jeton n\'est pas saisi.', type: 'success');
    }

    /** Vérifie la configuration SAISIE (sans l'enregistrer) : contrôles locaux puis UN appel de lecture, jamais une facture. */
    public function tester(): void
    {
        $this->authorize('manage-parametres');

        $this->resultatTest = app(MecefConfigurationTesteur::class)->tester([
            'mode' => $this->mecefMode, 'ifu' => $this->ifu, 'url' => $this->mecefApiUrl, 'jeton' => $this->mecefJeton,
        ]);
    }

    public function render()
    {
        return view('livewire.parametres.facturation-emecef');
    }
}
