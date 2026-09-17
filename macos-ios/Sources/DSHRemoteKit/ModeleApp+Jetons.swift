import Foundation

/// LES JETONS — où on les lit, où on les range, et ce qu'on ne fait JAMAIS.
///
/// POURQUOI CE FICHIER EXISTE. C'est le domaine qui touche aux secrets, et il porte
/// trois règles nées de défauts constatés — dont deux qui ont envoyé le secret d'une
/// machine à une autre :
///
///   1. **le jeton est PAR HÔTE.** Chaque hôte tire le sien (mesuré) : un compte unique
///      obligeait à recopier le jeton à chaque bascule, et faisait envoyer à une
///      machine le secret d'une autre quand on oubliait ;
///   2. **le coffre du harness ne répond QUE pour la machine locale.** `estHoteLocal`
///      est un fait local (la boucle locale, ou les adresses que la découverte LOCALE
///      a marquées) — jamais le marqueur `estLocal` d'une liste REÇUE : c'est lui qui
///      a fait envoyer le jeton du coffre à un Mac distant qui s'était marqué
///      lui-même ;
///   3. **l'ancienne clé d'hôte reste lisible.** Elle portait le schéma
///      (« http://mac… ») ; la même machine en `https` serait devenue une AUTRE
///      machine, et le jeton rangé pour la forme en clair aurait été introuvable. On
///      le retrouve, on le réécrit sous la clé neuve, et on efface l'ancienne.
///
/// CE QU'ON N'ÉCRIT JAMAIS : le jeton lui-même. Il n'apparaît dans aucune trace — les
/// journaux de l'application n'impriment que sa LONGUEUR et son EMPREINTE (`Empreinte`,
/// qui n'est pas réversible). C'est la règle du dépôt (RÈGLE #0, interdit #3), et elle
/// est vérifiable ici, en un fichier.
///
/// LA CONTRAINTE, RAPPELÉE ICI : une extension Swift ne porte pas de propriété
/// stockée. `jetonSaisi`, `cleJetonChargee` et `gardien` restent dans la classe.
extension ModeleApp {

  /// Charge, depuis le gardien, le jeton gardé POUR CETTE machine.
  ///
  /// Ne relit que si la clé d'hôte a changé : le champ d'adresse déclenche une
  /// transition par frappe, et une lecture de trousseau par caractère serait un
  /// gaspillage — sans compter les invites système qu'elle peut provoquer.
  func chargerJetonDeLaCible() {
    let cle = IdentiteHote.cle(cible.adresse)
    guard cle != cleJetonChargee else { return }
    cleJetonChargee = cle
    jetonSaisi = jetonGarde(pour: cible.adresse) ?? ""
  }

  /// Lit le jeton gardé pour un hôte, EN COMPTANT AVEC L'ANCIENNE CLÉ.
  ///
  /// POURQUOI CETTE SECONDE LECTURE EXISTE. Les clés d'hôte portaient autrefois le
  /// schéma (« http://mac.tailnet.ts.net ») ; elles ne le portent plus, parce que
  /// la même machine en `http` et en `https` est la MÊME machine — le transport
  /// dépend du paquet, pas de l'hôte. Un jeton rangé par une version antérieure
  /// serait donc introuvable, et l'utilisateur lirait « aucun jeton » pour un
  /// appareil parfaitement appairé. On le retrouve ici, on le RÉÉCRIT sous la clé
  /// neuve, et on efface l'ancienne : la migration se fait une fois, sans geste, et
  /// aucun secret ne reste en double.
  func jetonGarde(pour adresse: String) -> String? {
    let cle = IdentiteHote.cle(adresse)
    if let trouve = gardien.lire(pour: cle), !trouve.isEmpty { return trouve }
    let ancienne = "http://" + cle
    guard let ancien = gardien.lire(pour: ancienne), !ancien.isEmpty else { return nil }
    gardien.ecrire(ancien, pour: cle)
    gardien.effacer(pour: ancienne)
    return ancien
  }

  /// Le jeton À UTILISER pour la cible : celui gardé POUR ELLE, sinon — et
  /// seulement si la cible EST cette machine — celui du coffre local.
  ///
  /// POURQUOI LE COFFRE N'EST CONSULTÉ QU'ICI. `~/.dsh/.credentials.yaml`
  /// contient le jeton émis par l'hôte LOCAL, et rien d'autre. Le proposer pour
  /// une autre machine, c'était lui envoyer le secret d'une autre — et un refus
  /// qui ne dit pas son nom. Quand on ne sait pas, on ne devine pas : le champ
  /// de jeton est sur la page, à portée.
  public func jetonDeLaCible() -> String {
    // ── LE CHAMP D'ABORD, ET C'EST UNE CORRECTION ──────────────────────────
    //
    // Régression que j'ai introduite en rendant le jeton « par hôte » : cette
    // fonction ne consultait plus `jetonSaisi`, seulement le gardien et le
    // coffre. Or `jetonSaisi` est la valeur la PLUS FRAÎCHE — celle qu'on vient
    // de coller, ou celle qu'un fichier d'amorçage a posée — et elle est déjà
    // rechargée par hôte à chaque changement de cible. Résultat mesuré : l'app
    // démarrait en `0 ms` sans rien tenter, avec « aucun jeton » alors que le
    // champ en contenait un.
    if !jetonSaisi.isEmpty {
      Trace.siActive("[jeton] champ en memoire : longueur=\(jetonSaisi.count) empreinte=\(empreinteJeton)")
      return jetonSaisi
    }
    let cle = IdentiteHote.cle(cible.adresse)
    if let garde = jetonGarde(pour: cible.adresse) {
      Trace.siActive(
        "[jeton] gardien de l'hote : longueur=\(garde.count) empreinte=\(Empreinte.de(garde).prefix(8))")
      return garde
    }
    // LE JETON DU COFFRE NE VA QU'À CETTE MACHINE. Le test est `estHoteLocal`, et
    // non `serveurVise?.estLocal` : le second lisait le marqueur d'une liste reçue,
    // donc envoyait le secret local à l'hôte distant qui s'était marqué lui-même.
    guard estHoteLocal(cible.adresse) else {
      Trace.siActive("[jeton] AUCUN jeton pour \(cle)")
      return ""
    }
    let duCoffre = CoffreDuHarness.jetonDeLaMachine() ?? ""
    Trace.siActive(
      "[jeton] coffre du harness : longueur=\(duCoffre.count) empreinte=\(duCoffre.isEmpty ? "aucun" : String(Empreinte.de(duCoffre).prefix(8)))"
    )
    return duCoffre
  }

  /// Le jeton saisi pour l'hôte VISÉ, gardé DÈS LA FRAPPE.
  ///
  /// POURQUOI PAS SEULEMENT À LA CONNEXION : on colle un jeton, on change d'avis
  /// ou de machine, et le secret serait perdu — alors qu'il vient d'être
  /// laborieusement recopié. Même raisonnement que l'adresse, mémorisée dès la
  /// frappe. Le jeton, lui, ne va JAMAIS dans les préférences : il va là où un
  /// secret doit vivre (voir `enregistrerJeton`).
  public func definirJeton(_ valeur: String) {
    enregistrerJeton(valeur)
  }

  /// Le même geste, POUR UNE MACHINE NOMMÉE.
  ///
  /// POURQUOI L'ADRESSE EST UN PARAMÈTRE. La page d'une machine peut être celle
  /// d'un AUTRE hôte que la cible — on ouvre la fiche d'un Mac sans s'y
  /// connecter. Or la lecture, l'écriture et l'effacement du jeton visaient tous
  /// `cible.adresse` : le champ annonçait « jeton de cet hôte » et agissait sur
  /// un autre. Un jeton collé là partait vers la mauvaise machine, et celui
  /// d'une autre s'affichait sous ce nom-là.
  public func definirJeton(_ valeur: String, pour adresse: String) {
    enregistrerJeton(valeur, pour: adresse)
  }

  /// Efface le jeton de L'HÔTE VISÉ : en mémoire, et là où il était gardé.
  public func effacerJeton() {
    effacerJeton(pour: cible.adresse)
  }

  /// Efface le jeton d'une machine nommée.
  public func effacerJeton(pour adresse: String) {
    let cle = IdentiteHote.cle(adresse)
    // Le champ en mémoire ne décrit que la cible : l'effacer parce qu'on efface
    // le jeton d'une AUTRE machine ferait disparaître sous les yeux de
    // l'utilisateur un secret qui n'était pas visé.
    if cle == IdentiteHote.cle(cible.adresse) { jetonSaisi = "" }
    gardien.effacer(pour: cle)
    // L'ANCIENNE CLÉ AUSSI : un effacement qui laisserait derrière lui le secret
    // rangé sous « http://<hôte> » serait un effacement qui ment — et c'est
    // exactement ce qu'on vient lire dans une réinitialisation.
    gardien.effacer(pour: "http://" + cle)
  }

  /// Enregistre le jeton saisi : au trousseau sur iOS, en mémoire sur macOS.
  ///
  /// N'est appelé qu'à la SOUMISSION du formulaire, jamais à la frappe : un
  /// enregistrement par caractère persistait un jeton tronqué, et faisait
  /// croire à un jeton disponible alors que la saisie n'était pas terminée.
  public func enregistrerJeton(_ valeur: String) {
    enregistrerJeton(valeur, pour: cible.adresse)
  }

  /// Enregistre le jeton D'UNE MACHINE NOMMÉE.
  public func enregistrerJeton(_ valeur: String, pour adresse: String) {
    let propre = valeur.trimmingCharacters(in: .whitespacesAndNewlines)
    let cle = IdentiteHote.cle(adresse)
    // LE CHAMP EN MÉMOIRE NE DÉCRIT QUE LA CIBLE. Y écrire le jeton d'une autre
    // machine ferait afficher ici le secret collé là-bas — et, pire, pourrait
    // l'envoyer à la cible.
    if cle == IdentiteHote.cle(cible.adresse) {
      jetonSaisi = propre
      cleJetonChargee = cle
    }

    // LE JETON DE L'HÔTE LOCAL N'EST PAS RECOPIÉ ICI. Il est dans le coffre du
    // harness, qui est sa source ; en garder une seconde copie multiplierait les
    // endroits où un secret peut fuir sans rien apporter.
    guard !adresse.isEmpty, !estHoteLocal(adresse) else { return }

    // C'est le GARDIEN qui sait s'il peut garder durablement — le modèle n'a pas
    // à connaître la plateforme (il le faisait, et c'était une erreur de
    // conception : deux `#if` dans la logique métier, pour une question de
    // stockage).
    if propre.isEmpty {
      gardien.effacer(pour: cle)
    } else {
      gardien.ecrire(propre, pour: cle)
    }
  }
}
