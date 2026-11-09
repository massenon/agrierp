// Ticket AIDE-1 — logique pure de la visite guidée (placement du trou lumineux et de la carte).
// Fenêtre de 1000 × 800 ; carte de 352 × 240 ; valeurs attendues CALCULÉES À LA MAIN (marge 6, écart 12, bord 16).
import test from 'node:test';
import assert from 'node:assert/strict';
import { indicateur, placerCarte, rectUtilisable, trouAutour } from '../../resources/js/aide-logique.js';

const L = 1000;
const H = 800;
const carte = { width: 352, height: 240 };

test('un élément absent, nul, replié ou hors champ n a rien à mettre en valeur', () => {
    assert.equal(rectUtilisable(null, L, H), false);
    assert.equal(rectUtilisable({ top: 0, left: 0, width: 0, height: 0 }, L, H), false, 'display:none donne un rectangle nul');
    // Tiroir mobile fermé : 288 px de large, décalé de sa largeur vers la gauche -> bord droit à 0.
    assert.equal(rectUtilisable({ top: 0, left: -288, width: 288, height: 800 }, L, H), false);
    assert.equal(rectUtilisable({ top: 0, left: 1000, width: 60, height: 60 }, L, H), false);
    assert.equal(rectUtilisable({ top: 0, left: 0, width: 288, height: 800 }, L, H), true);
});

test('le trou est le rectangle élargi de 6 px, rogné à la fenêtre', () => {
    assert.deepEqual(trouAutour({ top: 10, left: 10, width: 100, height: 50 }, L, H), { top: 4, left: 4, width: 112, height: 62 });
    assert.deepEqual(trouAutour({ top: 0, left: 0, width: 288, height: 800 }, L, H), { top: 0, left: 0, width: 294, height: 800 });
});

test('la carte se pose sous le trou quand il y a la place', () => {
    // 4 + 62 + 12 = 78 ; 78 + 240 + 16 = 334 <= 800 ; gauche bornée à 16.
    assert.deepEqual(placerCarte({ top: 4, left: 4, width: 112, height: 62 }, carte, L, H), { top: 78, left: 16, lieu: 'dessous' });
});

test('le bouton d aide, en bas à droite : la carte passe au-dessus et reste dans la fenêtre', () => {
    // Dessous : 690 + 60 + 12 = 762, + 240 + 16 > 800 ; dessus : 690 - 12 - 240 = 438 ; gauche : 1000 - 352 - 16 = 632.
    assert.deepEqual(placerCarte({ top: 690, left: 930, width: 60, height: 60 }, carte, L, H), { top: 438, left: 632, lieu: 'dessus' });
});

test('le menu (bande pleine hauteur à gauche) : la carte se pose à sa droite', () => {
    // Ni dessous (812) ni dessus (-252) ; droite : 294 + 12 = 306, + 352 + 16 = 674 <= 1000 ; haut borné à 16.
    assert.deepEqual(placerCarte({ top: 0, left: 0, width: 294, height: 800 }, carte, L, H), { top: 16, left: 306, lieu: 'droite' });
});

test('un élément qui remplit l écran : carte centrée en bas', () => {
    // Plus de place ni dessous, ni dessus, ni à droite (1012), ni à gauche (-70) ; haut = 800 - 240 - 16 = 544 ; gauche = 324.
    assert.deepEqual(placerCarte({ top: 64, left: 294, width: 706, height: 736 }, carte, L, H), { top: 544, left: 324, lieu: 'bas' });
});

test('sans trou : carte centrée dans la fenêtre, y compris sur un petit écran', () => {
    assert.deepEqual(placerCarte(null, carte, L, H), { top: 280, left: 324, lieu: 'centre' });
    // 320 × 500 : la carte (352) est plus large que la fenêtre -> collée au bord (16) ; (500 - 240) / 2 = 130.
    assert.deepEqual(placerCarte(null, carte, 320, 500), { top: 130, left: 16, lieu: 'centre' });
});

test('l indicateur remplit le gabarit du fichier de langue', () => {
    assert.equal(indicateur('Étape :numero sur :total', 0, 4), 'Étape 1 sur 4');
    assert.equal(indicateur('Étape :numero sur :total', 3, 4), 'Étape 4 sur 4');
});
