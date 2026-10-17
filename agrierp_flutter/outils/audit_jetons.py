# -*- coding: utf-8 -*-
"""Phase 1D (partie mesurable) de AUDIT_FIDELISATION.md — jetons et valeurs en dur.

    py outils/audit_jetons.py      # ecrit RAPPORT_JETONS.md

Deux questions, toutes deux repondues par comparaison de sources, sans rendu :

  1. LES JETONS SONT-ILS CEUX DU PROTOTYPE ? `agri_tokens.dart` est annonce
     « transpose un pour un » de `tailwind-config.js` : couleurs, espacements,
     rayons. Verifie valeur par valeur.
  2. LE CODE S'EN TIENT-IL AUX JETONS ? Compte, par fichier, les couleurs et les
     tailles de police ECRITES EN DUR, et releve celles qui n'existent PAS dans le
     prototype — c'est le defaut que `conformite_portage_test.dart` ne verrouille
     que pour trois valeurs (12, 12.5, 13).

⚠️ Ce rapport ne dit RIEN de l'alignement ni du rendu : une taille de police
juste dans un conteneur trop etroit deborde quand meme. Voir RAPPORT_EMPLACEMENT.md
pour les debordements releves, et la phase 1D (captures) pour le reste.
"""
import collections
import glob
import io
import os
import re

RACINE = 'C:/Projects/agrierp_flutter'
PROTO = 'C:/Projects/agrierp_laravel/prototype_html'

# Echelle typographique de Tailwind, avec la surcharge de `common.css`.
TAILWIND_TAILLES = {'text-xs': 13.6, 'text-sm': 14, 'text-base': 16,
                    'text-lg': 18, 'text-xl': 20, 'text-2xl': 24,
                    'text-3xl': 30, 'text-4xl': 36}


def lire(p):
    return io.open(p, encoding='utf-8', errors='ignore').read()


def camel(nom):
    parts = nom.split('-')
    return parts[0] + ''.join(x.capitalize() for x in parts[1:])


def sans_commentaires(src):
    return re.sub(r'//[^\n]*', '', src)


def main():
    cfg = lire(PROTO + '/assets/js/tailwind-config.js')
    tok = sans_commentaires(lire(RACINE + '/lib/core/theme/agri_tokens.dart'))
    L = []
    w = L.append
    w('# RAPPORT JETONS — design tokens et valeurs en dur (phase 1D, partie '
      'mesurable)')
    w('')
    w('Généré par `outils/audit_jetons.py` (ticket AF1.3). **Aucun rendu** : '
      'comparaison de sources. Ne dit rien de l\'alignement.')
    w('')
    ecarts = []

    # ---- 1. couleurs
    proto_c = dict(re.findall(r"'([a-z-]+)':\s*'(#[0-9a-fA-F]{6})'", cfg))
    dart_c = {n: h.upper() for n, h in re.findall(
        r'static const (\w+) = Color\(0xFF([0-9A-Fa-f]{6})\)', tok)}
    w('## 1. Couleurs (`tailwind-config.js` ↔ `AgriColors`)')
    w('')
    w('| Jeton | Prototype | Poste | Verdict |')
    w('|---|---|---|---|')
    ok = 0
    for nom, hexa in proto_c.items():
        d = dart_c.get(camel(nom))
        v = '✔' if d and d == hexa.lstrip('#').upper() else '✘'
        ok += v == '✔'
        if v == '✘':
            ecarts.append(('bloquant', 'jeton couleur %s' % nom,
                           'prototype %s, poste %s' % (hexa, d)))
        w('| %s | %s | %s | %s |' % (nom, hexa.upper(), '#' + d if d else '—', v))
    w('')
    en_plus = [n for n in dart_c if n not in {camel(k) for k in proto_c}]
    w('**%d / %d couleurs identiques.** Couleurs du poste absentes du prototype : '
      '%s.' % (ok, len(proto_c), ', '.join(en_plus) or 'aucune'))
    w('')

    # ---- 2. espacements et rayons
    sp_p = dict(re.findall(r"(\w+):\s*'(\d+)px'", re.search(
        r'spacing:\s*\{(.*?)\}', cfg, re.S).group(1)))
    sp_p.update({k.strip("'"): v for k, v in re.findall(
        r"'(2xl)':\s*'(\d+)px'", cfg)})
    sp_d = dict(re.findall(r'static const double (\w+) = (\d+);', re.search(
        r'class AgriSpacing \{(.*?)\n\}', tok, re.S).group(1)))
    w('## 2. Espacements (`spacing`) et rayons (`borderRadius`)')
    w('')
    w('| Jeton | Prototype (px) | Poste | Verdict |')
    w('|---|---|---|---|')
    for k, v in sp_p.items():
        d = sp_d.get('xxl' if k == '2xl' else k)
        ver = '✔' if d == v else '✘'
        if ver == '✘':
            ecarts.append(('bloquant', 'jeton espacement %s' % k,
                           'prototype %s, poste %s' % (v, d)))
        w('| spacing.%s | %s | %s | %s |' % (k, v, d or '—', ver))
    rd_p = {'lg': 8, 'xl': 12}  # 0.5rem, 0.75rem
    rd_d = dict(re.findall(r'static const double (\w+) = (\d+);', re.search(
        r'class AgriRadius \{(.*?)\n\}', tok, re.S).group(1)))
    for k, v in rd_p.items():
        d = rd_d.get(k)
        ver = '✔' if d == str(v) else '✘'
        w('| borderRadius.%s | %d (%srem) | %s | %s |' % (
            k, v, '0.5' if v == 8 else '0.75', d or '—', ver))
    w('')

    # ---- 3. tailles de police du prototype
    tailles_proto = set(TAILWIND_TAILLES.values())
    n_cl = collections.Counter()
    for f in glob.glob(PROTO + '/*.html') + glob.glob(PROTO + '/assets/js/*.js'):
        src = lire(f)
        for m in re.finditer(r'text-\[(\d+(?:\.\d+)?)px\]', src):
            tailles_proto.add(float(m.group(1)))
            n_cl[float(m.group(1))] += 1
    w('## 3. Tailles de police : celles du prototype')
    w('')
    w('Tailles distinctes utilisées par le prototype (échelle Tailwind avec la '
      'surcharge `text-xs` = 13,6 px, plus les `text-[Npx]` arbitraires) : '
      '**%s**.' % ', '.join('%g' % t for t in sorted(tailles_proto)))
    w('')

    # ---- 4. valeurs en dur dans le code Dart
    fichiers = [f.replace(os.sep, '/') for f in
                glob.glob(RACINE + '/lib/**/*.dart', recursive=True)
                if not f.replace(os.sep, '/').endswith('agri_tokens.dart')
                and '.g.dart' not in f]
    tailles = collections.defaultdict(collections.Counter)
    couleurs = collections.defaultdict(collections.Counter)
    for f in fichiers:
        src = sans_commentaires(lire(f))
        rel = f.replace(RACINE + '/', '')
        for m in re.finditer(r'fontSize:\s*(\d+(?:\.\d+)?)\b', src):
            tailles[rel][float(m.group(1))] += 1
        for m in re.finditer(r'Color\(0x[0-9A-Fa-f]{8}\)', src):
            couleurs[rel][m.group(0)] += 1

    hors = collections.Counter()
    ou = collections.defaultdict(list)
    for rel, c in tailles.items():
        for t, n in c.items():
            if t not in tailles_proto:
                hors[t] += n
                ou[t].append('%s (%d)' % (os.path.basename(rel), n))
    w('## 4. Tailles de police écrites en dur qui n\'existent PAS dans le prototype')
    w('')
    if hors:
        w('`conformite_portage_test.dart` n\'en verrouille que trois (12, 12.5, '
          '13). Les autres passent sans bruit.')
        w('')
        w('| Taille | Occurrences | Fichiers |')
        w('|---|---|---|')
        for t, n in sorted(hors.items()):
            w('| %g | %d | %s |' % (t, n, ', '.join(ou[t][:6]) +
                                      (' …' if len(ou[t]) > 6 else '')))
            ecarts.append(('mineur', 'taille %g' % t,
                           '%d occurrence(s), absente du prototype' % n))
    else:
        w('Aucune.')
    w('')
    total = sum(sum(c.values()) for c in tailles.values())
    w('Au total %d tailles écrites en dur, dont %d hors prototype.' % (
        total, sum(hors.values())))
    w('')

    w('## 5. Couleurs écrites en dur hors `agri_tokens.dart`')
    w('')
    toutes = collections.Counter()
    for c in couleurs.values():
        toutes.update(c)
    # Valeurs qui sont des classes Tailwind PAR DEFAUT, employees par le prototype
    # sans passer par `tailwind-config.js`. Une couleur du poste n'est une derive
    # que si le prototype ne l'emploie pas non plus.
    tw = {'0xFFF59E0B': r'amber-500', '0xFFB45309': r'amber-700',
          '0xFF78350F': r'amber-900', '0x80000000': r'bg-black/50',
          '0x99000000': r'bg-black/60'}
    corpus = ' '.join(lire(f) for f in glob.glob(PROTO + '/*.html'))
    if toutes:
        w('| Valeur | Occurrences | Fichiers | Classe Tailwind du prototype |')
        w('|---|---|---|---|')
        for val, n in toutes.most_common():
            fs = [os.path.basename(r) for r, c in couleurs.items() if val in c]
            cle = re.search(r'0x[0-9A-Fa-f]{8}', val).group(0)
            cle = '0x' + cle[2:].upper()
            classe = tw.get(cle)
            nb = len(re.findall(re.escape(classe), corpus)) if classe else 0
            verdict = ('`%s` (%d emplois dans le prototype) ✔' % (classe, nb)
                       if classe and nb else 'AUCUNE — valeur inventée ?')
            if not (classe and nb):
                ecarts.append(('mineur', 'couleur %s' % val,
                               'absente du prototype'))
            w('| `%s` | %d | %s | %s |' % (
                val, n, ', '.join(fs[:5]) + (' …' if len(fs) > 5 else ''),
                verdict))
    else:
        w('Aucune.')
    w('')

    # ---- 6. police
    pubspec = lire(RACINE + '/pubspec.yaml')
    pubspec_sans = '\n'.join(l for l in pubspec.split('\n')
                             if not l.strip().startswith('#'))
    police_proto = re.search(r'family=([A-Za-z]+)', lire(
        PROTO + '/dashboard.html'))
    poids = re.search(r'wght@([0-9;]+)', lire(PROTO + '/dashboard.html'))
    emplois = 0
    for f in glob.glob(RACINE + '/lib/**/*.dart', recursive=True):
        if f.replace(os.sep, '/').endswith('agri_tokens.dart'):
            continue
        emplois += len(re.findall(r'AgriTypography\.famille|fontFamily:\s*'
                                  r"'Inter'", sans_commentaires(lire(f))))
    embarquee = bool(re.search(r'^\s*fonts:', pubspec_sans, re.M))
    w('## 6. Police de caractères')
    w('')
    w('| | Valeur |')
    w('|---|---|')
    w('| police du prototype | **%s**, graisses %s (Google Fonts) |' % (
        police_proto.group(1) if police_proto else '?',
        (poids.group(1).replace(';', ', ') if poids else '?')))
    w('| jeton du poste | `AgriTypography.famille` = \'Inter\' |')
    w('| emplois du jeton dans `lib/` | **%d** |' % emplois)
    w('| section `fonts:` dans `pubspec.yaml` | **%s** |' %
      ('oui' if embarquee else 'non'))
    w('| Inter installée dans `C:\\Windows\\Fonts` | %s |' % (
        'oui' if os.path.exists('C:/Windows/Fonts/Inter-Regular.ttf') or
        os.path.exists('C:/Windows/Fonts/Inter.ttf') else 'non (Segoe UI seule)'))
    w('')
    if not embarquee and emplois == 0:
        w('⚠️ **Le jeton est déclaré mais jamais appliqué, et la police n\'est '
          'pas embarquée** : le poste s\'affiche dans la police système de '
          'Windows, pas en Inter. Aucun test ni analyseur ne peut le voir — '
          'c\'est un défaut de rendu pur, présent sur **tous** les écrans. Il '
          'change aussi la largeur du texte, donc les débordements et les '
          'retours à la ligne.')
        w('')
        ecarts.append(('majeur', 'police',
                       'Inter déclarée (AgriTypography.famille) mais ni '
                       'embarquée ni appliquée : tous les écrans en police '
                       'système'))

    ordre = {'bloquant': 0, 'majeur': 1, 'mineur': 2}
    n = {k: sum(1 for e in ecarts if e[0] == k) for k in ordre}
    w('## Synthèse')
    w('')
    w('**%d bloquant · %d majeur · %d mineur.**' % (n['bloquant'], n['majeur'],
                                                  n['mineur']))
    w('')
    return '\n'.join(L), n


if __name__ == '__main__':
    texte, n = main()
    io.open(os.path.join(RACINE, 'RAPPORT_JETONS.md'), 'w',
            encoding='utf-8').write(texte)
    print(n)
