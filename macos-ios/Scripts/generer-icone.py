#!/usr/bin/env python3
"""Génère l'icône de l'application « DSH Remote ».

LA SILHOUETTE EST CELLE DE DEEPSEEK, ET ELLE N'EST PAS REDESSINÉE À LA MAIN.
`FISH_LOGO_PATH` ci-dessous est le tracé officiel, extrait du harness DeepSeek
(`packages/client/ui-primitives/src/FishLogo.tsx`, viewBox 23,16 × 17,04). Une
première version dessinait la baleine « d'après » le logo, de mémoire : le
résultat, vu à l'écran, ressemblait à une crevette puis à un poisson-lune. Un
logo ne s'approxime pas — il se reprend, ou il ne ressemble à rien.

POURQUOI UN GÉNÉRATEUR ET NON UN PNG POSÉ LÀ. Une icône produite par un outil
graphique n'est pas reproductible : personne ne peut la corriger sans rouvrir
l'outil. Ici, tout est DÉCRIT — le tracé, les pièces du harnais, les couleurs,
les proportions — et le script produit les PNG aux tailles exigées par iOS.
Corriger l'épaisseur d'une sangle, c'est changer un nombre.

POURQUOI PILLOW ET PAS UN CONVERTISSEUR SVG. Mesuré sur cette machine :
`rsvg-convert`, `inkscape`, `magick` et `cairosvg` sont absents, `Pillow` est
présent. Le script n'ajoute donc AUCUNE dépendance au dépôt : il lit le tracé
SVG lui-même, et remplit les polygones avec Pillow.

Usage :
    Scripts/generer-icone.py [--apercu]

`--apercu` écrit en plus une planche de contrôle dans .build/icone-apercu.png,
qui montre l'icône aux tailles réelles d'affichage (180, 120, 60, 40 px) : c'est
à 40 px qu'une icône se juge, pas à 1024.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:  # pragma: no cover - dépendance d'environnement
    print("[icone] Pillow est requis : python3 -m pip install Pillow", file=sys.stderr)
    raise SystemExit(1)

# ── Le tracé officiel ─────────────────────────────────────────────────────────
#
# Source : deepseek-harness, packages/client/ui-primitives/src/FishLogo.tsx
# (lui-même « exact extract » d'un fichier Figma). Reproduit tel quel : le
# moindre chiffre changé déforme le logo.
FISH_LOGO_VIEWBOX = (23.16, 17.04)
FISH_LOGO_PATH = (
    "M22.9168 1.43018C22.6713 1.31018 22.5658 1.53918 22.4223 1.65519C22.3733 1.69269 "
    "22.3318 1.74169 22.2903 1.78669C21.9317 2.1697 21.5127 2.42121 20.9657 2.39121C20.1657 "
    "2.34621 19.4827 2.59771 18.8787 3.20973C18.7502 2.45521 18.3236 2.0047 17.6746 1.71569C17.3351 "
    "1.56568 16.9916 1.41518 16.7536 1.08867C16.5876 0.856163 16.5421 0.597155 16.4591 0.341647C16.4061 "
    "0.187643 16.3536 0.0301382 16.1761 0.00363739C15.9836 -0.0263635 15.9081 0.135141 15.8326 "
    "0.270145C15.5306 0.822162 15.4136 1.43018 15.4251 2.0462C15.4516 3.43174 16.0366 4.53527 17.1991 "
    "5.3203C17.3311 5.4103 17.3651 5.5003 17.3236 5.63181C17.2441 5.90231 17.1501 6.16482 17.0671 "
    "6.43533C17.0141 6.60784 16.9351 6.64584 16.7501 6.57033C16.1121 6.30383 15.5611 5.90931 15.074 "
    "5.4328C14.2475 4.63328 13.5 3.75075 12.568 3.05973C12.349 2.89822 12.13 2.74822 11.9034 "
    "2.60522C10.9524 1.68169 12.028 0.923165 12.277 0.833162C12.5375 0.739159 12.3675 0.41615 11.5259 "
    "0.42015C10.6844 0.42365 9.91439 0.705658 8.93286 1.08117C8.78935 1.13767 8.63835 1.17867 8.48384 "
    "1.21267C7.59332 1.04367 6.66829 1.00617 5.70226 1.11517C3.88321 1.31768 2.43016 2.1777 1.36213 "
    "3.64575C0.0790928 5.4103 -0.222916 7.41536 0.146595 9.50642C0.535106 11.7105 1.66014 13.535 3.38869 "
    "14.9616C5.18125 16.4406 7.24581 17.1657 9.60138 17.0266C11.0319 16.9441 12.6245 16.7526 14.421 "
    "15.2321C14.874 15.4576 15.3496 15.5476 16.1381 15.6151C16.7456 15.6716 17.3306 15.5851 17.7836 "
    "15.4911C18.4931 15.3411 18.4441 14.6841 18.1876 14.5636C16.1081 13.595 16.5646 13.9891 16.1496 "
    "13.67C17.2061 12.42 18.8202 10.1979 19.3182 7.17235C19.3672 6.83834 19.4297 6.36783 19.4222 "
    "6.09732C19.4182 5.93231 19.4562 5.86831 19.6447 5.84931C20.1657 5.78931 20.6712 5.64681 21.1357 "
    "5.3913C22.4833 4.65528 23.0268 3.44624 23.1548 1.9972C23.1738 1.77569 23.1508 1.54668 22.9168 "
    "1.43018ZM11.1749 14.4736C9.15936 12.889 8.18184 12.3675 7.77832 12.39C7.40081 12.4125 7.46881 "
    "12.8445 7.55182 13.126C7.63882 13.404 7.75182 13.5955 7.91033 13.8396C8.01983 14.0011 8.09533 "
    "14.2411 7.80083 14.4216C7.15181 14.8231 6.02327 14.2866 5.97027 14.2601C4.65673 13.4865 3.5587 "
    "12.4655 2.78467 11.069C2.03715 9.72493 1.60314 8.28289 1.53164 6.74384C1.51264 6.37233 1.62214 "
    "6.24082 1.99215 6.17332C2.47916 6.08332 2.98118 6.06432 3.46769 6.13582C5.52476 6.43633 7.27581 "
    "7.35586 8.74385 8.8129C9.58188 9.64243 10.2159 10.634 10.8689 11.6025C11.5634 12.631 12.3105 "
    "13.611 13.262 14.4146C13.598 14.6961 13.866 14.9101 14.1225 15.0681C13.349 15.1546 12.058 15.1731 "
    "11.1749 14.4746L11.1749 14.4736ZM12.141 8.25988C12.141 8.09488 12.273 7.96338 12.439 7.96338C12.4765 "
    "7.96338 12.5105 7.97088 12.541 7.98188C12.5825 7.99688 12.6205 8.01938 12.6505 8.05338C12.7035 "
    "8.10588 12.7335 8.18088 12.7335 8.25988C12.7335 8.42489 12.6015 8.55639 12.4355 8.55639C12.2695 "
    "8.55639 12.141 8.42489 12.141 8.25988ZM15.1415 9.79893C14.949 9.87793 14.7565 9.94544 14.5715 "
    "9.95294C14.2845 9.96794 13.9715 9.85143 13.8015 9.70893C13.5375 9.48742 13.3485 9.36342 13.2695 "
    "8.97691C13.2355 8.8119 13.2545 8.55639 13.2845 8.40989C13.3525 8.09438 13.277 7.89187 13.0545 "
    "7.70787C12.8735 7.55786 12.643 7.51636 12.39 7.51636C12.2955 7.51636 12.209 7.47486 12.1445 "
    "7.44136C12.039 7.38886 11.9519 7.25735 12.035 7.09585C12.0615 7.04335 12.19 6.91584 12.22 "
    "6.89334C12.5635 6.69784 12.9595 6.76184 13.326 6.90834C13.6655 7.04735 13.9225 7.30236 14.292 "
    "7.66287C14.6695 8.09838 14.7375 8.21838 14.9525 8.54539C15.1225 8.8009 15.277 9.06341 15.3831 "
    "9.36392C15.4471 9.55142 15.3641 9.70493 15.1415 9.79893Z"
)

# ── Palette ───────────────────────────────────────────────────────────────────
#
# FOND CLAIR ET BALEINE BLEUE : c'est la déclinaison de marque telle qu'elle
# existe (logo bleu sur blanc). Une première version inversait les deux — fond
# bleu, baleine blanche — pour « faire ressortir » le dessin ; le résultat
# gardait la forme mais perdait la couleur de la marque. Un fond très légèrement
# gris, et non blanc pur, évite que l'icône disparaisse sur un fond blanc.
FOND_HAUT = (255, 255, 255)
FOND_BAS = (236, 239, 248)
BLEU_LOGO = (77, 107, 254)  # #4D6BFE — le bleu de la marque
BLEU_SANGLE = (32, 52, 150)  # la sangle : plus sombre, pour se voir sur le bleu
BLANC = (255, 255, 255)

# Marge autour du logo, en fraction du côté de l'icône.
MARGE = 0.10


# ── Lecture du tracé SVG ──────────────────────────────────────────────────────


def analyser_chemin(donnees: str) -> list[list[tuple[float, float]]]:
    """Convertit un attribut `d` de SVG en une liste de sous-chemins échantillonnés.

    Seules les commandes employées par le logo sont traitées : `M`, `m`, `C`,
    `c`, `L`, `l`, `Z`. Un analyseur générique serait plus long que nécessaire et
    masquerait ce qui compte : le tracé est FIGÉ, il ne s'agit pas d'un moteur
    SVG mais d'un lecteur pour ce fichier-là.
    """
    jetons = re.findall(r"[MmLlCcZz]|-?\d*\.?\d+(?:e-?\d+)?", donnees)
    sous_chemins: list[list[tuple[float, float]]] = []
    courant: list[tuple[float, float]] = []
    x = y = 0.0
    depart = (0.0, 0.0)
    index = 0

    def nombre() -> float:
        nonlocal index
        valeur = float(jetons[index])
        index += 1
        return valeur

    while index < len(jetons):
        commande = jetons[index]
        if not re.match(r"[MmLlCcZz]", commande):
            # Un nombre sans commande : on répète la dernière (implicite en SVG).
            commande = derniere
        else:
            index += 1
        derniere = commande

        if commande in "Mm":
            if courant:
                sous_chemins.append(courant)
                courant = []
            x, y = nombre(), nombre()
            if commande == "m":
                x += depart[0]
                y += depart[1]
            depart = (x, y)
            courant = [(x, y)]

        elif commande in "Ll":
            x, y = nombre(), nombre()
            if commande == "l":
                x += courant[-1][0]
                y += courant[-1][1]
            courant.append((x, y))

        elif commande in "Cc":
            if commande == "c":
                c1 = (nombre() + courant[-1][0], nombre() + courant[-1][1])
                c2 = (nombre() + courant[-1][0], nombre() + courant[-1][1])
                fin = (nombre() + courant[-1][0], nombre() + courant[-1][1])
            else:
                c1 = (nombre(), nombre())
                c2 = (nombre(), nombre())
                fin = (nombre(), nombre())
            p0 = courant[-1]
            for etape in range(1, 17):
                t = etape / 16
                u = 1 - t
                courant.append((
                    u**3 * p0[0] + 3 * u * u * t * c1[0] + 3 * u * t * t * c2[0] + t**3 * fin[0],
                    u**3 * p0[1] + 3 * u * u * t * c1[1] + 3 * u * t * t * c2[1] + t**3 * fin[1],
                ))
            x, y = fin

        elif commande in "Zz":
            if courant:
                courant.append(depart)
                sous_chemins.append(courant)
                courant = []

    if courant:
        sous_chemins.append(courant)
    return sous_chemins


def masque_logo(cote: int) -> Image.Image:
    """Rend le logo seul, en blanc opaque sur fond transparent.

    POURQUOI UN MASQUE ET NON UN DESSIN DIRECT. Le tracé est composé de plusieurs
    sous-chemins dont certains se CREUSENT (l'œil, le ventre). Une règle de
    remplissage « pair-impair » demande de composer les sous-chemins entre eux :
    on les rend donc séparément, puis on les combine par OU exclusif — c'est
    exactement ce que fait un moteur SVG, et Pillow ne le fait pas seul.
    """
    largeur, hauteur = FISH_LOGO_VIEWBOX
    echelle = (cote * (1 - 2 * MARGE)) / largeur
    decalage_x = (cote - largeur * echelle) / 2
    decalage_y = (cote - hauteur * echelle) / 2

    masque = Image.new("L", (cote, cote), 0)
    for sous_chemin in analyser_chemin(FISH_LOGO_PATH):
        calque = Image.new("L", (cote, cote), 0)
        ImageDraw.Draw(calque).polygon(
            [(decalage_x + px * echelle, decalage_y + py * echelle) for px, py in sous_chemin],
            fill=255,
        )
        # OU exclusif, octet par octet : c'est la règle « pair-impair » du SVG,
        # où un sous-chemin intérieur CREUSE le précédent au lieu de s'empiler.
        masque = Image.frombytes(
            "L", masque.size,
            bytes(a ^ b for a, b in zip(masque.tobytes(), calque.tobytes())),
        )
    return masque


# ── Harnais ───────────────────────────────────────────────────────────────────
#
# Coordonnées exprimées dans le repère du LOGO (23,16 × 17,04), et non dans
# celui de l'icône : le harnais est ainsi posé « sur l'animal », et suit
# automatiquement tout changement de marge ou de taille. Les valeurs sont
# mesurées sur le tracé réel — le dos passe par y ≈ 6,1 vers x = 11,5, le ventre
# par y ≈ 11,6 — et non estimées à l'œil.
COLLIER_HAUT = (11.9, 5.05)
COLLIER_BAS = (11.9, 12.35)
BOUCLE = (11.9, 9.6)
ANNEAU = (12.35, 4.62)
RENE_FIN = (15.6, 3.55)

EPISSEUR_COLLIER = 0.024  # en fraction de la largeur du logo


def dessiner_harnais(dessin: ImageDraw.ImageDraw, cote: int) -> None:
    """Pose le harnais sur le logo déjà rendu.

    POURQUOI CES QUATRE PIÈCES. Un simple collier se lirait comme une ceinture,
    et une sangle sans anneau comme une rayure. C'est l'ENSEMBLE qui dit
    « harnais » : le collier qui fait le tour, la boucle qui le règle, la rêne
    qui en repart et l'anneau où l'on attache. Les mêmes pièces que sur un
    cheval, à l'échelle d'une baleine.

    POURQUOI LA RÊNE EST COURTE. Une longe qui traverse l'icône se lit comme une
    canne à pêche : c'est ce que la première version donnait à l'écran. La rêne
    s'arrête donc au-dessus du dos.
    """
    largeur, hauteur = FISH_LOGO_VIEWBOX
    echelle = (cote * (1 - 2 * MARGE)) / largeur
    decalage_x = (cote - largeur * echelle) / 2
    decalage_y = (cote - hauteur * echelle) / 2

    def point(p):
        return (decalage_x + p[0] * echelle, decalage_y + p[1] * echelle)

    epaisseur = max(2, round(EPISSEUR_COLLIER * largeur * echelle))
    lisere = max(1, round(epaisseur * 0.28))

    # Le collier : une sangle qui fait le tour du corps. Elle est posée en deux
    # temps — un liseré clair, puis la sangle sombre — pour rester lisible
    # aussi bien sur le corps bleu que sur le fond clair, aux deux extrémités.
    for couleur, largeur in ((FOND_BAS, epaisseur + 2 * lisere), (BLEU_SANGLE, epaisseur)):
        dessin.line([point(COLLIER_HAUT), point(COLLIER_BAS)], fill=couleur, width=largeur)

    # La boucle, sur le flanc.
    centre = point(BOUCLE)
    cote_boucle = epaisseur * 1.35
    dessin.rectangle(
        [centre[0] - cote_boucle - lisere, centre[1] - cote_boucle - lisere,
         centre[0] + cote_boucle + lisere, centre[1] + cote_boucle + lisere],
        fill=FOND_BAS,
    )
    dessin.rectangle(
        [centre[0] - cote_boucle, centre[1] - cote_boucle,
         centre[0] + cote_boucle, centre[1] + cote_boucle],
        fill=BLEU_SANGLE,
    )
    dessin.line(
        [(centre[0], centre[1] - cote_boucle), (centre[0], centre[1] + cote_boucle)],
        fill=FOND_BAS,
        width=max(1, round(cote_boucle * 0.30)),
    )

    # La rêne : du haut du collier vers l'arrière, en suivant le dos.
    depart = point(COLLIER_HAUT)
    fin = point(RENE_FIN)
    for couleur, largeur in ((FOND_BAS, epaisseur + lisere), (BLEU_SANGLE, round(epaisseur * 0.72))):
        dessin.line([depart, fin], fill=couleur, width=largeur)

    # L'anneau, au bout de la rêne : un CERNE, et non un rond plein — un rond
    # plein ferait un point, un anneau se lit comme « on y attache ».
    centre = point(ANNEAU)
    externe = epaisseur * 1.15
    interne = epaisseur * 0.52
    dessin.ellipse(
        [centre[0] - externe - lisere, centre[1] - externe - lisere,
         centre[0] + externe + lisere, centre[1] + externe + lisere],
        fill=FOND_BAS,
    )
    dessin.ellipse(
        [centre[0] - externe, centre[1] - externe, centre[0] + externe, centre[1] + externe],
        fill=BLEU_SANGLE,
    )
    dessin.ellipse(
        [centre[0] - interne, centre[1] - interne, centre[0] + interne, centre[1] + interne],
        fill=FOND_BAS,
    )


def dessiner(rendu: int) -> Image.Image:
    """Rend l'icône complète au côté demandé, en pixels."""
    # Suréchantillonnage : on dessine 4× plus grand puis on réduit. C'est ce qui
    # donne des bords lisses sans dépendre d'un moteur vectoriel.
    facteur = 4
    grand = rendu * facteur

    # Fond : dégradé vertical très doux, pour que l'icône ne soit pas un aplat.
    fond = Image.new("RGB", (grand, grand), FOND_BAS)
    pinceau = ImageDraw.Draw(fond)
    for ligne in range(grand):
        t = ligne / max(1, grand - 1)
        pinceau.line(
            [(0, ligne), (grand, ligne)],
            fill=tuple(round(FOND_HAUT[i] + (FOND_BAS[i] - FOND_HAUT[i]) * t) for i in range(3)),
        )

    logo = Image.new("RGB", (grand, grand), BLEU_LOGO)
    fond.paste(logo, (0, 0), masque_logo(grand))

    dessiner_harnais(ImageDraw.Draw(fond), grand)
    return fond.resize((rendu, rendu), Image.LANCZOS)


def main() -> int:
    analyseur = argparse.ArgumentParser(description="Génère l'icône de DSH Remote")
    analyseur.add_argument("--apercu", action="store_true",
                           help="écrit en plus une planche de contrôle")
    analyseur.add_argument("--sortie", default=None, help="dossier du catalogue d'assets")
    options = analyseur.parse_args()

    racine = pathlib.Path(__file__).resolve().parent.parent
    catalogue = pathlib.Path(options.sortie) if options.sortie else (
        racine / "App" / "Assets.xcassets" / "AppIcon.appiconset"
    )
    catalogue.mkdir(parents=True, exist_ok=True)

    # iOS n'exige qu'UNE image de 1024 px : le système en dérive toutes les
    # tailles. Les tailles plus petites sont tout de même écrites, pour que
    # l'icône puisse être vérifiée à sa taille d'usage (voir --apercu) et
    # réutilisée ailleurs sans repasser par ce script.
    maitre = dessiner(1024)
    maitre.save(catalogue / "icone-1024.png")

    tailles = {
        "icone-180.png": 180,  # iPhone, écran d'accueil @3x
        "icone-120.png": 120,  # iPhone, écran d'accueil @2x
        "icone-167.png": 167,  # iPad Pro
        "icone-152.png": 152,  # iPad
        "icone-87.png": 87,    # réglages @3x
        "icone-80.png": 80,    # spotlight @2x
        "icone-58.png": 58,    # réglages @2x
        "icone-40.png": 40,    # notification @2x
    }
    for nom, taille in tailles.items():
        maitre.resize((taille, taille), Image.LANCZOS).save(catalogue / nom)

    print(f"[icone] {len(tailles) + 1} fichiers écrits dans {catalogue}")

    if options.apercu:
        planche = racine / ".build" / "icone-apercu.png"
        planche.parent.mkdir(parents=True, exist_ok=True)
        fond_planche = Image.new("RGB", (780, 700), (245, 245, 247))
        x = 24
        for taille in (180, 120, 60, 40):
            vignette = maitre.resize((taille, taille), Image.LANCZOS)
            # Arrondi du masque iOS, pour juger comme à l'écran.
            masque = Image.new("L", (taille, taille), 0)
            ImageDraw.Draw(masque).rounded_rectangle(
                [0, 0, taille - 1, taille - 1], radius=round(taille * 0.2237), fill=255
            )
            fond_planche.paste(vignette, (x, 30), masque)
            x += taille + 26
        # Le maître, réduit : pour juger le dessin lui-même.
        fond_planche.paste(maitre.resize((460, 460), Image.LANCZOS), (24, 200))
        # Et sur fond sombre, pour vérifier qu'il ne disparaît pas.
        sombre = Image.new("RGB", (460, 200), (28, 28, 30))
        sombre.paste(maitre.resize((160, 160), Image.LANCZOS), (20, 20))
        fond_planche.paste(sombre, (24, 480))
        planche.save(planche)
        print(f"[icone] planche de controle : {planche}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
