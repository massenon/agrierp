"""Extrait le décor floral du modèle d'attestation (capture 2000 x 1413) en calque PNG transparent."""
import sys
import numpy as np, cv2
from PIL import Image

src, sortie = sys.argv[1], sys.argv[2]
im = np.array(Image.open(src).convert('RGB')).astype(int)
H, W, _ = im.shape
r, g, b = im[..., 0], im[..., 1], im[..., 2]
mx, mn = im.max(2), im.min(2)
sat = mx - mn

bleu = (b > r + 55) & (b > g + 15) & (b < 235)
orange = (r > 215) & (g > 150) & (g < 215) & (b < 175) & (r - b > 70)
vert = (g >= r - 5) & (g > b + 25) & (mx > 185) & (r > 150)  # vert clair du décor (≠ vert foncé du titre)
decor = bleu | orange | vert

zone = np.zeros((H, W), bool)
zone[0:640, 1440:W - 8] = True         # haut droit (hors texte noir : exclu par la couleur)
zone[490:H - 22, 1925:W - 8] = True    # bord droit
zone[940:H - 22, 0:640] = True         # bas gauche
zone[300:H - 22, 0:130] = True         # bord gauche
zone[0:30, 1100:1700] = True           # filet bleu en haut
zone[330:640, 1440:1900] = False       # aucune décoration sous la date : taches de texte
zone[0:300, 330:430] = False
masque = (decor & zone).astype(np.uint8) * 255

# Les petites taches isolées sont du bruit d'antialiasing du texte : on les retire.
n, lab, stats, _ = cv2.connectedComponentsWithStats((masque > 0).astype(np.uint8), 8)
for i in range(1, n):
    if stats[i, cv2.CC_STAT_AREA] < 40:
        masque[lab == i] = 0

# Combler les trous laissés par le texte noir qui recouvrait le décor (fermeture + peinture).
ferme = cv2.morphologyEx(masque, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (15, 15)))
ferme = ((ferme > 0) & zone).astype(np.uint8) * 255
trous = (ferme > 0) & (masque == 0)
bgr = cv2.cvtColor(im.astype(np.uint8), cv2.COLOR_RGB2BGR)
peint = cv2.inpaint(bgr, trous.astype(np.uint8) * 255, 4, cv2.INPAINT_TELEA)
rgb = cv2.cvtColor(peint, cv2.COLOR_BGR2RGB)

# Bord doux : alpha légèrement flouté.
alpha = cv2.GaussianBlur(ferme, (3, 3), 0)
out = np.dstack([rgb, alpha]).astype(np.uint8)
out[alpha == 0, :3] = 255
Image.fromarray(out, 'RGBA').save(sortie, optimize=True)
print(sortie, out.shape, int((alpha > 0).sum()))
