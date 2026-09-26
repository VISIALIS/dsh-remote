# Fiche App Store Connect — DSH Remote Companion

Contenu prêt à copier-coller dans App Store Connect (Apple ID de l'app : voir App Store Connect).
Les textes sont dans `metadata/<langue>/` ; un fichier = un champ. Les longueurs respectent les limites d'Apple.

| Champ App Store Connect | Fichier | Limite |
|---|---|---|
| Nom | `name.txt` | 30 |
| Sous-titre | `subtitle.txt` | 30 |
| Texte promotionnel | `promotional_text.txt` | 170 |
| Description | `description.txt` | 4000 |
| Mots-clés | `keywords.txt` | 100 |
| Nouveautés de cette version | `release_notes.txt` | 4000 |

Langue principale : **anglais (en-US)**, localisation **français (fr-FR)** — comme l'app.

Vérifier les longueurs après modification :

```bash
for d in appstore/metadata/*/; do for f in name:30 subtitle:30 promotional_text:170 keywords:100 description:4000; do
  n=${f%%:*}; m=${f#*:}; c=$(python3 -c "print(len(open('$d$n.txt',encoding='utf-8').read()))")
  [ "$c" -gt "$m" ] && echo "TROP LONG: $d$n ($c/$m)"; done; done
```

---

## Informations générales

| Champ | Valeur |
|---|---|
| Catégorie principale | Developer Tools (Outils de développement) |
| Catégorie secondaire | Productivity (Productivité) |
| URL d'assistance | https://github.com/VISIALIS/dsh-remote/issues |
| URL marketing (facultatif) | https://github.com/VISIALIS/dsh-remote |
| URL de politique de confidentialité | https://github.com/VISIALIS/dsh-remote/blob/main/PRIVACY.md |
| Copyright | `2026 <titulaire du compte développeur>` — à compléter dans App Store Connect |
| Prix | Gratuit |

> Les URL GitHub ne fonctionnent qu'une fois `PRIVACY.md` poussé sur `main`.

---

## Confidentialité de l'app (App Privacy)

Réponse : **« Données non collectées » (Data Not Collected)**.

Justification, vérifiable dans le code :
- aucun SDK tiers, aucune statistique, aucun pistage (`PrivacyInfo.xcprivacy` : `NSPrivacyTracking = false`, aucune donnée collectée) ;
- l'app ne se connecte qu'à l'hôte DSH de l'utilisateur ; le développeur ne reçoit rien ;
- notifications locales uniquement (`UNUserNotificationCenter`), pas de push.

Apple considère qu'une donnée est « collectée » seulement si elle quitte l'appareil vers le développeur ou un tiers — ce qui n'est jamais le cas ici.

---

## Classification par âge

Répondre **« Aucun / None »** à toutes les catégories de contenu. Points d'attention :
- **Accès web non restreint** : Non (l'app n'ouvre pas de navigateur libre).
- **Contenu généré par les utilisateurs / fonctions d'IA** : l'app affiche la sortie d'un agent IA que l'utilisateur **héberge et pilote lui-même** ; elle ne propose ni chat public, ni contenu d'autres utilisateurs. Si le questionnaire demande si l'app intègre un assistant IA, répondre selon ce fait : l'app est un client de supervision, le modèle ne tourne pas dans l'app.

Résultat attendu : **4+**.

---

## Conformité à l'export (chiffrement)

Déjà déclaré dans les `Info.plist` : `ITSAppUsesNonExemptEncryption = false` (HTTPS/TLS système uniquement). Aucune question ne devrait être posée à chaque build.

---

## TestFlight

- **Description de la bêta** : reprendre le premier paragraphe de `description.txt`.
- **À tester (What to Test)** : reprendre `release_notes.txt`.
- **Adresse e-mail de retour** : obligatoire pour les testeurs externes.
- Les testeurs **internes** n'ont pas besoin de la revue bêta ; les testeurs **externes** déclenchent une revue Apple (voir ci-dessous).

---

## Notes pour l'App Review — POINT BLOQUANT

L'app ne fonctionne qu'avec un hôte DSH appairé. Sans lui, un réviseur ne voit qu'un écran d'appairage et rejettera l'app (guideline 2.1, « App Completeness », faute de pouvoir la tester).

Il faut fournir **au moins l'un des deux** :
1. **Une vidéo de démonstration** (lien non listé) montrant l'appairage par QR code, une session suivie en direct, les widgets et l'Activité en direct — c'est la voie la plus simple ;
2. **Un hôte de démonstration** joignable par les réviseurs, avec un code d'appairage durable — à éviter : cela exposerait un hôte sur Internet, contraire à la RÈGLE #0.

Texte proposé pour le champ « Notes » (en anglais) :

```text
DSH Remote Companion is a companion app for DeepSeek Harness (DSH), a self-hosted
AI agent harness that runs on the user's own computer. The app connects only to
that computer, over the local network or a private Tailscale network, after
pairing with a one-time QR code shown in the DSH web panel.

Because the host runs on the user's own machine, we cannot provide a public
server or demo account. A full demonstration video is available here: <LIEN VIDEO>
It shows pairing, live session monitoring, widgets and the Live Activity.

The app collects no data, has no account and uses no third-party service.
The camera is used only to scan the pairing QR code.
Host plugin (open source, MIT): https://github.com/VISIALIS/dsh-remote
```

---

## Captures d'écran à produire

Tailles obligatoires (App Store Connect les redimensionne pour les appareils plus petits) :

| Plateforme | Taille | Obligatoire |
|---|---|---|
| iPhone 6,9" | 1320 × 2868 (portrait) | Oui |
| iPad 13" | 2064 × 2752 (portrait) | Oui — l'app cible aussi l'iPad |
| Mac | 2880 × 1800 (ou 1280 × 800) | Seulement si la plateforme macOS est ajoutée à l'app |

Écrans suggérés (3 à 5) : liste des sessions, détail d'une session avec appels d'outils, appairage par QR code, widgets / Activité en direct, réglages de confidentialité.

Les captures doivent montrer des **données fictives** (RÈGLE #0 : aucun nom de machine, tailnet ou chemin réel). Le faux hôte des tests (`macos-ios/Tests/DSHRemoteKitTests/Outils/serveur-modele-essai.mjs`) peut servir de source de données dans le simulateur.

---

## Marques

- « DeepSeek » n'apparaît ni dans le nom, ni dans les mots-clés (guideline 2.3.7 : pas de marques de tiers dans les mots-clés).
- La description le mentionne de façon factuelle, avec la mention de non-affiliation.
- « Tailscale » est cité dans la description comme moyen de connexion, pas dans les mots-clés.
