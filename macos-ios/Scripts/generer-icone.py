#!/usr/bin/env python3
"""Génère l'icône de l'application « DSH Remote ».

Le dessin par défaut est le sifflet arrondi retenu le 14 septembre 2026 :
un corps rond, un bec et une encoche, en bleu DeepSeek. Son contour est
décrit dans `SIFFLET_ARRONDI_PATH`. Les variantes précédentes restent
accessibles avec `--variante` et `--comparer`.

POUR LES VARIANTES HISTORIQUES AVEC BALEINE :
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
    Scripts/generer-icone.py [--apercu] [--variante NOM]
    Scripts/generer-icone.py --comparer        # n'écrit RIEN dans le catalogue

`--apercu` écrit en plus une planche de contrôle dans .build/icone-apercu.png,
qui montre l'icône aux tailles réelles d'affichage (180, 120, 60, 40 px) : c'est
à 40 px qu'une icône se juge, pas à 1024.

`--comparer` met les variantes côte à côte aux mêmes tailles réelles, sur
fond clair et sur fond sombre, sans modifier le catalogue de l'application.
"""

from __future__ import annotations

import argparse
import math
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

# LES TROIS APPARENCES, ET POURQUOI ELLES SONT GÉNÉRÉES ICI.
#
# Depuis iOS 18, l'écran d'accueil peut teinter les icônes (mode sombre, mode
# teinté), et Xcode attend alors un jeu de trois images. Mesuré sur le
# simulateur : sans variante sombre, iOS assombrit lui-même l'icône claire — le
# fond clair devient gris ardoise et l'icône perd sa couleur de marque. Mieux
# vaut décider de ce que chaque apparence montre.
APPARENCES = {
    "claire": {
        "fond_haut": FOND_HAUT,
        "fond_bas": FOND_BAS,
        "logo": (77, 107, 254, 255),
        "sangle": (26, 42, 122, 255),
        "cerne": (255, 255, 255, 255),
        # Le sifflet SEUL reprend le bleu de la marque : posé sur le fond clair,
        # c'est la déclinaison « logo bleu sur blanc », comme la baleine.
        "sifflet": (77, 107, 254, 255),
    },
    "sombre": {
        # Fond bleu profond, baleine au bleu de la marque : lisible sur un fond
        # sombre sans devenir un aplat noir.
        "fond_haut": (26, 34, 62),
        "fond_bas": (12, 16, 34),
        "logo": (108, 134, 255, 255),
        "sangle": (240, 243, 255, 255),
        "cerne": (12, 16, 34, 255),
        "sifflet": (108, 134, 255, 255),
    },
    "teintee": {
        # Le gabarit de teinte : iOS n'utilise que la FORME et applique sa propre
        # couleur. Un fond transparent, un dessin noir, et les sangles en blanc
        # pour rester visibles une fois la teinte appliquée.
        "fond_haut": (0, 0, 0, 0),
        "fond_bas": (0, 0, 0, 0),
        "logo": (0, 0, 0, 255),
        "sangle": (255, 255, 255, 255),
        "cerne": (0, 0, 0, 255),
        "sifflet": (0, 0, 0, 255),
    },
}
# LA SANGLE EST EN CUIR SOMBRE, ET SON CERNE EST CLAIR.
#
# Deux versions ont été écartées, chacune mesurée à l'écran :
#
#   - sangle blanche : elle CADRAIT la baleine comme une grue, et à 40 px
#     l'icône ne se lisait plus comme un animal ;
#   - sangle bleu sombre sans cerne : elle se lisait comme un TROU dans le
#     corps, la baleine paraissait fendue en deux.
#
# Le cuir sombre CERNÉ de clair est la seule combinaison qui se détache du corps
# bleu ET du fond clair, sans masquer la silhouette.
SANGLE = (26, 42, 122)       # cuir sombre
CERNE = (255, 255, 255)      # cerne clair
BLANC = (255, 255, 255)

# Marge autour du logo, en fraction du côté de l'icône.
MARGE = 0.10

# Première silhouette de la planche validée : corps rond en bas à gauche,
# bec montant à droite et encoche ouverte. Un seul contour, sans détail ajouté.
VARIANTE_PAR_DEFAUT = "arrondi"
SIFFLET_ARRONDI_VIEWBOX = (328, 302)
SIFFLET_ARRONDI_PATH = (
    "M160 54 C75 57 0 93 0 180 "
    "C0 251 45 302 119 302 C194 302 237 251 237 184 "
    "C237 163 234 145 229 128 "
    "L328 78 L309 0 L193 38 L218 80 L185 94 Z"
)


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
    # L'échelle est prise sur la PLUS GRANDE dimension. La prendre sur la largeur
    # — première version — donnait un logo plus haut que le cadre : la baleine
    # débordait par le bas, et l'icône n'en montrait que le dos.
    echelle = (cote * (1 - 2 * MARGE)) / max(largeur, hauteur)
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
# automatiquement tout changement de marge ou de taille.
#
# LES VALEURS SONT MESURÉES, PAS ESTIMÉES. Deux tentatives à l'estime ont échoué,
# et la mesure dit pourquoi : le relevé des BANDES OPAQUES de chaque colonne
# montre où le corps est continu et où la queue s'en détache.
#
#     x = 9,5   bandes : (0,86 → 9,62) et (13,24 → 17,00)   ← corps continu
#     x = 13,5  bandes : (3,86 → 6,97), (9,48 → 14,6), (15,11 → 15,87)
#
# À x = 13,5 la colonne est DISCONTINUE : c'est là que la queue se sépare du dos.
# Un collier posé là traversait les fanons — exactement ce que la capture a
# montré.
#
# POURQUOI UN HARNAIS DE TÊTE ET NON UN COLLIER DE POITRAIL. Un collier qui fait
# le tour du corps a été essayé : à 40 px — la taille où une icône se voit
# vraiment — il se lit comme un TRAIT QUI COUPE L'ANIMAL en deux. Le harnais
# retenu est donc celui d'une tête : un montant en arrière du museau, une
# muselière sur le museau, une têtière qui rejoint le montant, et la rêne avec
# son anneau. C'est le licol du cheval, et il habille la baleine sans la trancher.
#
# La baleine va vers la GAUCHE : museau à x ≈ 0,15, œil à (12,4 ; 8,2) —
# l'œil est un TROU du tracé, mesuré à x [12,0 .. 15,3], y [6,8 .. 9,9].
#
# POURQUOI UN BRIDE EN « V », ET NON UN LICOL RECTANGULAIRE. Cinq tentatives ont
# échoué avant celle-ci, et la raison est structurelle : un licol tracé avec des
# segments orthogonaux — deux montants verticaux réunis par une couronne — se lit
# comme un CADRE posé sur l'animal. À l'écran, cela a donné successivement une
# grue, un but de football, puis une cage. Un mors de bride, lui, est un point de
# CONVERGENCE : la têtière et la muselière y descendent en V depuis le haut de la
# tête. C'est cette convergence qui se reconnaît, même à 40 px.
#
# Les points sont mesurés sur le contour réel : le dessus de la tête passe par
# y ≈ 1,06 entre x = 6 et x = 9, et le museau descend jusqu'à y ≈ 16,8.
MORS = (4.6, 7.4)         # le point de convergence, sur le museau

TETIERE = [               # du sommet du crâne au mors
    (9.6, 1.5),
    (8.4, 3.4), (6.6, 5.2), (4.6, 7.4),
]

MUSELIERE = [             # du mors au dessous du museau
    (4.6, 7.4),
    (4.9, 10.4), (5.6, 13.4), (6.9, 15.6),
]

# La rêne : elle repart du mors, COURTEMENT — une longe qui traverse l'icône se
# lit comme une canne à pêche.
RENE = [
    (4.6, 7.4),
    (7.0, 6.6), (9.4, 6.2), (11.6, 6.4),
]

# L'anneau du mors : c'est lui qui réunit les trois sangles et dit « bride ».
ANNEAU = (4.6, 7.4)

EPISSEUR_SANGLE = 0.019  # en fraction de la largeur du logo


def dessiner_harnais(dessin: ImageDraw.ImageDraw, cote: int,
                     sangle=(26, 42, 122, 255),
                     couleur_cerne=(255, 255, 255, 255)) -> None:
    """Pose le harnais sur le logo déjà rendu.

    POURQUOI CES PIÈCES. Une sangle seule se lirait comme une rayure, et un
    anneau sans rêne comme un bouton. C'est l'ENSEMBLE qui dit « harnais » : le
    montant et la muselière qui entourent la tête, la têtière qui relie le
    montant à la joue, la rêne qui repart et l'anneau où l'on attache. Les mêmes
    pièces que sur un licol de cheval, à l'échelle d'une baleine.

    POURQUOI LA SANGLE EST CLAIRE ET CERNÉE DE SOMBRE. Une sangle bleu sombre sur
    un corps bleu se lit comme un TROU dans l'animal — mesuré sur une capture,
    où la baleine paraissait fendue en deux. Claire, elle se lit comme une
    sangle ; le cerne sombre la détache du corps ET du fond clair.
    """
    largeur, hauteur = FISH_LOGO_VIEWBOX
    echelle = (cote * (1 - 2 * MARGE)) / max(largeur, hauteur)
    decalage_x = (cote - largeur * echelle) / 2
    decalage_y = (cote - hauteur * echelle) / 2

    def point(p):
        return (decalage_x + p[0] * echelle, decalage_y + p[1] * echelle)

    epaisseur = max(2, round(EPISSEUR_SANGLE * largeur * echelle))
    epaisseur_cerne = max(1, round(epaisseur * 0.34))

    def bande(points, facteur=1.0):
        """Trace une sangle de la bride, à l'épaisseur du harnais."""
        tracer_bande(dessin, [point(p) for p in points],
                     round(epaisseur * facteur), sangle, couleur_cerne, epaisseur_cerne)

    # La bride : trois sangles qui CONVERGENT vers le mors, plus l'anneau.
    bande(TETIERE)
    bande(MUSELIERE)
    bande(RENE, facteur=0.85)

    centre = point(ANNEAU)
    externe = epaisseur * 1.25
    interne = epaisseur * 0.55
    for rayon, couleur in ((externe + epaisseur_cerne, couleur_cerne),
                           (externe, sangle),
                           (interne, couleur_cerne)):
        dessin.ellipse(
            [centre[0] - rayon, centre[1] - rayon, centre[0] + rayon, centre[1] + rayon],
            fill=couleur,
        )


# ── Le sifflet ────────────────────────────────────────────────────────────────
#
# POURQUOI UN SIFFLET, ET PAS SEULEMENT UNE BRIDE. Le harnais dit « la baleine
# est attachée » ; le sifflet dit « c'est moi qui donne le signal ». Ce que fait
# cette application, c'est émettre un signal — approuver, refuser, interrompre —
# et c'est exactement ce qu'est un sifflet de dresseur : le « signal-pont » qui
# marque l'instant juste, et qui fait revenir l'animal vers son dresseur.
#
# POURQUOI UN SIFFLET DE DRESSEUR ET NON UN SIFFLET D'ARBITRE. Le sifflet
# d'arbitre — le « Fox 40 » — est anguleux, sans pois, et se lit comme un coin.
# Le sifflet de dresseur — le « Thunderer » — a un CORPS ROND, un bec plat et un
# anneau où passer le cordon. C'est le corps rond qui porte le sens, et c'est
# lui qui distingue le dresseur de l'arbitre à 40 px.
#
# Le sifflet est décrit dans un repère LOCAL : le corps est un cercle de rayon 1
# centré sur l'origine, le bec pointe vers les x croissants. `poser_sifflet`
# place, tourne et colorise ce repère.


def tracer_bande(dessin, sommets, largeur, couleur, couleur_cerne,
                 epaisseur_cerne) -> None:
    """Trace une lanière : cerne clair dessous, lanière dessus.

    Le cerne est ce qui détache la lanière du corps bleu ET du fond clair ;
    sans lui, elle se lit comme un trou dans l'animal — mesuré.
    """
    dessin.line(sommets, fill=couleur_cerne,
                width=largeur + 2 * epaisseur_cerne, joint="curve")
    dessin.line(sommets, fill=couleur, width=largeur, joint="curve")


def _le_long_de(centre, theta, t, d):
    """Point situé à `t` le long de l'axe `theta`, et `d` perpendiculairement."""
    ux, uy = math.cos(theta), math.sin(theta)
    return (centre[0] + ux * t - uy * d, centre[1] + uy * t + ux * d)


# LE BEC EST INCLINÉ VERS LE HAUT, ET C'EST CELA QUI LE SÉPARE DU CORPS.
#
# Troisième reprise, et la mesure dit pourquoi les deux premières ont échoué :
# un bec ALIGNÉ sur l'axe du corps se lit comme une CLÉ (corps et bec confondus),
# et un bec TANGENT au sommet du corps se lit comme une ANTENNE (le contour du
# corps se prolonge sans rupture, et l'ensemble devient une louche). Ce qui
# distingue un bec, c'est un ÉPAULEMENT : le bec sort du corps plus bas que son
# sommet, et il MONTE. D'où BEC_ANGLE, appliqué à l'axe du bec seulement — et
# non à celui du corps.
#
# Le point d'attache est pris FRANCHEMENT À L'INTÉRIEUR du corps (0,41 rayon du
# centre) : c'est ce qui garantit la jonction, sans avoir à calculer où le bec
# rencontre exactement le cercle.
# ÉTAT HONNÊTE DE CE DESSIN, APRÈS SIX GÉOMÉTRIES ESSAYÉES.
#
# Celles qui ont échoué, et ce que la planche de contrôle a nommé à chaque fois :
#
#     bec sur l'axe du corps      → une CLÉ
#     bec long, épais, sur le dessus → un PISTOLET
#     bec tangent au sommet       → une ANTENNE
#     bec incliné et fin          → une LOUCHE
#     bec large et court          → un CADENAS
#     lanière pendante ajoutée    → un BALLON
#
# La raison est structurelle, et elle vaut d'être écrite : LE PROFIL D'UN
# SIFFLET EST AMBIGU. Aucun réglage ne le lève, parce que ce qui manque n'est
# pas la forme mais le CONTEXTE — un sifflet ne se reconnaît pas seul.
#
# La géométrie retenue ci-dessous est celle qui s'est le mieux tenue sur la
# planche à 180 et 120 px : bec posé sur le dessus, plus étroit que le corps et
# arrondi au bout. Elle est CONSERVÉE COMME POINT DE DÉPART, PAS COMME RÉSULTAT :
# à 40 px, le sifflet à pois se lit encore comme une tache, et la variante
# « baleine + sifflet » est PLUS CONFUSE que la bride qu'elle remplace.
#
# LA FAMILLE QUI LIT, C'EST CELLE DES ULTRASONS — et c'est la seule des cinq
# variantes qui se distingue à 60 px. Le sifflet à pois reste ambigu ; le
# sifflet à ultrasons AVEC ses ondes se lit comme « un appareil qui émet un
# signal », ce qui est la fonction réelle de l'application.
#
# Aucune des cinq variantes n'est adoptée : `--comparer` sert à trancher, et la
# décision n'est pas prise.
BEC_ORIGINE = (0.0, 0.50)       # le long de l'axe, puis perpendiculairement
BEC_ANGLE = 0.0                 # degrés : 0 = bec parallèle à l'axe du corps
BEC_LONGUEUR = (0.85, 2.55)     # du talon au bout, le long de l'axe du bec
LARGEUR_BEC = (0.46, 0.28)
DECALAGE_FENETRE, LARGEUR_FENETRE = 0.44, 0.19
FENETRE_DEBUT, FENETRE_FIN = 0.02, 0.72


def _masque_corps_sifflet(cote, centre, rayon, theta, ep=0.0):
    """Le corps du sifflet — corps rond, bec, anneau — SANS la fenêtre.

    `ep` dilate toutes les distances du dessin. C'est ainsi que le cerne se
    trace : sans filtre de dilatation, et donc sans dépendance de plus.
    """
    r = rayon + ep
    masque = Image.new("L", (cote, cote), 0)
    pinceau = ImageDraw.Draw(masque)

    # LE CORPS ROND. C'est lui qui dit « dresseur » plutôt qu'« arbitre ».
    pinceau.ellipse(
        [centre[0] - r, centre[1] - r, centre[0] + r, centre[1] + r],
        fill=255,
    )

    # LE BEC : un tuyau court posé sur le dessus du corps, INCLINÉ vers le haut,
    # arrondi au bout. C'est l'inclinaison qui crée l'épaulement, et c'est
    # l'épaulement qui dit « bec » plutôt que « clé » ou « antenne ».
    origine = _le_long_de(centre, theta, BEC_ORIGINE[0] * rayon, BEC_ORIGINE[1] * rayon)
    theta_bec = theta + math.radians(BEC_ANGLE)
    debut, fin = BEC_LONGUEUR[0] * rayon - ep, BEC_LONGUEUR[1] * rayon + ep
    demi_debut, demi_fin = LARGEUR_BEC[0] * rayon + ep, LARGEUR_BEC[1] * rayon + ep
    pinceau.polygon([
        _le_long_de(origine, theta_bec, debut, demi_debut),
        _le_long_de(origine, theta_bec, fin, demi_fin),
        _le_long_de(origine, theta_bec, fin, -demi_fin),
        _le_long_de(origine, theta_bec, debut, -demi_debut),
    ], fill=255)
    bout = _le_long_de(origine, theta_bec, fin, 0.0)
    pinceau.ellipse(
        [bout[0] - demi_fin, bout[1] - demi_fin,
         bout[0] + demi_fin, bout[1] + demi_fin],
        fill=255,
    )

    # L'ANNEAU, où passe le cordon. Il est détaché du corps juste ce qu'il faut
    # pour que son trou reste OUVERT : un anneau plein se lit comme une bosse.
    arriere = _le_long_de(centre, theta, -(1.35 * rayon + ep), 0.0)
    externe, interne = 0.44 * rayon + ep, 0.20 * rayon - ep
    pinceau.ellipse(
        [arriere[0] - externe, arriere[1] - externe,
         arriere[0] + externe, arriere[1] + externe],
        fill=255,
    )
    if interne > 0.5:
        pinceau.ellipse(
            [arriere[0] - interne, arriere[1] - interne,
             arriere[0] + interne, arriere[1] + interne],
            fill=0,
        )
    return masque


def _masque_fenetre_sifflet(cote, centre, rayon, theta):
    """La fenêtre : le trou par où sort l'air, sur le dessus, avant le bec."""
    masque = Image.new("L", (cote, cote), 0)
    pinceau = ImageDraw.Draw(masque)
    debut, fin = FENETRE_DEBUT * rayon, FENETRE_FIN * rayon
    demi, decalage = LARGEUR_FENETRE * rayon, DECALAGE_FENETRE * rayon

    pinceau.polygon([
        _le_long_de(centre, theta, debut, decalage + demi),
        _le_long_de(centre, theta, fin, decalage + demi),
        _le_long_de(centre, theta, fin, decalage - demi),
        _le_long_de(centre, theta, debut, decalage - demi),
    ], fill=255)
    for extremite in (debut, fin):
        point = _le_long_de(centre, theta, extremite, decalage)
        pinceau.ellipse(
            [point[0] - demi, point[1] - demi, point[0] + demi, point[1] + demi],
            fill=255,
        )
    return masque


def poser_sifflet(image, cote, centre, rayon, angle_deg, couleur,
                  couleur_cerne=None, epaisseur_cerne=0) -> None:
    """Pose un sifflet sur un CALQUE RGBA transparent, cerne compris.

    POURQUOI UN CALQUE, ET NON LE FOND DIRECTEMENT. La fenêtre est CREUSÉE, pas
    peinte : creuser demande de rendre transparents les pixels qu'elle occupe, et
    cela n'a de sens que sur un calque RGBA. Sur le fond, qui est RGB, le même
    paste de (0, 0, 0, 0) PEINT DU NOIR — la fenêtre est alors un trou noir, ce
    qui était le cas de la première planche. C'est l'appelant qui compose le
    calque sur le fond, une fois la fenêtre creusée.
    """
    theta = math.radians(angle_deg)
    if couleur_cerne is not None and epaisseur_cerne > 0:
        image.paste(
            Image.new("RGBA", (cote, cote), tuple(couleur_cerne)), (0, 0),
            _masque_corps_sifflet(cote, centre, rayon, theta, ep=epaisseur_cerne),
        )
    image.paste(
        Image.new("RGBA", (cote, cote), tuple(couleur)), (0, 0),
        _masque_corps_sifflet(cote, centre, rayon, theta),
    )
    image.paste((0, 0, 0, 0), (0, 0),
                _masque_fenetre_sifflet(cote, centre, rayon, theta))


# OÙ LE SIFFLET SE POSE QUAND IL ACCOMPAGNE LA BALEINE.
#
# CES VALEURS SONT RELEVÉES, PAS ESTIMÉES. Le relevé des bandes occupées,
# colonne par colonne, se refait à tout moment avec `Scripts/mesurer-silhouette.py`,
# qui donne l'espace réellement libre dans le repère du logo :
#
#     x = 3,5   occupé 1,8→6,2 et 12,2→15,1   → libre 6,2→12,2
#     x = 5,5   occupé 1,1→6,7 et 14,0→16,3   → libre 6,7→14,0
#     x = 7,5   occupé 1,1→7,8 et 14,6→16,9   → libre 7,8→14,6
#
# C'est le blanc du ventre : un vaste lens libre entre le dos et la mâchoire,
# de x ≈ 2,5 à x ≈ 11,5. Le sifflet s'y pose SANS MORDRE le corps, et le
# cordon descend du sommet du crâne, là où passait la têtière.
#
# L'ANGLE DE 155° FAIT POINTER LE BEC VERS LE BAS ET LA GAUCHE, donc l'anneau
# vers le haut et la droite : c'est de là que vient le cordon. Un sifflet dont
# l'anneau ne fait pas face à son cordon se lit comme deux objets posés l'un à
# côté de l'autre.
#
# LA TAILLE A ÉTÉ AUGMENTÉE APRÈS LA PREMIÈRE PLANCHE, et pour une raison
# mesurable : à 1,30 rayon, le sifflet ne mesurait que 5,3 unités de long dans
# un lens qui en offre 7 au plus étroit — il se lisait comme une tache sombre
# sur le ventre, à 120 px comme à 40. À 1,75, le corps rond se distingue du bec.
# Le prix est que la POINTE DU BEC mord la mâchoire, à x ≈ 2,3 : c'est assumé,
# le sifflet est dessiné APRÈS la baleine et son cerne le détache du corps.
SIFFLET_CENTRE = (5.9, 10.6)
SIFFLET_RAYON = 1.75
SIFFLET_ANGLE = 155.0
CORDON = [
    (9.2, 2.2),
    (8.5, 3.9), (8.3, 6.0), (8.5, 7.8), (8.74, 9.28),
]


# ── Le sifflet court ──────────────────────────────────────────────────────────
#
# CE TRACÉ EST UNE RÉPONSE À LA PLANCHE `designs/dsh-remote/sifflet-minimaliste/`,
# et il s'en écarte sur quatre points PRÉCIS. Les trois silhouettes de cette
# planche se lisent mieux que les cinq variantes d'ici — mais elles se lisent
# aussi comme une virgule, un oiseau et un cadenas, et la raison est mesurable :
#
#   1. BEC HORIZONTAL, PAS DIAGONAL. Un bec qui monte en diagonale laisse la
#      masse ronde dominer, et le bec se lit comme une QUEUE : virgule, note de
#      musique, poisson. Horizontal, il donne une silhouette large et basse, et
#      c'est l'ÉPAULEMENT — le bec qui sort du flanc, pas du sommet — qui dit
#      « sifflet ». Le commentaire de BEC_ANGLE l'avait trouvé pour la baleine,
#      puis l'a perdu en passant au sifflet seul.
#   2. ENCOCHE SUR LE DESSUS DU BEC, PAS À LA JONCTION. La fenêtre d'air est SUR
#      le bec. Posée à la jonction bec/corps, elle se lit comme un cou ou un
#      œil — c'est ce qui fait basculer la goutte de la planche vers l'oiseau.
#   3. BEC COURT : rapport corps/bec ≈ 1:1. Sur la planche il vaut 1:1,4 ; ici,
#      avec BEC_LONGUEUR = (0.85, 2.55), il valait 1:2,5 — d'où le têtard.
#   4. AUCUN ANNEAU. C'est l'anneau qui transforme le sifflet à pois en têtard
#      sur la planche de comparaison : il fait une tête à l'autre bout, et la
#      silhouette devient un spermatozoïde. Le retirer coûte le cordon, et le
#      cordon ne manque pas.
#
# Le repère est celui de `_masque_corps_sifflet` : corps de rayon 1 à l'origine,
# bec vers les x croissants, et `poser_*` place, tourne et colorise.
COURT_BEC = (0.55, 1.95)         # du talon au bout — court, d'où le nom
COURT_LARGEUR_BEC = (0.62, 0.50) # peu effilé : un bec de Thunderer est droit
COURT_BEC_DECALAGE = 0.28        # le bec sort du FLANC, au-dessus de l'axe
COURT_FENETRE = (1.02, 1.62)     # la fenêtre, le long du bec
COURT_FENETRE_LARGEUR = 0.17


def _masque_sifflet_court(cote, centre, rayon, theta, ep=0.0):
    """Le corps du sifflet court — corps rond et bec droit — SANS la fenêtre.

    Pas d'anneau, pas de bague, pas de gorge : c'est le retrait de ces pièces
    qui fait la lisibilité, et non un réglage plus fin de leurs proportions.
    """
    r = rayon + ep
    masque = Image.new("L", (cote, cote), 0)
    pinceau = ImageDraw.Draw(masque)

    def point(t, d=0.0):
        return _le_long_de(centre, theta, t * rayon, d * rayon)

    # LE CORPS. Rond et compact : c'est la masse qui porte la reconnaissance.
    pinceau.ellipse([centre[0] - r, centre[1] - r, centre[0] + r, centre[1] + r],
                    fill=255)

    # LE BEC. Horizontal, décalé vers le haut pour créer l'épaulement, et coupé
    # DROIT au bout — un bout arrondi rendrait le bec au corps, et l'ensemble
    # redeviendrait une goutte.
    haut_talon = COURT_BEC_DECALAGE + COURT_LARGEUR_BEC[0] / 2
    bas_talon = COURT_BEC_DECALAGE - COURT_LARGEUR_BEC[0] / 2
    haut_bout = COURT_BEC_DECALAGE + COURT_LARGEUR_BEC[1] / 2
    bas_bout = COURT_BEC_DECALAGE - COURT_LARGEUR_BEC[1] / 2
    marge = ep / rayon if rayon else 0.0
    pinceau.polygon([
        point(COURT_BEC[0] - marge, haut_talon + marge),
        point(COURT_BEC[1] + marge, haut_bout + marge),
        point(COURT_BEC[1] + marge, bas_bout - marge),
        point(COURT_BEC[0] - marge, bas_talon - marge),
    ], fill=255)
    return masque


def _masque_fenetre_courte(cote, centre, rayon, theta):
    """La fenêtre : une encoche franche sur le DESSUS DU BEC.

    Elle est ouverte sur le bord supérieur — elle entame le contour au lieu
    d'être un trou intérieur. Un trou fermé se lit comme un œil ; une encoche
    qui mord le contour se lit comme une ouverture.
    """
    masque = Image.new("L", (cote, cote), 0)
    pinceau = ImageDraw.Draw(masque)

    def point(t, d=0.0):
        return _le_long_de(centre, theta, t * rayon, d * rayon)

    haut = COURT_BEC_DECALAGE + COURT_LARGEUR_BEC[0]  # franchement au-delà du bord
    bas = COURT_BEC_DECALAGE + COURT_LARGEUR_BEC[1] / 2 - COURT_FENETRE_LARGEUR
    pinceau.polygon([
        point(COURT_FENETRE[0], haut),
        point(COURT_FENETRE[1], haut),
        point(COURT_FENETRE[1], bas),
        point(COURT_FENETRE[0], bas),
    ], fill=255)
    return masque


def poser_sifflet_court(image, cote, centre, rayon, angle_deg, couleur,
                        couleur_cerne=None, epaisseur_cerne=0) -> None:
    """Pose un sifflet court sur un calque RGBA, cerne compris.

    Comme `poser_sifflet` : la fenêtre est CREUSÉE, donc le calque doit être
    RGBA et c'est l'appelant qui le compose sur le fond.
    """
    theta = math.radians(angle_deg)
    if couleur_cerne is not None and epaisseur_cerne > 0:
        image.paste(
            Image.new("RGBA", (cote, cote), tuple(couleur_cerne)), (0, 0),
            _masque_sifflet_court(cote, centre, rayon, theta, ep=epaisseur_cerne),
        )
    image.paste(
        Image.new("RGBA", (cote, cote), tuple(couleur)), (0, 0),
        _masque_sifflet_court(cote, centre, rayon, theta),
    )
    image.paste((0, 0, 0, 0), (0, 0),
                _masque_fenetre_courte(cote, centre, rayon, theta))


def dessiner_sifflet_court_seul(rendu: int, apparence: str = "claire") -> Image.Image:
    """Rend le sifflet court SEUL, sans la baleine."""
    facteur = 4
    grand = rendu * facteur
    fond = fond_degrade(apparence, grand)

    rayon = grand / 8.0
    # Bec vers la gauche, comme la baleine regarde à gauche et comme les autres
    # variantes : la planche ne doit comparer que des dessins, pas des sens.
    calque = Image.new("RGBA", (grand, grand), (0, 0, 0, 0))
    poser_sifflet_court(calque, grand, (grand / 2, grand / 2), rayon, 180.0,
                        tuple(APPARENCES[apparence]["sifflet"]))
    calque = _cadrer_sur_mesure(calque, grand, grand * (1 - 2 * MARGE))
    fond.paste(calque, (0, 0), calque)
    return fond.resize((rendu, rendu), Image.LANCZOS)


# OÙ LE SIFFLET COURT SE POSE SUR LA BALEINE.
#
# Le sifflet à pois occupe le lens du ventre à 155°, bec vers le bas-gauche,
# parce que son anneau devait faire face au cordon. SANS ANNEAU, cette
# contrainte tombe : le bec peut pointer vers la GAUCHE, dans le sens de la
# baleine, et le sifflet cesse d'être un objet posé en travers du ventre.
#
# Le lens libre relevé par `mesurer-silhouette.py` va de x ≈ 2,5 à x ≈ 11,5 ;
# le centre est repris du sifflet à pois, dont le placement était mesuré.
COURT_CENTRE = (6.1, 10.3)
COURT_RAYON = 1.62


def dessiner_baleine_sifflet_court(fond, grand: int, reglages: dict) -> None:
    """Pose le sifflet court sur la baleine déjà rendue, sans cordon.

    PAS DE CORDON, et c'est le corollaire du retrait de l'anneau : un cordon qui
    ne s'attache à rien se lit comme une rayure. Le sifflet est posé sur le
    ventre comme une marque, et le cerne suffit à le détacher du corps.
    """
    largeur, hauteur = FISH_LOGO_VIEWBOX
    echelle = (grand * (1 - 2 * MARGE)) / max(largeur, hauteur)
    decalage_x = (grand - largeur * echelle) / 2
    decalage_y = (grand - hauteur * echelle) / 2
    centre = (decalage_x + COURT_CENTRE[0] * echelle,
              decalage_y + COURT_CENTRE[1] * echelle)

    epaisseur = max(2, round(EPISSEUR_SANGLE * largeur * echelle))
    calque = Image.new("RGBA", (grand, grand), (0, 0, 0, 0))
    poser_sifflet_court(
        calque, grand, centre, COURT_RAYON * echelle, 180.0,
        tuple(reglages["sangle"]),
        couleur_cerne=tuple(reglages["cerne"]),
        epaisseur_cerne=max(1, round(epaisseur * 0.34)),
    )
    fond.paste(calque, (0, 0), calque)


# ── Le sifflet à ultrasons ────────────────────────────────────────────────────
#
# POURQUOI IL CHANGE LE SENS, ET PAS SEULEMENT LA FORME.
#
# Un sifflet à ultrasons — « silent whistle », ou sifflet de Galton, inventé en
# 1876 — émet entre 23 et 54 kHz, au-dessus de l'audition humaine. Sa raison
# d'être est que LE SIGNAL PASSE ENTRE L'OPÉRATEUR ET L'ANIMAL SANS ÊTRE ENTENDU
# DE CEUX QUI SONT LÀ.
#
# C'est très exactement ce qu'est cette application : un canal privé entre un
# opérateur et son agent, invisible pour qui regarde. Le sifflet à pois commande
# DEVANT la foule ; le sifflet à ultrasons commande À CÔTÉ d'elle.
#
# ET IL LÈVE LE DÉFAUT N° 1 DU SIFFLET À POIS. La planche de contrôle avait
# désigné la lecture « arbitre » comme le risque principal — un sifflet de sport
# qui arrête le jeu et sanctionne. La forme d'un sifflet à ultrasons est celle
# d'un INSTRUMENT : un corps cylindrique, une bague moletée de réglage, un
# anneau. Il n'y a plus d'arbitre à y lire.
#
# SA FORME EST CELLE D'UN ACME 535, et elle est LONGUE ET FINE — c'est le risque
# de cette variante, et il est réel : un cylindre segmenté se lit comme une PILE
# à 40 px. La variante « + ondes » existe pour cette raison : ce ne sont pas les
# gorges du métal qui disent « ultrasons », c'est le signal.
ULTRASON_CORPS = (-2.10, 0.30)   # la capsule, le long de l'axe
ULTRASON_BEC = (0.30, 1.35)      # du corps au bout du bec
ULTRASON_LARGEUR_BEC = (0.60, 0.40)
ULTRASON_BAGUE = (-1.45, -0.55)  # la bague moletée, en travers du corps
ULTRASON_RENFLEMENT = 1.05       # son rayon, en rayons du corps
ULTRASON_ANNEAU = (-2.75, 0.42, 0.19)   # position, rayon externe, rayon interne
ULTRASON_GORGES = (-1.22, -1.00, -0.78)  # les trois gorges de la bague
ULTRASON_ONDE_RAYONS = (1.05, 1.60, 2.15)
ULTRASON_ONDE_OUVERTURE = 48.0   # demi-angle d'ouverture des ondes, en degrés


def _poser_masque(image, cote: int, masque, couleur) -> None:
    """Pose une couleur à travers un masque, sur un calque RGBA."""
    image.paste(Image.new("RGBA", (cote, cote), tuple(couleur)), (0, 0), masque)


def _masque_ultrason(cote, centre, rayon, theta, ep=0.0):
    """Le corps d'un sifflet à ultrasons : capsule, bague, bec, anneau.

    Une CAPSULE et non un cercle : c'est ce qui fait un instrument plutôt qu'un
    accessoire de sport, et c'est toute la différence de lecture entre les deux
    variantes.
    """
    r = rayon + ep
    masque = Image.new("L", (cote, cote), 0)
    pinceau = ImageDraw.Draw(masque)

    def point(t, d=0.0):
        return _le_long_de(centre, theta, t * rayon, d * rayon)

    # Le corps : un segment épais, arrondi à ses deux bouts.
    arriere, avant = point(ULTRASON_CORPS[0]), point(ULTRASON_CORPS[1])
    pinceau.line([arriere, avant], fill=255, width=max(1, round(2 * r)))
    for extremite in (arriere, avant):
        pinceau.ellipse(
            [extremite[0] - r, extremite[1] - r, extremite[0] + r, extremite[1] + r],
            fill=255,
        )

    # La bague moletée : un RENFLEMENT. Des gorges creusées dans le corps
    # l'auraient découpé en rondelles — un cylindre segmenté se lit comme une
    # pile, et la silhouette se serait disloquée à 40 px.
    demi_bague = ULTRASON_RENFLEMENT * rayon + ep
    debut, fin = point(ULTRASON_BAGUE[0]), point(ULTRASON_BAGUE[1])
    pinceau.line([debut, fin], fill=255, width=max(1, round(2 * demi_bague)))
    for extremite in (debut, fin):
        pinceau.ellipse(
            [extremite[0] - demi_bague, extremite[1] - demi_bague,
             extremite[0] + demi_bague, extremite[1] + demi_bague],
            fill=255,
        )

    # Le bec : court, peu effilé. Un sifflet à ultrasons n'a pas de gros bec.
    bec_debut, bec_fin = point(ULTRASON_BEC[0]), point(ULTRASON_BEC[1])
    demi_debut = ULTRASON_LARGEUR_BEC[0] * rayon + ep
    demi_fin = ULTRASON_LARGEUR_BEC[1] * rayon + ep
    pinceau.polygon([
        point(ULTRASON_BEC[0], ULTRASON_LARGEUR_BEC[0]),
        point(ULTRASON_BEC[1], ULTRASON_LARGEUR_BEC[1]),
        point(ULTRASON_BEC[1], -ULTRASON_LARGEUR_BEC[1]),
        point(ULTRASON_BEC[0], -ULTRASON_LARGEUR_BEC[0]),
    ], fill=255)
    pinceau.ellipse(
        [bec_fin[0] - demi_fin, bec_fin[1] - demi_fin,
         bec_fin[0] + demi_fin, bec_fin[1] + demi_fin],
        fill=255,
    )
    del bec_debut, demi_debut

    # L'anneau, où passe la lanière.
    arriere_anneau = point(ULTRASON_ANNEAU[0])
    externe = ULTRASON_ANNEAU[1] * rayon + ep
    interne = ULTRASON_ANNEAU[2] * rayon - ep
    pinceau.ellipse(
        [arriere_anneau[0] - externe, arriere_anneau[1] - externe,
         arriere_anneau[0] + externe, arriere_anneau[1] + externe],
        fill=255,
    )
    if interne > 0.5:
        pinceau.ellipse(
            [arriere_anneau[0] - interne, arriere_anneau[1] - interne,
             arriere_anneau[0] + interne, arriere_anneau[1] + interne],
            fill=0,
        )
    return masque


def _masques_gorges(cote, centre, rayon, theta):
    """Les gorges de la bague moletée — PARTIELLES, jamais traversantes.

    Une gorge qui traverse le corps détache un tronçon : la silhouette se
    disloque, et à 40 px il ne reste qu'un chapelet de taches. Les gorges
    s'arrêtent donc avant le bord, du côté opposé aux ondes.
    """
    masques = []
    for position in ULTRASON_GORGES:
        masque = Image.new("L", (cote, cote), 0)
        pinceau = ImageDraw.Draw(masque)
        demi = 0.055 * rayon
        # Le trait va d'un bord de la bague à 55 % de sa hauteur : la gorge est
        # franche, et la bague reste d'une seule pièce.
        pinceau.line(
            [_le_long_de(centre, theta, position * rayon, -1.20 * rayon),
             _le_long_de(centre, theta, position * rayon, 0.55 * rayon)],
            fill=255, width=max(1, round(2 * demi)),
        )
        masques.append(masque)
    return masques


def _masques_ondes(cote, centre, rayon, theta_deg):
    """Les ondes : des arcs SERRÉS, et c'est leur serrage qui dit « ultrasons ».

    Un signal grave s'écrit avec trois arcs largement espacés ; un signal
    ultrasonore, avec des arcs rapprochés. L'écartement est donc le seul porteur
    du sens, et il est réglé en fraction de rayon — pas au jugé.
    """
    theta = math.radians(theta_deg)
    origine = _le_long_de(centre, theta, ULTRASON_BEC[1] * rayon, 0.0)
    masques = []
    for rang, multiple in enumerate(ULTRASON_ONDE_RAYONS):
        rayon_onde = multiple * rayon
        masque = Image.new("L", (cote, cote), 0)
        # L'épaisseur DÉCROÎT avec le rang : c'est ce qui donne l'éloignement
        # sans avoir à rétrécir l'arc, qui doit rester lisible.
        epaisseur = max(1, round((0.16 - 0.03 * rang) * rayon))
        ImageDraw.Draw(masque).arc(
            [origine[0] - rayon_onde, origine[1] - rayon_onde,
             origine[0] + rayon_onde, origine[1] + rayon_onde],
            start=theta_deg - ULTRASON_ONDE_OUVERTURE,
            end=theta_deg + ULTRASON_ONDE_OUVERTURE,
            fill=255, width=epaisseur,
        )
        masques.append(masque)
    return masques


def poser_ultrason(image, cote, centre, rayon, angle_deg, couleur,
                   couleur_cerne=None, epaisseur_cerne=0, ondes=False) -> None:
    """Pose un sifflet à ultrasons sur un calque RGBA, cerne et ondes compris."""
    theta = math.radians(angle_deg)
    if ondes:
        for masque in _masques_ondes(cote, centre, rayon, angle_deg):
            _poser_masque(image, cote, masque, couleur)
    if couleur_cerne is not None and epaisseur_cerne > 0:
        _poser_masque(image, cote,
                      _masque_ultrason(cote, centre, rayon, theta, ep=epaisseur_cerne),
                      couleur_cerne)
    _poser_masque(image, cote, _masque_ultrason(cote, centre, rayon, theta), couleur)
    # Les gorges sont CREUSÉES, comme la fenêtre du sifflet à pois : peintes
    # d'une couleur supposée être « celle du fond », elles laisseraient une
    # marque visible dès que le fond n'est pas un aplat.
    for masque in _masques_gorges(cote, centre, rayon, theta):
        image.paste((0, 0, 0, 0), (0, 0), masque)


def _cadrer_sur_mesure(calque, cote: int, interieur: float):
    """Rogne un calque sur son contenu, puis le remet à l'échelle demandée.

    POURQUOI RECADRER SUR LA MESURE. Choisir le rayon « au jugé » a coûté quatre
    essais sur le sifflet à pois, et chacun laissait l'objet soit trop petit,
    soit débordant du cadre. Ici le dessin est fait à une taille quelconque,
    puis ROGNÉ SUR SON CONTENU : un seul réglage, `interieur`, et il est
    respecté par construction — y compris quand une variante ajoute des ondes
    qui allongent le dessin.
    """
    boite = calque.getbbox()
    if boite is None:
        return calque
    contenu = calque.crop(boite)
    echelle = interieur / max(contenu.size)
    taille = (max(1, round(contenu.width * echelle)), max(1, round(contenu.height * echelle)))
    contenu = contenu.resize(taille, Image.LANCZOS)
    resultat = Image.new("RGBA", (cote, cote), (0, 0, 0, 0))
    resultat.paste(contenu, ((cote - taille[0]) // 2, (cote - taille[1]) // 2))
    return resultat


def dessiner_ultrason_seul(rendu: int, apparence: str = "claire",
                           ondes: bool = False) -> Image.Image:
    """Rend un sifflet à ultrasons SEUL, avec ou sans ses ondes."""
    facteur = 4
    grand = rendu * facteur
    fond = fond_degrade(apparence, grand)

    # Le rayon est quelconque : `_cadrer_sur_mesure` s'occupe du cadre.
    rayon = grand / 8.0
    # Le bec pointe vers la gauche comme la baleine regarde à gauche. L'angle
    # est plus ouvert quand les ondes sont là, pour que l'ensemble — long —
    # occupe la diagonale au lieu de déborder.
    angle = 205.0 if ondes else 197.0
    calque = Image.new("RGBA", (grand, grand), (0, 0, 0, 0))
    poser_ultrason(calque, grand, (grand / 2, grand / 2), rayon, angle,
                   tuple(APPARENCES[apparence]["sifflet"]), ondes=ondes)
    calque = _cadrer_sur_mesure(calque, grand, grand * (1 - 2 * MARGE))
    fond.paste(calque, (0, 0), calque)
    return fond.resize((rendu, rendu), Image.LANCZOS)
def dessiner_sifflet_seul(rendu: int, apparence: str = "claire") -> Image.Image:
    """Rend le sifflet à pois SEUL, sans la baleine.

    Le bec pointe vers la gauche, comme la baleine regarde à gauche : les deux
    variantes ont ainsi le même sens de lecture, et l'œil ne fait pas l'aller-
    retour entre deux orientations.
    """
    facteur = 4
    grand = rendu * facteur
    fond = fond_degrade(apparence, grand)

    # Le rayon est quelconque : `_cadrer_sur_mesure` s'occupe du cadre, et les
    # deux familles de sifflet occupent donc exactement la même surface — sans
    # quoi la planche comparerait des tailles autant que des dessins.
    rayon = grand / 8.0
    calque = Image.new("RGBA", (grand, grand), (0, 0, 0, 0))
    poser_sifflet(calque, grand, (grand / 2, grand / 2), rayon, 192.0,
                  tuple(APPARENCES[apparence]["sifflet"]))
    calque = _cadrer_sur_mesure(calque, grand, grand * (1 - 2 * MARGE))
    fond.paste(calque, (0, 0), calque)
    return fond.resize((rendu, rendu), Image.LANCZOS)


def fond_degrade(apparence: str, cote: int) -> Image.Image:
    """Le fond de l'icône : dégradé vertical très doux, ou TRANSPARENT en teinté.

    En mode teinté, iOS n'utilise que la forme : un fond transparent est ce qui
    permet à sa propre couleur de s'appliquer.
    """
    reglages = APPARENCES[apparence]
    if len(reglages["fond_haut"]) == 4:
        fond = Image.new("RGBA", (cote, cote), (0, 0, 0, 0))
    else:
        fond = Image.new("RGB", (cote, cote), reglages["fond_bas"])
    pinceau = ImageDraw.Draw(fond)
    for ligne in range(cote):
        t = ligne / max(1, cote - 1)
        haut, bas = reglages["fond_haut"], reglages["fond_bas"]
        couleur = tuple(round(haut[i] + (bas[i] - haut[i]) * t) for i in range(len(haut)))
        pinceau.line([(0, ligne), (cote, ligne)], fill=couleur)
    return fond


def dessiner_sifflet_arrondi(rendu: int, apparence: str = "claire") -> Image.Image:
    """Rend la silhouette retenue, avec les mêmes proportions dans les trois modes."""
    grand = rendu * 4
    largeur, hauteur = SIFFLET_ARRONDI_VIEWBOX
    echelle = grand * 0.70 / largeur
    dx = (grand - largeur * echelle) / 2
    dy = (grand - hauteur * echelle) / 2
    masque = Image.new("L", (grand, grand), 0)
    contour = analyser_chemin(SIFFLET_ARRONDI_PATH)[0]
    ImageDraw.Draw(masque).polygon(
        [(dx + x * echelle, dy + y * echelle) for x, y in contour], fill=255
    )

    if apparence == "claire":
        fond = Image.new("RGB", (grand, grand), BLANC)
        couleur = BLEU_LOGO
    elif apparence == "sombre":
        # Le système fournit le fond sombre ; le bleu du signe reste inchangé.
        fond = Image.new("RGBA", (grand, grand), (0, 0, 0, 0))
        couleur = (*BLEU_LOGO, 255)
    elif apparence == "teintee":
        # Gabarit en niveaux de gris : signe clair sur fond noir, recoloré par iOS.
        fond = Image.new("RGB", (grand, grand), (0, 0, 0))
        couleur = BLANC
    else:
        raise ValueError(f"apparence inconnue : {apparence}")
    fond.paste(couleur, (0, 0, grand, grand), masque)
    return fond.resize((rendu, rendu), Image.LANCZOS)


def dessiner_icone_macos(source: Image.Image) -> Image.Image:
    """Cadre le dessin dans une tuile arrondie, pour le paquet macOS au format ICNS."""
    cote = source.width
    facteur = 4
    grand = cote * facteur
    marge = round(grand * 100 / 1024)
    taille = grand - 2 * marge
    tuile = source.resize((taille, taille), Image.LANCZOS).convert("RGBA")
    masque = Image.new("L", (taille, taille), 0)
    ImageDraw.Draw(masque).rounded_rectangle(
        (0, 0, taille - 1, taille - 1), radius=round(taille * 0.2237), fill=255
    )
    tuile.putalpha(masque)
    image = Image.new("RGBA", (grand, grand), (0, 0, 0, 0))
    image.paste(tuile, (marge, marge))
    return image.resize((cote, cote), Image.LANCZOS)


def dessiner(rendu: int, apparence: str = "claire",
             variante: str = VARIANTE_PAR_DEFAUT) -> Image.Image:
    """Rend l'icône complète au côté demandé, pour l'apparence demandée.

    Le sifflet arrondi est le dessin retenu ; les autres sont des explorations :

      - `arrondi`          le sifflet minimaliste au corps rond ;
      - `actuelle`         la baleine et son harnais de tête (la bride) ;
      - `baleine-sifflet`  la baleine, la bride remplacée par un sifflet ;
      - `sifflet`          le sifflet à pois seul, sans la baleine ;
      - `ultrason`         le sifflet à ultrasons seul (silent whistle) ;
      - `ultrason-ondes`   le même, avec ses ondes ;
      - `court`            le sifflet court seul (bec horizontal, sans anneau) ;
      - `baleine-court`    la baleine, avec le sifflet court sur le ventre.
    """
    if variante == "arrondi":
        return dessiner_sifflet_arrondi(rendu, apparence)
    if variante in ("sifflet", "ultrason", "ultrason-ondes", "court"):
        if variante == "sifflet":
            return dessiner_sifflet_seul(rendu, apparence)
        if variante == "court":
            return dessiner_sifflet_court_seul(rendu, apparence)
        return dessiner_ultrason_seul(rendu, apparence, ondes=variante == "ultrason-ondes")
    if variante not in ("actuelle", "baleine-sifflet", "baleine-court"):
        raise ValueError(f"variante inconnue : {variante}")

    # Suréchantillonnage : on dessine 4× plus grand puis on réduit. C'est ce qui
    # donne des bords lisses sans dépendre d'un moteur vectoriel.
    facteur = 4
    grand = rendu * facteur

    reglages = APPARENCES[apparence]
    fond = fond_degrade(apparence, grand)

    masque = masque_logo(grand)
    logo = Image.new("RGBA", (grand, grand), tuple(reglages["logo"]))
    fond.paste(logo, (0, 0), masque)

    if variante == "baleine-sifflet":
        dessiner_cordon_sifflet(fond, grand, reglages, masque)
        return fond.resize((rendu, rendu), Image.LANCZOS)

    if variante == "baleine-court":
        dessiner_baleine_sifflet_court(fond, grand, reglages)
        return fond.resize((rendu, rendu), Image.LANCZOS)

    # LE HARNAIS EST DÉCOUPÉ SUR LA SILHOUETTE, ET C'EST INDISPENSABLE.
    # Tracé librement, il dépassait du dos et du museau : des sangles qui
    # flottent dans le vide ne se lisent pas comme du harnais PORTÉ, mais comme
    # un objet posé à côté de l'animal — constaté sur capture. On le rend donc
    # sur un calque, que l'on découpe avec le masque du corps avant de le
    # composer. Les sangles s'arrêtent ainsi exactement au contour.
    calque = Image.new("RGBA", (grand, grand), (0, 0, 0, 0))
    dessiner_harnais(ImageDraw.Draw(calque), grand,
                     sangle=tuple(reglages["sangle"]), couleur_cerne=tuple(reglages["cerne"]))
    fond.paste(calque, (0, 0), Image.composite(
        calque.getchannel("A"), Image.new("L", (grand, grand), 0), masque))

    return fond.resize((rendu, rendu), Image.LANCZOS)


def dessiner_cordon_sifflet(fond, grand: int, reglages: dict, masque) -> None:
    """Pose le cordon et le sifflet sur la baleine déjà rendue.

    LE CORDON N'EST PAS DÉCOUPÉ SUR LA SILHOUETTE, contrairement au harnais, et
    c'est la différence de nature entre les deux : une bride est PORTÉE, elle
    s'arrête donc au contour ; un cordon pend DANS LE VIDE, et le découper le
    ferait disparaître dès qu'il quitte le corps. Il part donc d'un point
    franchement à l'intérieur du crâne — (9,2 ; 2,2), mesuré sur le relevé des
    bandes — pour ne jamais dépasser du dos.
    """
    largeur, hauteur = FISH_LOGO_VIEWBOX
    echelle = (grand * (1 - 2 * MARGE)) / max(largeur, hauteur)
    decalage_x = (grand - largeur * echelle) / 2
    decalage_y = (grand - hauteur * echelle) / 2

    def point(p):
        return (decalage_x + p[0] * echelle, decalage_y + p[1] * echelle)

    epaisseur = max(2, round(EPISSEUR_SANGLE * largeur * echelle))
    epaisseur_cerne = max(1, round(epaisseur * 0.34))

    # UN SEUL CALQUE pour le cordon et le sifflet : c'est ce qui permet à la
    # fenêtre d'être CREUSÉE sans percer le fond, et au sifflet de passer DEVANT
    # le cordon — sinon le cordon traverse l'anneau, qui se lit comme une boucle
    # fermée au lieu d'un trou où l'on passe une lanière.
    calque = Image.new("RGBA", (grand, grand), (0, 0, 0, 0))
    tracer_bande(
        ImageDraw.Draw(calque),
        [point(p) for p in CORDON],
        epaisseur,
        tuple(reglages["sangle"]),
        tuple(reglages["cerne"]),
        epaisseur_cerne,
    )
    poser_sifflet(
        calque, grand, point(SIFFLET_CENTRE), SIFFLET_RAYON * echelle, SIFFLET_ANGLE,
        tuple(reglages["sangle"]),
        couleur_cerne=tuple(reglages["cerne"]),
        epaisseur_cerne=epaisseur_cerne,
    )
    fond.paste(calque, (0, 0), calque)


VARIANTES = {
    "arrondi": "sifflet arrondi (dessin retenu)",
    "actuelle": "baleine + bride (ancienne icône)",
    "baleine-sifflet": "baleine + sifflet à pois",
    "sifflet": "sifflet à pois seul",
    "ultrason": "sifflet à ultrasons seul",
    "ultrason-ondes": "sifflet à ultrasons + ondes",
    "court": "sifflet court seul (bec horizontal, sans anneau)",
    "baleine-court": "baleine + sifflet court",
}


def vignette(source, taille: int, fond_local, fond_icone=None) -> Image.Image:
    """Réduit une icône à sa taille d'usage, arrondie comme iOS.

    C'est à CETTE échelle qu'une icône se juge, et la forme compte : une
    vignette carrée laisserait passer un dessin qui ne tient pas dans le carré
    arrondi réel.
    """
    pave = Image.new("RGB", (taille, taille), fond_local)
    reduite = Image.new("RGBA", (taille, taille), (*(fond_icone or fond_local), 255))
    reduite.alpha_composite(source.resize((taille, taille), Image.LANCZOS).convert("RGBA"))
    masque = Image.new("L", (taille, taille), 0)
    ImageDraw.Draw(masque).rounded_rectangle(
        [0, 0, taille - 1, taille - 1], radius=round(taille * 0.2237), fill=255
    )
    reduite.putalpha(masque)
    pave.paste(reduite, (0, 0), reduite)
    return pave


def planche_comparaison(racine: pathlib.Path) -> pathlib.Path:
    """Met les variantes côte à côte, à leurs tailles d'usage.

    POURQUOI CETTE PLANCHE EXISTE. Comparer trois PNG de 1024 px, c'est choisir
    à l'aveugle : à 1024 px, TOUT se lit. C'est à 40 px que les variantes se
    séparent, et c'est à 40 px qu'une planche doit les montrer. Chaque variante
    est donc rendue à 180, 120, 60 et 40 px sur fond clair, puis sur fond
    sombre — parce qu'une icône qui tient sur l'un peut disparaître sur l'autre.
    """
    clairs = {nom: dessiner(1024, "claire", nom) for nom in VARIANTES}
    sombres = {nom: dessiner(1024, "sombre", nom) for nom in VARIANTES}

    planche = Image.new("RGB", (880, 96 + 260 * len(VARIANTES)), (245, 245, 247))
    pinceau = ImageDraw.Draw(planche)
    pinceau.text((30, 28), "tailles d'usage, fond clair", fill=(90, 90, 100))
    pinceau.text((560, 28), "fond sombre", fill=(90, 90, 100))

    ligne = 76
    for nom, libelle in VARIANTES.items():
        pinceau.text((30, ligne - 22), libelle, fill=(20, 20, 25))
        x = 30
        for taille in (180, 120, 60, 40):
            planche.paste(vignette(clairs[nom], taille, (245, 245, 247)),
                          (x, ligne + (180 - taille) // 2))
            x += taille + 26
        x = 560
        for taille in (120, 60, 40):
            planche.paste(vignette(sombres[nom], taille, (28, 28, 30)),
                          (x, ligne + (180 - taille) // 2))
            x += taille + 22
        ligne += 260

    chemin = racine / ".build" / "icone-comparaison.png"
    chemin.parent.mkdir(parents=True, exist_ok=True)
    planche.save(chemin)
    return chemin


def main() -> int:
    analyseur = argparse.ArgumentParser(description="Génère l'icône de DSH Remote")
    analyseur.add_argument("--apercu", action="store_true",
                           help="écrit en plus une planche de contrôle")
    analyseur.add_argument("--sortie", default=None, help="dossier du catalogue d'assets")
    analyseur.add_argument("--icns", default=None,
                           help="écrit aussi une icône macOS (.icns) à ce chemin")
    analyseur.add_argument("--variante", choices=sorted(VARIANTES), default=VARIANTE_PAR_DEFAUT,
                           help="quelle icône écrire (défaut : arrondi)")
    analyseur.add_argument("--comparer", action="store_true",
                           help="écrit la planche des variantes sans modifier le catalogue")
    options = analyseur.parse_args()

    racine = pathlib.Path(__file__).resolve().parent.parent

    # --comparer n'écrit rien dans le catalogue : c'est un outil de décision, il
    # ne doit pas pouvoir modifier l'icône de l'application par accident.
    if options.comparer:
        print(f"[icone] planche de comparaison : {planche_comparaison(racine)}")
        return 0

    catalogue = pathlib.Path(options.sortie) if options.sortie else (
        racine / "App" / "Assets.xcassets" / "AppIcon.appiconset"
    )
    catalogue.mkdir(parents=True, exist_ok=True)

    # iOS n'exige QU'UNE image de 1024 px par apparence : le système en dérive
    # toutes les tailles. Les tailles plus petites sont tout de même écrites,
    # pour que l'icône puisse être vérifiée à sa taille d'usage (voir --apercu)
    # et réutilisée ailleurs sans repasser par ce script.
    suffixes = {"claire": "", "sombre": "-sombre", "teintee": "-teintee"}
    sources = {apparence: dessiner(1024, apparence, options.variante) for apparence in suffixes}
    maitre = sources["claire"]
    for apparence, suffixe in suffixes.items():
        image = sources[apparence]
        image.save(catalogue / f"icone-1024{suffixe}.png")

    # Les tailles intermédiaires ne vont PAS dans le catalogue : Xcode les
    # signale comme « non assignées » (avertissement de build), parce qu'iOS ne
    # lit que les images de 1024 px et dérive le reste. Elles sont donc écrites
    # à part, dans .build/, pour être regardées et réutilisées (README, aperçu)
    # sans polluer le catalogue.
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
    dossier_tailles = racine / ".build" / "icones"
    dossier_tailles.mkdir(parents=True, exist_ok=True)
    for nom, taille in tailles.items():
        for apparence, suffixe in suffixes.items():
            source = sources[apparence]
            source.resize((taille, taille), Image.LANCZOS).save(
                dossier_tailles / nom.replace(".png", f"{suffixe}.png"))

    print(f"[icone] 3 apparences (1024 px) dans {catalogue}")
    print(f"[icone] {len(tailles) * 3} tailles d'usage dans {dossier_tailles}")

    # ── L'icône macOS ────────────────────────────────────────────────────────
    #
    # POURQUOI ELLE EST ÉCRITE ICI. Le projet Xcode ne produit qu'une
    # application iOS ; l'application macOS est un exécutable SwiftPM, donc un
    # binaire NU, sans paquet ni icône — pas d'image dans le Dock, et rien pour
    # la reconnaître dans la barre des tâches. Le même dessin sert donc aux deux
    # plateformes : `iconutil` attend un dossier `.iconset` contenant des PNG
    # aux tailles imposées, que l'on dérive du maître de 1024 px.
    if options.icns:
        import subprocess
        import tempfile

        chemin_icns = pathlib.Path(options.icns)
        chemin_icns.parent.mkdir(parents=True, exist_ok=True)
        maitre_macos = dessiner_icone_macos(maitre)
        with tempfile.TemporaryDirectory() as temporaire:
            iconset = pathlib.Path(temporaire) / "DSHRemote.iconset"
            iconset.mkdir()
            # Les tailles que `iconutil` exige, avec leur variante @2x.
            for taille in (16, 32, 128, 256, 512):
                maitre_macos.resize((taille, taille), Image.LANCZOS).save(
                    iconset / f"icon_{taille}x{taille}.png")
                maitre_macos.resize((taille * 2, taille * 2), Image.LANCZOS).save(
                    iconset / f"icon_{taille}x{taille}@2x.png")
            subprocess.run(
                ["iconutil", "-c", "icns", str(iconset), "-o", str(chemin_icns)],
                check=True,
            )
        print(f"[icone] icone macOS : {chemin_icns}")

    if options.apercu:
        chemin_planche = racine / ".build" / "icone-apercu.png"
        chemin_planche.parent.mkdir(parents=True, exist_ok=True)

        # LA PLANCHE MONTRE LES TROIS APPARENCES, ET À LEUR TAILLE D'USAGE.
        # C'est à 40 px qu'une icône se juge : une planche qui ne montrerait que
        # le maître de 1024 px laisserait passer un dessin illisible là où il
        # sert vraiment.
        planche = Image.new("RGB", (900, 300 * len(APPARENCES) + 130), (245, 245, 247))
        ligne = 30
        for apparence in APPARENCES:
            source = sources[apparence]
            fond_local = (28, 28, 30) if apparence == "sombre" else (245, 245, 247)
            x = 26
            for taille in (180, 120, 60, 40):
                planche.paste(vignette(source, taille, (245, 245, 247), fond_icone=fond_local),
                              (x, ligne + (180 - taille) // 2))
                x += taille + 24
            planche.paste(vignette(source, 220, (245, 245, 247), fond_icone=fond_local),
                          (x + 10, ligne - 20))
            ligne += 300

        # En bas : le maître clair sur fond sombre, pour vérifier qu'il ne
        # disparaît dans aucun des deux.
        sombre = Image.new("RGB", (840, 100), (28, 28, 30))
        for indice, taille in enumerate((80, 60, 40)):
            sombre.paste(vignette(maitre, taille, (28, 28, 30)), (20 + indice * 100, 10))
        planche.paste(sombre, (30, ligne))
        planche.save(chemin_planche)
        print(f"[icone] planche de controle : {chemin_planche}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
