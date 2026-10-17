# -*- coding: utf-8 -*-
"""Ticket F0.57 — transpose les libelles du journal d'audit depuis Laravel.

    py outils/libelles_audit.py

Lit `ACTION_LABELS` et `MODULE_LABELS` de `app/Models/AuditLog.php` et ecrit
`lib/core/audit/libelles_audit.dart`.

⚠️ GENERE, JAMAIS RETOUCHE A LA MAIN. Le serveur ne sert au poste que la cle
technique (`login`, `sale.created`) ; le libelle francais vit uniquement dans ce
modele PHP. Le recopier a la main ferait deriver les deux tables au premier
ajout d'une action cote serveur. Relancer ce script apres chaque ticket Laravel
qui ajoute une cle.
"""
import re
import sys

PHP = 'C:/laragon/www/agrierp/app/Models/AuditLog.php'
DART = 'C:/Projects/agrierp_flutter/lib/core/audit/libelles_audit.dart'

# 'cle' => 'libelle'  ou  'cle' => "libelle"
PAIRE = re.compile(
    r"""^\s*'(?P<cle>[^']+)'\s*=>\s*(?:'(?P<a>(?:[^'\\]|\\.)*)'|"(?P<b>(?:[^"\\]|\\.)*)")\s*,""",
    re.M)


def bloc(source, nom):
    m = re.search(r'const\s+%s\s*=\s*\[(.*?)\n\s*\];' % nom, source, re.S)
    if not m:
        sys.exit('constante %s introuvable dans %s' % (nom, PHP))
    paires = []
    for p in PAIRE.finditer(m.group(1)):
        texte = p.group('a') if p.group('a') is not None else p.group('b')
        texte = texte.replace("\\'", "'").replace('\\"', '"')
        paires.append((p.group('cle'), texte))
    return paires


def litteral(texte):
    """Litteral Dart entre apostrophes, `$` et `'` echappes."""
    e = texte.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$')
    return "'%s'" % e


def table(nom, paires):
    lignes = ['  static const Map<String, String> %s = {' % nom]
    for cle, texte in paires:
        lignes.append('    %s: %s,' % (litteral(cle), litteral(texte)))
    lignes.append('  };')
    return '\n'.join(lignes)


if __name__ == '__main__':
    source = open(PHP, encoding='utf-8').read()
    actions = bloc(source, 'ACTION_LABELS')
    modules = bloc(source, 'MODULE_LABELS')
    sortie = '''// GENERE par outils/libelles_audit.py — NE PAS RETOUCHER A LA MAIN.
// Source : app/Models/AuditLog.php (Laravel), %d actions et %d modules.

/// Libellés français du journal d'audit.
///
/// ⚠️ Le serveur ne descend au poste que la CLÉ technique (`login`,
/// `sale.created`) ; le libellé n'existe que dans le modèle `AuditLog`. Cette
/// classe en est la transposition, générée — pas écrite.
///
/// ⚠️ Une clé inconnue s'affiche brute, comme côté serveur : mieux vaut la clé
/// technique qu'un libellé inventé.
class LibellesAudit {
  const LibellesAudit._();

  static String action(String cle) => actions[cle] ?? cle;

  static String? module(String? cle) =>
      cle == null ? null : (modules[cle] ?? cle);

%s

%s
}
''' % (len(actions), len(modules), table('actions', actions),
       table('modules', modules))
    import os
    os.makedirs(os.path.dirname(DART), exist_ok=True)
    open(DART, 'w', encoding='utf-8', newline='\n').write(sortie)
    print('%d actions, %d modules -> %s' % (len(actions), len(modules), DART))
