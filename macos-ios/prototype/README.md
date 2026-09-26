# Prototype d'interface iOS — à juger avant d'implémenter

Ce dossier contient une **maquette exécutable** de la nouvelle page d'accueil de
l'application iPhone. Elle ne remplace rien : `Sources/DSHRemoteKit/Vues.swift`
est inchangé, et rien de ce qui est ici n'est câblé au réseau.

---

## Ce que le prototype permet de juger

| Écran | Fichier de capture | Ce qu'il montre |
|---|---|---|
| Accueil, Tailscale absent | `captures/01-accueil-installer.png` | La carte en état « action requise » : installer |
| Accueil, tailnet connecté | `captures/02-accueil-connecte.png` | La carte en état « connecté », le carrousel, les sessions |
| Aucun Mac découvert | `captures/03-serveurs-vides.png` | Une liste vide qui dit POURQUOI et propose l'action |
| Réglages | `captures/04-reglages.png` | Ce qui n'est plus sur la page principale : adresse, jeton, filtres |

Les captures ne sont pas versionnées : elles se régénèrent avec
`Scripts/construire-prototype.sh <ecran>` puis `xcrun simctl io … screenshot`
(voir ci-dessous).

---

## Comment le lancer

### Sur le simulateur

```bash
cd macos-ios
Scripts/construire-prototype.sh [ecran] [appareil]
```

`ecran` vaut `complet` (défaut), `carte`, `sans-mac` ou `reglages`.
`appareil` est un nom de simulateur — `iPhone 17 Pro` par défaut.

Le script compile le fichier unique avec `swiftc` contre le SDK simulateur,
fabrique un paquet `.app` minimal, l'installe et le lance. Aucun projet Xcode
n'est créé, aucune signature n'est faite, rien n'est installé sur un appareil
réel.

Pour capturer :

```bash
xcrun simctl io "iPhone 17 Pro" screenshot /tmp/prototype.png
```

### Sur l'iPhone

```bash
Scripts/installer-prototype-iphone.sh [ecran] [identifiant-appareil]
```

L'identifiant d'appareil est **découvert automatiquement** quand il n'est pas
donné : c'est une donnée personnelle, et le script refuse de choisir à la place
de l'utilisateur quand plusieurs iPhone sont branchés.

Trois points à savoir :

- **Le prototype s'installe sous `org.example.DSHRemotePrototype`**, affiché
  « Prototype UI ». L'application `org.example.DSHRemote` qui fonctionne n'est
  **pas** touchée : une maquette ne doit pas pouvoir écraser l'outil qu'on
  utilise tous les jours.
- **La signature est manuelle, avec le profil de développement déjà présent**
  (`iOS Team Provisioning Profile: org.example.*`, wildcard). Aucun
  aller-retour avec le portail Apple, aucun identifiant d'application nouveau,
  et surtout : les droits sont extraits **du profil**, jamais écrits à la main.
- **L'écran se change sur l'iPhone** : un appui sur le titre fait défiler les
  quatre états. iOS ne transmet aucune variable d'environnement à une
  application lancée depuis l'écran d'accueil — sans ce sélecteur, il faudrait
  réinstaller entre chaque état. La mention « prototype · … » disparaîtra à
  l'implémentation.

---

## Décisions de conception, et ce qui les a fait changer

Chaque choix ci-dessous a été **corrigé après avoir regardé le simulateur** — pas
déduit. Le détail est aussi dans les commentaires du code, à l'endroit concerné.

### 1. La carte Tailscale

- **La carte entière est la cible, avec un chevron.** Deux autres dispositions
  ont été essayées puis écartées : un bouton pleine largeur sous la carte
  (60 points de hauteur pour redire ce que la carte venait de dire, plus aucune
  session visible), puis un bouton capsule à droite du titre (« Tailscale est
  connecté » se cassait sur deux lignes et la pastille d'état devenait
  orpheline).
- **La teinte du lien bleuit tout son contenu.** Mesuré : dans l'état « à
  installer », le titre et la description viraient au bleu du système, et la
  carte se lisait comme une phrase cliquable au lieu d'un avertissement. `Link`
  est donc employé **sans** style de bouton, chaque texte porte sa couleur, et
  la teinte ne colore plus que le chevron.
- **Le verbe de l'action est écrit dans la description.** La carte est cliquable
  en entier : sans le verbe, l'appui serait un pari sur ce qui va s'ouvrir.
- **Trois états, trois actions** : `Installer` (App Store), `Ouvrir`
  (`tailscale://`), `Vérifier` (relire la liste des serveurs).

### 2. Le carrousel des serveurs

- **Des icônes, pas des lignes.** Une liste de lignes dit « réglage » ; une
  icône dit « appareil ». Chaque vignette porte son icône de châssis, sa
  pastille d'état, et le **premier mot** du nom en dessous — la forme sous
  laquelle on reconnaît un appareil.
- **La sélection est une coche, pas un contour.** Mesuré : l'anneau de 2 points
  se confondait avec les bords de la vignette déjà colorée, et le serveur choisi
  ne se distinguait pas des autres.
- **« hôte » sous la vignette** : la seule mention qui vient de l'hôte et non du
  nom de la machine. Elle est réservée en place (`opacity(0)`) pour que les
  icônes restent alignées.
- **Défilement libre, pas paginé** : avec quatre Macs ou plus, un carrousel
  paginé cacherait la moitié des machines derrière un geste que rien n'annonce.

### 3. Le titre de la page

Mesuré : le grand titre coûtait **60 points** pour répéter le nom de
l'application, déjà connu de qui l'ouvre — et ces 60 points manquaient aux
sessions, dont deux seulement restaient visibles. Le titre est donc **en ligne**,
et une ligne de workspace supplémentaire tient à l'écran.

### 4. La recherche, en bas

Ancrée sous le pouce, dans une bande en matière, plutôt que `.searchable` dans la
barre de navigation : la recherche native se replie sous un geste de défilement,
c'est-à-dire qu'on la perd exactement quand on en a besoin. C'est aussi la place
qu'elle occupe dans l'interface web.

### 5. Ce qui a quitté la page principale

L'adresse, le jeton, le test d'adresse et les deux filtres tiennent maintenant
dans une feuille « Réglages » (icône engrenage). Ce ne sont pas des gestes
quotidiens, et ils occupaient à eux seuls plus de la moitié de la hauteur utile.

---

## Ce que ce prototype ne prouve pas

- **Rien n'est câblé.** Les données sont factices (`DonneesDemo`), les boutons
  sont inertes, et aucun appel réseau n'est fait.
- **La détection de Tailscale n'est pas implémentée.** Le prototype affiche
  l'état demandé par la variable d'environnement. La vraie détection possible
  sur iOS est `canOpenURL("tailscale://")` — et elle exige que `tailscale` soit
  déclaré dans `LSApplicationQueriesSchemes` de l'`Info.plist` de
  l'application. Le script de construction le déclare pour le prototype, mais
  l'`Info.plist` de la vraie application devra l'ajouter.
- **« Installé » et « connecté » ne se distinguent pas** depuis l'application :
  un Tailscale installé mais déconnecté ressemble à un tailnet vide. Le
  prototype montre les deux états, l'implémentation devra choisir la règle.
- **Aucun essai sur iPhone réel** : le rendu est celui du simulateur
  (iOS 26.5), pas celui de l'appareil.
