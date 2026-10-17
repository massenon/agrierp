<?php

namespace Database\Seeders\Demo;

use App\Actions\RecordPayrollAccountingEntryAction;
use App\Models\AttendanceRecord;
use App\Models\Employee;
use App\Models\Internship;
use App\Models\Payslip;
use Carbon\CarbonImmutable;
use Illuminate\Database\Seeder;

/**
 * Ticket 14.31 (Sprint 14) — RESSOURCES HUMAINES de démonstration.
 *
 * ⚠️ LA PAIE PASSE PAR `RecordPayrollAccountingEntryAction` : la charge portée
 * au débit de 661 est le salaire RÉELLEMENT DÛ (net + CNSS), pas le net versé
 * — c'est la règle posée au ticket 14.25, et la recopier ici à la main aurait
 * sous-estimé les charges de personnel de 3,6 % chaque mois dans la
 * démonstration, précisément le défaut que ce ticket avait corrigé.
 *
 * ⚠️ POINTAGE COHÉRENT AVEC LES BULLETINS : les absences enregistrées sur le
 * pointage sont celles qui réduisent le salaire dû. Deux jeux de données
 * indépendants auraient donné un écran de pointage et un bulletin qui se
 * contredisent — le genre d'incohérence qu'un client repère immédiatement en
 * démonstration.
 */
class DemoRhSeeder extends Seeder
{
    public function __construct(private DemoContexte $ctx) {}

    public function run(): void
    {
        $employes = $this->creerEmployes();
        $absences = $this->creerPointage($employes);
        $bulletins = $this->creerBulletins($employes, $absences);
        $this->creerStagiaires();

        $this->command?->info('  RH : '.count($employes).' employés, '.AttendanceRecord::count()
            .' pointages, '.$bulletins.' bulletins de paie, '.Internship::count().' stagiaires.');
    }

    /** @return array<int, Employee> */
    private function creerEmployes(): array
    {
        $definitions = [
            ['Kossi', 'ADJOVI', 'Chef d\'exploitation', 145_000, 26],
            ['Bernadette', 'HOUNSOU', 'Animalière — Aviculture', 85_000, 20],
            ['Rachidou', 'BIO SANNI', 'Animalier — Porciculture', 85_000, 14],
            ['Estelle', 'DOSSOU', 'Caissière / Ventes', 95_000, 30],
            ['Marcel', 'AGBOTON', 'Ouvrier polyvalent', 65_000, 9],
            ['Christine', 'KOUTON', 'Comptable', 130_000, 22],
        ];

        $employes = [];

        foreach ($definitions as [$prenom, $nom, $poste, $salaire, $anciennete]) {
            $employes[] = Employee::firstOrCreate(
                ['first_name' => $prenom, 'last_name' => $nom],
                [
                    'position' => $poste,
                    'base_salary' => $salaire,
                    'hire_date' => $this->ctx->debut->subMonths($anciennete)->format('Y-m-d'),
                    'status' => 'actif',
                    'is_active' => true,
                ]
            );
        }

        return $employes;
    }

    /**
     * Pointage quotidien, hors dimanche.
     *
     * @param  array<int, Employee>  $employes
     * @return array<string, array<string, int>>  absences par employé et par mois
     */
    private function creerPointage(array $employes): array
    {
        $absences = [];

        foreach ($this->ctx->jours() as $jour) {
            if ($jour->dayOfWeek === CarbonImmutable::SUNDAY) {
                continue;
            }

            foreach ($employes as $employe) {
                $statut = match (true) {
                    $this->ctx->chance(3) => 'absent',
                    $this->ctx->chance(4) => 'retard',
                    $this->ctx->chance(2) => 'conge',
                    default => 'present',
                };

                AttendanceRecord::create([
                    'employee_id' => $employe->id,
                    'attendance_date' => $jour->format('Y-m-d'),
                    'check_in' => $statut === 'absent' ? null : sprintf('%02d:%02d:00', $statut === 'retard' ? 8 : 7, $this->ctx->entre(0, 55)),
                    'check_out' => $statut === 'absent' ? null : sprintf('%02d:%02d:00', 17, $this->ctx->entre(0, 45)),
                    'status' => $statut,
                    'is_active' => true,
                    'created_at' => $jour, 'updated_at' => $jour,
                ]);

                // Seule l'absence non justifiée réduit le salaire dû : un
                // congé et un retard n'entrent pas dans la retenue.
                if ($statut === 'absent') {
                    $cle = $jour->format('Y-m');
                    $absences[$employe->id][$cle] = ($absences[$employe->id][$cle] ?? 0) + 1;
                }
            }
        }

        return $absences;
    }

    /**
     * Bulletins mensuels — uniquement pour les mois RÉVOLUS.
     *
     * ⚠️ Le mois en cours n'est pas payé : une paie versée d'avance
     * fausserait à la fois la trésorerie et les charges de la période, et
     * afficherait un mois clos qui ne l'est pas.
     *
     * @param  array<int, Employee>  $employes
     * @param  array<string, array<string, int>>  $absences
     */
    private function creerBulletins(array $employes, array $absences): int
    {
        $compte = 0;
        $joursOuvres = 26;

        for ($mois = $this->ctx->debut->startOfMonth(); $mois->lt($this->ctx->fin->startOfMonth()); $mois = $mois->addMonth()) {
            foreach ($employes as $employe) {
                $brut = (float) $employe->base_salary;
                $joursAbsents = $absences[$employe->id][$mois->format('Y-m')] ?? 0;

                // ⚠️ MÊME SERVICE QUE L'ÉCRAN (ticket 14.38). Recopier ici la
                // formule — comme le faisait ce seeder avec un taux CNSS en
                // dur — produisait une démonstration sans ITS ni charges
                // patronales, donc un net et un coût du travail faux.
                $calcul = app(\App\Services\PayrollCalculationService::class)
                    ->calculer($brut, $joursAbsents, $joursOuvres);

                $net = $calcul['net'];

                $bulletin = Payslip::create([
                    'employee_id' => $employe->id,
                    'period_month' => $mois->format('Y-m-01'),
                    'gross_salary' => $brut,
                    'absence_deduction' => $calcul['retenue_absence'],
                    'cnss_deduction' => $calcul['cnss_salariale'],
                    'its_deduction' => $calcul['its'],
                    'vps_employer' => $calcul['vps'],
                    'cnss_employer_pension' => $calcul['cnss_patronale_pension'],
                    'cnss_employer_family' => $calcul['cnss_patronale_famille'],
                    'cnss_employer_risk' => $calcul['cnss_patronale_risque'],
                    'net_salary' => $net,
                    'created_at' => $mois->endOfMonth(), 'updated_at' => $mois->endOfMonth(),
                ]);

                // ⚠️ DÉCRÉMENT DE TRÉSORERIE, exactement comme `GestionPaie` :
                // premier compte actif, et le NET est ce qui sort réellement.
                // L'omettre laissait la simulation payer 2,8 M FCFA de salaires
                // sans que la trésorerie ne bouge — la démonstration aurait
                // montré une caisse plus riche que la réalité qu'elle simule.
                // ⚠️ COMPTE PAYEUR EXPLICITE, contrairement à l'application.
                //
                // 🔴 GAP RÉEL SIGNALÉ : `GestionPaie` débite
                // `TreasuryAccount::where('is_active', true)->first()` — un
                // compte ARBITRAIRE, sans `orderBy` ni choix de l'utilisateur.
                // L'écran ne demande jamais par quel compte les salaires sont
                // versés (limite déjà signalée au ticket 14.25). Sur MySQL,
                // « first » n'est pas un ordre garanti : la simulation faisait
                // atterrir 2,9 M FCFA de salaires sur un compte différent d'une
                // exécution à l'autre, et les soldes variaient de ±2,8 M à
                // données métier pourtant identiques.
                $compteTresorerie = $this->ctx->compteSolvable($net);
                $compteTresorerie?->decrement('balance', $net);

                app(RecordPayrollAccountingEntryAction::class)->execute($bulletin, $compteTresorerie?->id);

                $compte++;
            }
        }

        return $compte;
    }

    /** Stagiaires — la ferme est une ferme ÉCOLE, l'écran doit le refléter. */
    private function creerStagiaires(): void
    {
        foreach ([
            ['Ange', 'TOSSOU', 'Lycée Agricole de Sékou', 4, 2, 25_000, true],
            ['Nadège', 'AKPOVI', 'Université d\'Abomey-Calavi — FSA', 3, 0, 30_000, true],
            ['Ibrahim', 'MAMA', 'CFP Pobè', 2, 0, 20_000, false],
            ['Sylvie', 'ZINSOU', 'Lycée Agricole de Sékou', 1, 0, 25_000, false],
        ] as [$prenom, $nom, $ecole, $debutMois, $dureeFinie, $indemnite, $paye]) {
            $debut = $this->ctx->fin->subMonths($debutMois)->startOfMonth();

            Internship::create([
                'first_name' => $prenom,
                'last_name' => $nom,
                'school' => $ecole,
                'start_date' => $debut->format('Y-m-d'),
                'end_date' => $dureeFinie > 0 ? $debut->addMonths($dureeFinie)->format('Y-m-d') : null,
                'monthly_fee' => $indemnite,
                'fee_paid' => $paye,
                'created_at' => $debut, 'updated_at' => $debut,
            ]);
        }
    }
}
