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

## 2. Procédure pour lancer une Bêta (TestFlight)

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
   # Création du tag avec le préfixe beta-
   git tag beta-0.1.0

   # Envoi sur le dépôt distant (déclenche Xcode Cloud)
   git push origin beta-0.1.0
   ```

4. **Distribution automatique :**
   - Xcode Cloud compile `Archive - iOS` et `Archive - macOS`.
   - Dès le traitement Apple terminé, la post-action `TestFlight Internal Testing` distribue la nouvelle version à vos testeurs.

---

## 3. Procédure pour la Production (App Store)

1. Après validation de la bêta par les testeurs :
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```
2. Le workflow de production s'exécute et déploie le binaire éligible pour soumission finale dans App Store Connect.

---

## 4. Comment suivre l'avancement des builds

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

## 5. Corriger / Supprimer un mauvais tag

Si un tag a été poussé par erreur :
```bash
# 1. Supprimer le tag en local
git tag -d <nom-du-tag>

# 2. Supprimer le tag sur le dépôt distant
git push origin --delete <nom-du-tag>
```
