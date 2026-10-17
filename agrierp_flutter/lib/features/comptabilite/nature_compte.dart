/// Sens naturel d'un compte (`true` = débiteur), pour le signe du solde progressif du Grand Livre.
///
/// ⚠️⚠️ **COPIE FIDÈLE, SANS RÉINTERPRÉTATION, de
/// `FinancialReportService::natureDebitrice`** (`C:\laragon\www\agrierp\app\Services\`). Le serveur
/// fait foi : cette règle n'est ni dans le prototype (qui ne cite que huit comptes en dur) ni dans
/// un document, elle a été posée côté Laravel (tickets 14.1 puis 15.21) et le cabinet FAGUEZ doit
/// encore la valider compte par compte.
///
/// Elle est PAR CLASSE, et donc discutable pour plusieurs comptes du plan importé (109, 129, 1291,
/// 47x, 48x, 56x, 82/84/86/88…). Le poste ne la CORRIGE PAS : la corriger ici serait trancher une
/// règle comptable à la place du cabinet. `test/grand_livre_poste_test.dart` (« à décider par le
/// cabinet ») rend ce comportement visible, et le test de PARITÉ exécute la vraie règle PHP sur les
/// 1 332 comptes du plan : si le serveur change, le poste doit suivre.
///
/// Ce qui est lu : le CODE du compte et sa CLASSE (colonne `class`, pas le premier chiffre du code —
/// les deux peuvent différer). Classe absente (`null`) = 0, comme le `(int)` de PHP : cas par défaut.
///
/// Pourquoi une copie plutôt que la nature servie par le serveur : voir le ticket F0.85.
bool natureDebitrice(String code, int? classe) {
  bool commencePar(List<String> prefixes) =>
      prefixes.any((p) => code.startsWith(p));

  switch (classe ?? 0) {
    case 1:
      return commencePar(['139']);
    case 2:
      return !commencePar(['28', '29']);
    case 3:
      return !commencePar(['39']);
    case 4:
      return commencePar(['409']) ||
          (commencePar(['445']) && !commencePar(['4457'])) ||
          (commencePar(['41']) && !commencePar(['419']));
    case 5:
      return !commencePar(['59']);
    case 7:
      return false;
    default:
      return true;
  }
}
