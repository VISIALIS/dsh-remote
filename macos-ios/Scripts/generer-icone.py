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
    },
    "sombre": {
        # Fond bleu profond, baleine au bleu de la marque : lisible sur un fond
        # sombre sans devenir un aplat noir.
        "fond_haut": (26, 34, 62),
        "fond_bas": (12, 16, 34),
        "logo": (108, 134, 255, 255),
        "sangle": (240, 243, 255, 255),
        "cerne": (12, 16, 34, 255),
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
        """Trace une sangle : cerne clair dessous, cuir sombre dessus.

        Le cerne est ce qui détache la sangle du corps bleu ET du fond clair ;
        sans lui, la sangle se lit comme un trou dans l'animal — mesuré.
        """
        sommets = [point(p) for p in points]
        dessin.line(sommets, fill=couleur_cerne,
                    width=round(epaisseur * facteur) + 2 * epaisseur_cerne, joint="curve")
        dessin.line(sommets, fill=sangle, width=round(epaisseur * facteur), joint="curve")

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


def dessiner(rendu: int, apparence: str = "claire") -> Image.Image:
    """Rend l'icône complète au côté demandé, pour l'apparence demandée."""
    # Suréchantillonnage : on dessine 4× plus grand puis on réduit. C'est ce qui
    # donne des bords lisses sans dépendre d'un moteur vectoriel.
    facteur = 4
    grand = rendu * facteur

    reglages = APPARENCES[apparence]

    # Fond : dégradé vertical très doux, pour que l'icône ne soit pas un aplat.
    # En mode teinté, il est TRANSPARENT : iOS n'utilise alors que la forme.
    if len(reglages["fond_haut"]) == 4:
        fond = Image.new("RGBA", (grand, grand), (0, 0, 0, 0))
    else:
        fond = Image.new("RGB", (grand, grand), reglages["fond_bas"])
    pinceau = ImageDraw.Draw(fond)
    for ligne in range(grand):
        t = ligne / max(1, grand - 1)
        haut, bas = reglages["fond_haut"], reglages["fond_bas"]
        couleur = tuple(round(haut[i] + (bas[i] - haut[i]) * t) for i in range(len(haut)))
        pinceau.line([(0, ligne), (grand, ligne)], fill=couleur)

    masque = masque_logo(grand)
    logo = Image.new("RGBA", (grand, grand), tuple(reglages["logo"]))
    fond.paste(logo, (0, 0), masque)

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


def main() -> int:
    analyseur = argparse.ArgumentParser(description="Génère l'icône de DSH Remote")
    analyseur.add_argument("--apercu", action="store_true",
                           help="écrit en plus une planche de contrôle")
    analyseur.add_argument("--sortie", default=None, help="dossier du catalogue d'assets")
    analyseur.add_argument("--icns", default=None,
                           help="écrit aussi une icône macOS (.icns) à ce chemin")
    options = analyseur.parse_args()

    racine = pathlib.Path(__file__).resolve().parent.parent
    catalogue = pathlib.Path(options.sortie) if options.sortie else (
        racine / "App" / "Assets.xcassets" / "AppIcon.appiconset"
    )
    catalogue.mkdir(parents=True, exist_ok=True)

    # iOS n'exige QU'UNE image de 1024 px par apparence : le système en dérive
    # toutes les tailles. Les tailles plus petites sont tout de même écrites,
    # pour que l'icône puisse être vérifiée à sa taille d'usage (voir --apercu)
    # et réutilisée ailleurs sans repasser par ce script.
    suffixes = {"claire": "", "sombre": "-sombre", "teintee": "-teintee"}
    maitre = dessiner(1024, "claire")
    for apparence, suffixe in suffixes.items():
        image = maitre if apparence == "claire" else dessiner(1024, apparence)
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
            source = maitre if apparence == "claire" else dessiner(1024, apparence)
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
        with tempfile.TemporaryDirectory() as temporaire:
            iconset = pathlib.Path(temporaire) / "DSHRemote.iconset"
            iconset.mkdir()
            # Les tailles que `iconutil` exige, avec leur variante @2x.
            for taille in (16, 32, 128, 256, 512):
                maitre.resize((taille, taille), Image.LANCZOS).save(
                    iconset / f"icon_{taille}x{taille}.png")
                maitre.resize((taille * 2, taille * 2), Image.LANCZOS).save(
                    iconset / f"icon_{taille}x{taille}@2x.png")
            subprocess.run(
                ["iconutil", "-c", "icns", str(iconset), "-o", str(chemin_icns)],
                check=True,
            )
        print(f"[icone] icone macOS : {chemin_icns}")

    if options.apercu:
        chemin_planche = racine / ".build" / "icone-apercu.png"
        chemin_planche.parent.mkdir(parents=True, exist_ok=True)

        def vignette(source, taille, fond_local):
            """Arrondit comme iOS, pour juger à la forme réelle."""
            pave = Image.new("RGB", (taille, taille), fond_local)
            reduite = source.resize((taille, taille), Image.LANCZOS).convert("RGBA")
            masque = Image.new("L", (taille, taille), 0)
            ImageDraw.Draw(masque).rounded_rectangle(
                [0, 0, taille - 1, taille - 1], radius=round(taille * 0.2237), fill=255
            )
            reduite.putalpha(masque)
            pave.paste(reduite, (0, 0), reduite)
            return pave

        # LA PLANCHE MONTRE LES TROIS APPARENCES, ET À LEUR TAILLE D'USAGE.
        # C'est à 40 px qu'une icône se juge : une planche qui ne montrerait que
        # le maître de 1024 px laisserait passer un dessin illisible là où il
        # sert vraiment.
        planche = Image.new("RGB", (900, 300 * len(APPARENCES) + 130), (245, 245, 247))
        ligne = 30
        for apparence in APPARENCES:
            source = maitre if apparence == "claire" else dessiner(1024, apparence)
            fond_local = (28, 28, 30) if apparence == "sombre" else (245, 245, 247)
            x = 26
            for taille in (180, 120, 60, 40):
                planche.paste(vignette(source, taille, fond_local), (x, ligne + (180 - taille) // 2))
                x += taille + 24
            planche.paste(vignette(source, 220, fond_local), (x + 10, ligne - 20))
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
