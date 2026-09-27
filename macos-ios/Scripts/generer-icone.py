#!/usr/bin/env python3
"""Génère l'icône de l'application « DSH Remote ».

Le dessin est un sifflet arrondi : un corps rond, un bec et une encoche, en
bleu, sur fond clair. Son contour est décrit dans `SIFFLET_ARRONDI_PATH` — un
dessin propre au projet, sans aucun élément de marque tiers.

POURQUOI UN GÉNÉRATEUR ET NON UN PNG POSÉ LÀ. Une icône produite par un outil
graphique n'est pas reproductible : personne ne peut la corriger sans rouvrir
l'outil. Ici, tout est DÉCRIT — le tracé, les couleurs, les proportions — et le
script produit les PNG aux tailles exigées par iOS et macOS.

POURQUOI PILLOW ET PAS UN CONVERTISSEUR SVG. Mesuré sur cette machine :
`rsvg-convert`, `inkscape`, `magick` et `cairosvg` sont absents, `Pillow` est
présent. Le script n'ajoute donc AUCUNE dépendance au dépôt : il lit le tracé
SVG lui-même, et remplit les polygones avec Pillow.

Usage :
    Scripts/generer-icone.py [--apercu]
    Scripts/generer-icone.py --icns-seul --icns CHEMIN.icns   # ne touche PAS au catalogue

`--apercu` écrit en plus une planche de contrôle dans .build/icone-apercu.png,
qui montre l'icône aux tailles réelles d'affichage (180, 120, 60, 40 px) : c'est
à 40 px qu'une icône se juge, pas à 1024.

`--icns-seul` est le mode de l'EMPAQUETAGE macOS : il écrit le `.icns` demandé et
RIEN d'autre. Le catalogue iOS (`App/Assets.xcassets/AppIcon.appiconset`) est un
artefact de l'icône, pas de la compilation du Mac : le réécrire à chaque
empaquetage salissait trois fichiers versionnés pour des différences d'encodage
que personne ne peut juger (mesuré le 18 septembre 2026 — et 42 pixels
d'anti-aliasing sur un million pour la variante sombre). Le catalogue se régénère
donc EXPLICITEMENT, quand l'icône change : sans `--icns-seul`, ou avec `--sortie`.

UN SEUL INTERPRÉTEUR PORTE PILLOW SUR CETTE MACHINE : `/usr/bin/python3`
(3.9.6, Pillow 11.1.0). Celui du PATH (`/opt/homebrew/bin/python3`) ne l'a pas.
C'est l'environnement de référence des PNG commités :

    PATH="/usr/bin:$PATH" python3 Scripts/generer-icone.py
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

# ── Palette et tracé ──────────────────────────────────────────────────────────
BLEU = (77, 107, 254)  # #4D6BFE
BLANC = (255, 255, 255)

# LES TROIS APPARENCES. Depuis iOS 18, l'écran d'accueil peut teinter les icônes
# (mode sombre, mode teinté), et Xcode attend alors un jeu de trois images.
APPARENCES = ("claire", "sombre", "teintee")

# Corps rond en bas à gauche, bec montant à droite et encoche ouverte. Un seul
# contour, sans détail ajouté.
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

    Seules les commandes employées par le tracé sont traitées : `M`, `m`, `C`,
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


def dessiner_sifflet_arrondi(rendu: int, apparence: str = "claire") -> Image.Image:
    """Rend l'icône au côté demandé, avec les mêmes proportions dans les trois modes."""
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
        couleur = BLEU
    elif apparence == "sombre":
        # Le système fournit le fond sombre ; le bleu du signe reste inchangé.
        fond = Image.new("RGBA", (grand, grand), (0, 0, 0, 0))
        couleur = (*BLEU, 255)
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


def main() -> int:
    analyseur = argparse.ArgumentParser(description="Génère l'icône de DSH Remote")
    analyseur.add_argument("--apercu", action="store_true",
                           help="écrit en plus une planche de contrôle")
    analyseur.add_argument("--sortie", default=None, help="dossier du catalogue d'assets")
    analyseur.add_argument("--icns", default=None,
                           help="écrit aussi une icône macOS (.icns) à ce chemin")
    analyseur.add_argument("--icns-seul", action="store_true",
                           help="n'écrit QUE le fichier .icns demandé : ne touche PAS au "
                                "catalogue iOS (pour l'empaquetage macOS)")
    options = analyseur.parse_args()

    racine = pathlib.Path(__file__).resolve().parent.parent

    # ── POURQUOI `--icns-seul` EXISTE, ET CE QU'IL A RÉPARÉ ──────────────────
    #
    # MESURÉ LE 18 SEPTEMBRE 2026. `empaqueter-app-macos.sh` appelle ce script pour
    # obtenir un `.icns` — et le script, lui, réécrivait AUSSI les trois PNG de
    # 1024 px du catalogue iOS, qui appartiennent à Xcode. Conséquence : chaque
    # empaquetage macOS salissait trois fichiers VERSIONNÉS, avec un diff que
    # personne ne peut juger (encodage de Pillow, et 42 pixels d'anti-aliasing sur
    # un million pour la variante sombre). Un diff qu'on ne peut pas juger est un
    # diff qu'on apprend à ignorer — et le jour où l'icône change vraiment, on ne
    # le voit plus.
    #
    # Le catalogue iOS est donc un ACTE EXPLICITE : on le régénère quand on change
    # l'icône, pas à chaque compilation du Mac. Les images sont tout de même
    # dessinées ici (elles servent à `--apercu` et à l'ICNS) ; seul leur ENREGISTREMENT
    # dans le catalogue est sauté.
    catalogue = pathlib.Path(options.sortie) if options.sortie else (
        racine / "App" / "Assets.xcassets" / "AppIcon.appiconset"
    )
    # Le catalogue s'écrit s'il est explicitement demandé (`--sortie`), ou si l'on
    # n'a pas dit qu'on ne voulait QUE l'ICNS.
    ecrire_catalogue = options.sortie is not None or not options.icns_seul

    # iOS n'exige QU'UNE image de 1024 px par apparence : le système en dérive
    # toutes les tailles. Les tailles plus petites sont tout de même écrites,
    # pour que l'icône puisse être vérifiée à sa taille d'usage (voir --apercu)
    # et réutilisée ailleurs sans repasser par ce script.
    suffixes = {"claire": "", "sombre": "-sombre", "teintee": "-teintee"}
    sources = {apparence: dessiner_sifflet_arrondi(1024, apparence) for apparence in suffixes}
    maitre = sources["claire"]

    # Les tailles intermédiaires ne vont PAS dans le catalogue : Xcode les
    # signale comme « non assignées » (avertissement de build), parce qu'iOS ne
    # lit que les images de 1024 px et dérive le reste. Elles sont donc écrites
    # à part, dans .build/, pour être regardées et réutilisées (README, aperçu)
    # sans polluer le catalogue.
    #
    # ELLES SUIVENT LE MÊME SORT QUE LE CATALOGUE : ce sont des artefacts de
    # l'icône, pas de la compilation macOS.
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

    if ecrire_catalogue:
        catalogue.mkdir(parents=True, exist_ok=True)
        for apparence, suffixe in suffixes.items():
            image = sources[apparence]
            image.save(catalogue / f"icone-1024{suffixe}.png")

        dossier_tailles = racine / ".build" / "icones"
        dossier_tailles.mkdir(parents=True, exist_ok=True)
        for nom, taille in tailles.items():
            for apparence, suffixe in suffixes.items():
                source = sources[apparence]
                source.resize((taille, taille), Image.LANCZOS).save(
                    dossier_tailles / nom.replace(".png", f"{suffixe}.png"))

        print(f"[icone] 3 apparences (1024 px) dans {catalogue}")
        print(f"[icone] {len(tailles) * 3} tailles d'usage dans {dossier_tailles}")
    else:
        print("[icone] catalogue iOS NON modifie (--icns-seul) : seules les images demandees sont ecrites")

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
