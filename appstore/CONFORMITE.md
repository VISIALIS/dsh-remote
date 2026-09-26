# Conformité aux App Store Review Guidelines — DSH Remote Companion

Audit du 26 septembre 2026, version 0.2. Chaque point renvoie à ce qui le prouve dans le dépôt.

Légende : ✅ conforme · 🔧 corrigé lors de cet audit · ⚠️ action requise hors du code · ℹ️ risque à surveiller

## 1. Sécurité (Safety)

| Guideline | État | Preuve / remarque |
|---|---|---|
| 1.1 Contenu choquant | ✅ | Aucun contenu éditorial ; l'app affiche les sessions de l'utilisateur. |
| 1.2 Contenu généré par les utilisateurs | ✅ | Pas de contenu d'autres utilisateurs : l'app lit l'agent que l'utilisateur héberge lui-même. |
| 1.6 Sécurité des données | ✅ | Jeton au trousseau ; portée lecture seule par défaut ; révocation par appareil (`SECURITY.md`). |

## 2. Performances

| Guideline | État | Preuve / remarque |
|---|---|---|
| 2.1 Complétude de l'app | ⚠️ | **Bloquant pour l'App Store.** Le réviseur n'a pas d'hôte DSH. Il faut fournir une **vidéo de démonstration** dans les notes de review (texte prêt dans `README.md`). Elle peut être tournée avec `macos-ios/Scripts/hote-demo.mjs` (données fictives). |
| 2.1 Plantages | ✅ | Suites de tests : 152 (plugin) + 365 (Swift). Vérifier aussi l'app sur un iPhone réel avant soumission. |
| 2.3.1 Métadonnées exactes | 🔧 | La fiche annonçait « token usage » : l'app ne l'affiche pas. Mention retirée (en et fr). |
| 2.3.3 Captures d'écran | ✅ | Captures de l'app réelle, données fictives : `captures/`. |
| 2.3.7 Mots-clés | ✅ | Ni « DeepSeek » ni « Tailscale » dans les mots-clés. |
| 2.3.8 Métadonnées adaptées à tous | ✅ | Classification 4+. |
| 2.5.1 API publiques uniquement | ✅ | Le `@_silgen_name` de `Widgets/main.swift` ne sert qu'au paquet macOS manuel ; il n'est pas compilé dans les cibles Xcode. |
| 2.5.2 Pas de code téléchargé | ✅ | Aucun code exécuté à distance. |
| 2.5.4 Modes d'arrière-plan | ✅ | Aucun `UIBackgroundModes` ; l'écran reste allumé seulement au premier plan (`AppDSHRemoteIOS.swift`). |
| 2.5.6 / Debug | 🔧 | Les ancres de capture (`DSH_REMOTE_JETON_DEMO`, `--session=`…) : le jeton de démo est sous `#if DEBUG` — **vérifié absent du binaire Release** (`strings` : 0 occurrence). |

## 3. Business

| Guideline | État | Preuve / remarque |
|---|---|---|
| 3.1 Paiements | ✅ | Gratuit, aucun achat intégré, aucun lien vers un paiement externe. |

## 4. Design

| Guideline | État | Preuve / remarque |
|---|---|---|
| 4.0 iPad | ✅ | `TARGETED_DEVICE_FAMILY = 1,2`, quatre orientations iPad (multitâche). |
| 4.1 Copies / imitation | ✅ | Icône propre au projet, sans marque tierce. |
| 4.2 Fonctionnalité minimale | ℹ️ | App compagnon d'un logiciel installé sur un ordinateur (comme un client bureau à distance) : acceptable, mais le réviseur doit le comprendre — d'où la vidéo et les notes. |
| 4.2.3 Dépendance à une autre app | ℹ️ | DSH n'est pas une app iOS à installer ; l'app fonctionne seule face à l'hôte. À expliciter dans les notes de review. |
| Localisation | 🔧 | Trois textes restaient en français dans l'interface anglaise (résumé « en attente », bandeau « lecture seule », libellés « À propos ») : traduits via `L()`, 283 clés vérifiées par `traduire.py --verifier`. |

## 5. Légal

| Guideline | État | Preuve / remarque |
|---|---|---|
| 5.1.1(i) Politique de confidentialité | 🔧 | `PRIVACY.md` publié ; **lien ajouté dans l'app** (Réglages → À propos → Privacy Policy). |
| 5.1.1(ii) Autorisations justifiées | 🔧 | Caméra : texte existant. **Réseau local : `NSLocalNetworkUsageDescription` ajouté** (en + fr). Notifications : demandées seulement quand l'utilisateur active les alertes. |
| 5.1.1(v) Suppression de compte | ✅ | Aucun compte. |
| 5.1.2 Usage des données | ✅ | Aucune collecte ; App Privacy : « Data Not Collected ». |
| Manifeste de confidentialité | 🔧 | App : raison `1C8F.1` ajoutée (groupe d'app). **Widget : manifeste créé** (`Widgets/PrivacyInfo.xcprivacy`) et embarqué — vérifié dans le `.appex`. |
| 5.2.1 Propriété intellectuelle | ℹ️ | « DeepSeek » apparaît dans la description (usage descriptif + mention de non-affiliation), pas dans le nom ni l'icône. Si DeepSeek est une marque déposée d'un tiers, un réviseur peut demander une preuve d'autorisation ; le retirer de la description éliminerait le risque. |
| Chiffrement à l'export | ✅ | `ITSAppUsesNonExemptEncryption = false` (TLS du système uniquement). |

## Actions restantes (hors code)

1. **Tourner la vidéo de démonstration** et mettre son lien dans les notes de review — indispensable avant la soumission App Store (pas pour TestFlight interne).
2. **Tester sur un iPhone réel** la build TestFlight : appairage par QR code, Activité en direct, widgets.
3. Décider du point 5.2.1 : garder ou retirer la mention de DeepSeek dans la description.
4. Si l'app Mac doit être publiée : ajouter la plateforme macOS à l'app dans App Store Connect, et produire des captures Mac.
