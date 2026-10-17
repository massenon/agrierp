<?php

namespace App\Livewire\Parametres;

use App\Actions\RecordTreasuryTransferAction;
use App\Models\AuditLog;
use App\Models\TreasuryAccount;
use Livewire\Component;

/**
 * Suite du Sprint 11 — modes-paiement.html → Livewire\Parametres\ModesPaiement
 * "Comptes de trésorerie (Classe 5 SYSCOHADA) : caisse, banques et
 * mobile money."
 *
 * `treasury_accounts` existait déjà en intégralité depuis le ticket 2.6
 * (déjà décrémentée/incrémentée réellement par Achats, Dépenses, Paie,
 * Règlements Fournisseurs...) — cet écran est le PREMIER à exposer
 * réellement son CRUD (ajout de comptes bancaires/lignes mobile money),
 * jamais une seconde table ni une copie des soldes déjà réels partout
 * ailleurs dans ce projet.
 *
 * Extension schéma : `iban`, `holder_name`, `sim_serial` (voir
 * migration) — champs réels des deux formulaires du prototype, absents
 * du schéma minimal documenté.
 *
 * "Caisse Physique" (531) reste en lecture seule ici — le prototype ne
 * propose aucun bouton "Ajouter une Caisse" (une seule caisse
 * principale, déjà seedée) ; seuls comptes bancaires et lignes mobile
 * money sont ajoutables.
 *
 * 🔴→✅ TICKET 14.35 — VIREMENT INTERNE, fonction ajoutée ici.
 *
 * ⚠️ ABSENTE DU PROTOTYPE ET DU CDC : ni `modes-paiement.html` ni le cahier
 * des charges ne prévoient de déplacer de l'argent entre comptes. Ce n'est
 * donc pas une conversion d'écran mais un AJOUT, signalé comme tel et à faire
 * valider par le Cabinet FAGUEZ.
 *
 * Le manque est pourtant structurel, démontré par la simulation (14.31) :
 * cette exploitation encaisse en espèces et par Mobile Money mais règle ses
 * gros postes par la banque. Sans dépôt possible, un compte se vide
 * mécaniquement pendant qu'un autre déborde — constaté dans les trois sens
 * (−3,3 M en banque, −262 000 en caisse, −1,6 M en Mobile Money selon le
 * compte payeur retenu). Aucune règle d'allocation ne corrige cela.
 *
 * Cet écran est le seul qui présente les trois familles de comptes et leurs
 * soldes : c'est là que le virement a sa place, pas dans un écran comptable.
 */
class ModesPaiement extends Component
{
    public string $type = '';

    public string $bankName = '';

    public string $holderName = '';

    public string $rib = '';

    public string $iban = '';

    public string $accountCode = '';

    public string $operatorName = '';

    public string $phoneNumber = '';

    public string $simSerial = '';

    // --- Virement interne (ticket 14.35) --------------------------------
    public string $transferFromId = '';

    public string $transferToId = '';

    public $transferAmount = null;

    public string $transferReason = '';

    public function getKpisProperty(): array
    {
        return [
            'caisse' => TreasuryAccount::where('type', 'caisse')->where('is_active', true)->sum('balance'),
            'banques' => TreasuryAccount::where('type', 'banque')->where('is_active', true)->sum('balance'),
            'mobile_money' => TreasuryAccount::where('type', 'mobile_money')->where('is_active', true)->sum('balance'),
        ];
    }

    public function getCaisseAccountsProperty()
    {
        return TreasuryAccount::where('type', 'caisse')->where('is_active', true)->orderBy('label')->get();
    }

    public function getBankAccountsProperty()
    {
        return TreasuryAccount::where('type', 'banque')->where('is_active', true)->orderBy('label')->get();
    }

    public function getMomoAccountsProperty()
    {
        return TreasuryAccount::where('type', 'mobile_money')->where('is_active', true)->orderBy('label')->get();
    }

    public function openAddBank(): void
    {
        $this->reset(['bankName', 'holderName', 'rib', 'iban', 'accountCode']);
        $this->holderName = 'Ferme École OLOUWACHEGOUN';
        $this->type = 'banque';
        $this->dispatch('open-modal', name: 'modal-add-bank');
    }

    public function saveBank(): void
    {
        $this->validate([
            'bankName' => ['required', 'string'],
            'rib' => ['required', 'string', 'max:100'],
            'iban' => ['required', 'string', 'max:40'],
        ]);

        TreasuryAccount::create([
            'type' => 'banque',
            'label' => $this->bankName.($this->accountCode ? ' - '.$this->accountCode : ''),
            'account_code' => $this->accountCode ?: '521',
            'bank_name' => $this->bankName,
            'holder_name' => $this->holderName ?: null,
            'rib' => $this->rib,
            'iban' => $this->iban,
            'balance' => 0,
            'is_active' => true,
        ]);

        AuditLog::record('treasury_account.bank_created', 'parametres');
        $this->dispatch('close-modal', name: 'modal-add-bank');
        $this->dispatch('toast', message: 'Compte bancaire ajouté avec succès.', type: 'success');
    }

    public function openAddMomo(): void
    {
        $this->reset(['operatorName', 'phoneNumber', 'holderName', 'simSerial', 'accountCode']);
        $this->dispatch('open-modal', name: 'modal-add-momo');
    }

    public function saveMomo(): void
    {
        $this->validate([
            'operatorName' => ['required', 'string'],
            'phoneNumber' => ['required', 'string', 'max:30'],
        ]);

        TreasuryAccount::create([
            'type' => 'mobile_money',
            'label' => $this->operatorName.($this->accountCode ? ' - '.$this->accountCode : ''),
            'account_code' => $this->accountCode ?: '5212',
            'operator_name' => $this->operatorName,
            'holder_name' => $this->holderName ?: null,
            'phone_number' => $this->phoneNumber,
            'sim_serial' => $this->simSerial ?: null,
            'balance' => 0,
            'is_active' => true,
        ]);

        AuditLog::record('treasury_account.momo_created', 'parametres');
        $this->dispatch('close-modal', name: 'modal-add-momo');
        $this->dispatch('toast', message: 'Ligne Mobile Money ajoutée avec succès.', type: 'success');
    }

    /** Tous les comptes mouvementables, pour les deux listes du virement. */
    public function getTransferableAccountsProperty()
    {
        return TreasuryAccount::where('is_active', true)->orderBy('label')->get();
    }

    public function openTransfer(): void
    {
        $this->authorize('manage-comptabilite');

        $this->reset(['transferFromId', 'transferToId', 'transferAmount', 'transferReason']);
        $this->resetValidation();
        $this->dispatch('open-modal', name: 'modal-virement-interne');
    }

    public function submitTransfer(): void
    {
        // ⚠️ `manage-comptabilite` ET NON UNE PERMISSION DE PARAMÉTRAGE : un
        // virement déplace de l'argent, c'est un acte comptable avant d'être un
        // réglage. Et surtout, `manage-parametres` N'EXISTE PAS dans la matrice
        // de permissions — seul `view-parametres` y figure. Inventer une
        // permission reviendrait à modifier la matrice RBAC, que le projet
        // interdit d'harmoniser sans accord du client.
        //
        // 🔴 GAP RÉEL SIGNALÉ : `saveBank()` et `saveMomo()`, sur ce même
        // écran, n'appellent AUCUN `authorize()`. Créer un compte bancaire ou
        // une ligne Mobile Money est donc ouvert à tout profil disposant de
        // `view-parametres`. Non corrigé ici faute de permission adéquate —
        // même classe de défaut que celui trouvé sur les Retours et Avoirs
        // (ticket 14.27).
        //
        // Autorisation posée sur l'action qui ÉCRIT : les propriétés publiques
        // sont modifiables côté client (leçon des tickets 12.4 et 14.27).
        $this->authorize('manage-comptabilite');

        $this->validate([
            'transferFromId' => ['required', 'exists:treasury_accounts,id'],
            'transferToId' => ['required', 'exists:treasury_accounts,id', 'different:transferFromId'],
            'transferAmount' => ['required', 'numeric', 'min:1'],
            'transferReason' => ['nullable', 'string', 'max:150'],
        ], [
            'transferToId.different' => 'Le compte destinataire doit être différent du compte source.',
        ], [
            'transferFromId' => 'compte source', 'transferToId' => 'compte destinataire',
            'transferAmount' => 'montant',
        ]);

        $source = TreasuryAccount::findOrFail($this->transferFromId);
        $destination = TreasuryAccount::findOrFail($this->transferToId);

        try {
            $ecriture = app(RecordTreasuryTransferAction::class)->execute(
                $source, $destination, (float) $this->transferAmount, $this->transferReason ?: null
            );
        } catch (\InvalidArgumentException $e) {
            // Solde insuffisant : refus net. Contrairement au stock (14.30),
            // un virement n'entérine aucun fait déjà accompli — rien
            // n'oblige à l'enregistrer, et on ne vire pas un argent qu'on n'a
            // pas.
            $this->addError('transferAmount', $e->getMessage());

            return;
        } catch (\App\Exceptions\ClosedFiscalYearException|\App\Exceptions\NoOpenFiscalYearException $e) {
            $this->addError('transferAmount', $e->getMessage());

            return;
        }

        AuditLog::record('treasury.transfer', 'parametres');
        $this->dispatch('close-modal', name: 'modal-virement-interne');

        $this->dispatch('toast', message: $ecriture
            ? 'Virement enregistré — '.number_format((float) $this->transferAmount, 0, ',', ' ').' FCFA de '.$source->label.' vers '.$destination->label.'.'
            : "Virement effectué SANS écriture comptable (compte absent du plan comptable). À régulariser au Journal Comptable.",
            type: $ecriture ? 'success' : 'warning');

        $this->reset(['transferFromId', 'transferToId', 'transferAmount', 'transferReason']);
    }

    public function render()
    {
        return view('livewire.parametres.modes-paiement');
    }
}
