# Guide de Déploiement et CI/CD — DSH Remote

Ce document définit les règles de versionnement, la convention de tags Git et les procédures de suivi pour les builds **Xcode Cloud** (iOS & macOS).

---

## 1. Convention des Tags Git (CRITIQUE)

Dans **Xcode Cloud**, le déclencheur de build automatique (*Start Conditions > Tag Changes*) filtre sur les **préfixes de nom de tag**.

> [!CAUTION]
> **Règle absolue :** Respecter rigoureusement les préfixes ci-dessous. Un tag mal préfixé ne déclenchera **aucun build** dans Xcode Cloud.

| Environnement | Workflow Xcode Cloud | Préfixe requis | Exemple valide | Exemple INTERDIT |
| :--- | :--- | :--- | :--- | :--- |
| **Bêta / TestFlight** | `Internal TestFlight Build` | `beta-` ou `test-` | `beta-0.1.0`, `beta-0.1.0.1` | `v0.1.0-beta.1` ❌ |
| **Production** | `App Store Release` | `v` | `v1.0.0`, `v1.1.0` | `1.0.0` ❌ |

---

## 2. Configuration du Workflow Xcode Cloud (`Internal TestFlight Build`)

Dans Xcode (**Integrate > Manage Workflows > Internal TestFlight Build**) :

### Actions principales
1. **Archive - iOS** :
   - *Scheme* : `DSHRemote`
   - *Platform* : `iOS`
   - *Deployment Type* : `TestFlight (Internal Testing Only)`
2. **Archive - macOS** :
   - *Scheme* : `DSHRemote-macOS`
   - *Platform* : `macOS`
   - *Deployment Type* : `TestFlight (Internal Testing Only)`

### Post-Actions
- ✅ **TestFlight (Internal Testing Only)** :
  - Ajouter cette post-action et sélectionner le groupe de testeurs internes.
  - Dès validation par Apple, les versions iOS et macOS sont déployées automatiquement.
- ❌ **Notarize - macOS** :
  - **Ne JAMAIS ajouter cette post-action dans un workflow TestFlight.**
  - La notarisation Apple sert uniquement à la distribution directe hors Mac App Store (Developer ID). L'activer sur une archive TestFlight crée un conflit d'export et bloque la préparation du build.

### Exigences du code (déjà intégrées dans le projet)
- `<key>ITSAppUsesNonExemptEncryption</key><false/>` dans `App/Info.plist`, `App/Info-macOS.plist` et `Widgets/Info.plist` (évite le blocage automatique de conformité export à l'ingestion App Store Connect).
- `MARKETING_VERSION` et `CURRENT_PROJECT_VERSION` synchronisés sur iOS et macOS.

---

## 3. Procédure pour lancer une Bêta (TestFlight)

1. **Vérifier l'arbre de travail localement :**
   ```bash
   bash scripts/verifier.sh
   ```
   *Doit retourner `exit 0` (tests Swift, bundle Node et secrets conformes).*

2. **Commiter et pousser vos modifications :**
   ```bash
   git push origin main
   ```

3. **Créer et pousser le tag de test :**
   ```bash
   # Choisir le numéro incrémental (ex: beta-0.1.3)
   git tag beta-0.1.3
   git push origin beta-0.1.3
   ```

4. **Si un tag précédent a échoué et doit être nettoyé :**
   ```bash
   # Supprimer le tag distant et local
   git push origin --delete beta-0.1.2
   git tag -d beta-0.1.2
   ```

---

## 4. Procédure pour la Production (App Store)

1. Après validation de la bêta par les testeurs :
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```
2. Le workflow de production s'exécute et déploie le binaire éligible pour soumission finale dans App Store Connect.

---

## 5. Comment suivre l'avancement des builds

### Option A — En ligne de commande (Instantané)
Xcode synchronise l'état de tous les builds dans son cache Core Data local. Vous pouvez interroger la base SQLite directement :

```bash
sqlite3 ~/Library/Developer/Xcode/UserData/XcodeCloud/XcodeCloudCoreDataModel-v12.sqlite \
  "SELECT ZNUMBER, ZRAWLIFECYCLE, ZRAWOUTCOME, ZCOMMITSHA, datetime(ZCREATEDDATE + 978307200, 'unixepoch', 'localtime') as date 
   FROM ZBUILDENTITY 
   ORDER BY ZCREATEDDATE DESC LIMIT 5;"
```
- `ZRAWLIFECYCLE` : `running` (en cours), `finished` (terminé).
- `ZRAWOUTCOME` : `success` (vert ✅), `failure` (rouge ❌).

### Option B — Dans l'interface Xcode
1. Ouvrez le **Report Navigator** (`Cmd + 9`).
2. Cliquez sur l'onglet **Cloud** en haut.
3. Déroulez le workflow souhaité pour voir les étapes en direct et inspecter les logs détaillés en cas d'erreur.

### Option C — Sur le Web (App Store Connect)
Rendez-vous sur [appstoreconnect.apple.com](https://appstoreconnect.apple.com) > **Xcode Cloud** pour visualiser les artefacts et gérer les groupes de test.

---

## 6. Nettoyage et gestion des tags

Si un tag a été poussé par erreur ou pour relancer un build :
```bash
# 1. Supprimer le tag sur le dépôt distant
git push origin --delete <nom-du-tag>

# 2. Supprimer le tag en local
git tag -d <nom-du-tag>
```
