#!/usr/bin/env python3
"""Relève l'espace libre autour de la silhouette de la baleine.

POURQUOI CET OUTIL EXISTE. Les pièces du harnais — puis celles du sifflet — sont
posées en coordonnées du LOGO (le repère 23,16 × 17,04 du tracé DeepSeek), et
ces coordonnées ne sont pas devinées : elles sont MESURÉES. Sans cet outil, la
phrase « les valeurs sont relevées, pas estimées » serait invérifiable, et la
prochaine retouche se ferait de nouveau à l'œil.

Ce que l'outil produit :

  1. une image `.build/silhouette-grillee.png` — la baleine sur une grille
     graduée dans le repère du logo (x en rouge, y en vert), pour lire une
     position d'un coup d'œil ;
  2. sur la sortie standard, le relevé CHIFFRÉ des bandes occupées colonne par
     colonne. C'est ce relevé qui dit où le corps est continu, où il se sépare
     de la queue, et où il reste du vide.

Usage :
    Scripts/mesurer-silhouette.py [--cote 1200]

L'outil IMPORTE `generer-icone.py` plutôt que de recopier le tracé : une seule
vérité sur la silhouette, et le relevé suit automatiquement toute correction du
logo.
"""

from __future__ import annotations

import argparse
import importlib.util
import pathlib

from PIL import Image, ImageDraw

RACINE = pathlib.Path(__file__).resolve().parent.parent


def charger_generateur():
    """Importe `generer-icone.py`, dont le nom interdit un `import` ordinaire.

    Le tiret du nom de fichier est imposé par la convention des scripts du
    dépôt (`construire-app-ios.sh`, `empaqueter-app-macos.sh`) : on passe donc
    par `importlib` au lieu de renommer le générateur.
    """
    chemin = RACINE / "Scripts" / "generer-icone.py"
    specification = importlib.util.spec_from_file_location("generer_icone", chemin)
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


def main() -> int:
    analyseur = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    analyseur.add_argument("--cote", type=int, default=1200,
                           help="côté du rendu de contrôle (défaut : 1200)")
    options = analyseur.parse_args()

    generateur = charger_generateur()
    cote = options.cote
    masque = generateur.masque_logo(cote)

    largeur, hauteur = generateur.FISH_LOGO_VIEWBOX
    echelle = (cote * (1 - 2 * generateur.MARGE)) / max(largeur, hauteur)
    decalage_x = (cote - largeur * echelle) / 2
    decalage_y = (cote - hauteur * echelle) / 2

    image = Image.new("RGB", (cote, cote), (255, 255, 255))
    image.paste(Image.new("RGB", (cote, cote), generateur.BLEU_LOGO), (0, 0), masque)

    pinceau = ImageDraw.Draw(image)
    # La grille est graduée EN UNITÉS DU LOGO, pas en pixels : c'est le seul
    # repère dans lequel les constantes du générateur ont un sens.
    for i in range(0, int(largeur) + 1):
        x = decalage_x + i * echelle
        if 0 <= x < cote:
            pinceau.line([(x, 0), (x, cote)], fill=(255, 0, 0), width=1)
            pinceau.text((x + 3, 6), str(i), fill=(190, 0, 0))
    for j in range(0, int(hauteur) + 1):
        y = decalage_y + j * echelle
        if 0 <= y < cote:
            pinceau.line([(0, y), (cote, y)], fill=(0, 150, 0), width=1)
            pinceau.text((6, y + 3), str(j), fill=(0, 110, 0))

    chemin = RACINE / ".build" / "silhouette-grillee.png"
    chemin.parent.mkdir(parents=True, exist_ok=True)
    image.save(chemin)
    print(f"[mesure] {chemin}")
    print("[mesure] 1 carreau = 1 unite du logo ; x en rouge, y en vert\n")

    # LE RELEVÉ CHIFFRÉ EST LA PARTIE QUI SERT. Une image se lit à l'œil et
    # laisse passer un chevauchement de deux dixièmes ; ces bandes-là, non.
    print("colonnes (x) : bandes occupees (y), en unites du logo")
    for i in range(0, int(largeur)):
        colonne = [
            masque.getpixel((min(cote - 1, max(0, round(decalage_x + (i + 0.5) * echelle))), y))
            for y in range(cote)
        ]
        bandes = []
        debut = None
        for y, valeur in enumerate(colonne):
            if valeur > 8 and debut is None:
                debut = y
            elif valeur <= 8 and debut is not None:
                bandes.append((debut, y))
                debut = None
        if debut is not None:
            bandes.append((debut, cote))

        lisibles = ", ".join(
            f"{max(0.0, (a - decalage_y) / echelle):.1f}->{min(hauteur, (b - decalage_y) / echelle):.1f}"
            for a, b in bandes if (b - a) > 12
        )
        vide = sum(b - a for a, b in bandes) / cote
        print(f"  x = {i + 0.5:5.1f}  occupe {vide * 100:5.1f}%   {lisibles}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
