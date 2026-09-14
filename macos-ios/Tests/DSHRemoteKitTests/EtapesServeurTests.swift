import Foundation
import Testing

@testable import DSHRemoteKit

// LE PARCOURS D'UN SERVEUR, ÉPROUVÉ ÉTAPE PAR ÉTAPE.
//
// Ces étapes remplacent un diagnostic : elles disent OÙ l'on en est, donc quoi
// faire ensuite. Une étape affirmée à tort envoie chercher au mauvais endroit —
// publier un port sur un Mac éteint, installer un plugin derrière un port fermé,
// OU INSTALLER UN PLUGIN DÉJÀ LÀ parce qu'on a pris l'absence de jeton pour
// l'absence de DSH. Les tests tiennent donc surtout les cas où l'on NE SAIT PAS,
// et celui où l'on sait très bien : l'appareil n'est pas appairé.

/// Les cinq étapes d'une machine DÉJÀ APPAIRÉE, sauf mention contraire.
///
/// POURQUOI UNE VALEUR PAR DÉFAUT ICI. La plupart des cas éprouvés dans ce fichier
/// portent sur la MACHINE — visible, port publié, plugin chargé — et se lisaient
/// avant que l'appairage existe. L'appairage a ses propres tests, explicites ;
/// le répéter dans chacun des autres noierait ce que chacun vérifie.
private func machine(
  tailnet: Bool? = true, enLigne: Bool = true, sertDsh: Bool? = nil, cause: CauseSansDsh? = nil,
  appairage: EtapesServeur.EtatAppairage = .appaire
) -> [EtapesServeur.Etape] {
  EtapesServeur.etapes(
    tailnetDeLAppareil: tailnet, enLigne: enLigne, sertDsh: sertDsh, cause: cause,
    appairage: appairage)
}

private func etat(_ etapes: [EtapesServeur.Etape], _ numero: Int) -> EtapesServeur.Etat? {
  etapes.first { $0.numero == numero }?.etat
}

private func etape(_ etapes: [EtapesServeur.Etape], _ numero: Int) -> EtapesServeur.Etape? {
  etapes.first { $0.numero == numero }
}

@Test("Sans Tailscale sur CET APPAREIL, rien en aval ne se conclut")
func appareilHorsTailnet() {
  // Le propriétaire a demandé cette étape après coup, et elle manquait : sur un
  // iPhone sans Tailscale, les trois autres ne peuvent pas être franchies.
  let etapes = machine(tailnet: false, sertDsh: true)

  #expect(etat(etapes, 1) == .aFaire)
  // MÊME SI la liste dit une machine en ligne et que la sonde a répondu : depuis
  // un appareil qui ne peut plus rien joindre, ces mesures parlent du passé.
  #expect(etat(etapes, 2) == .inconnue)
  #expect(etat(etapes, 3) == .inconnue)
  #expect(etat(etapes, 4) == .inconnue)
  #expect(EtapesServeur.premiereAEtapesFranchir(etapes) == 1)
  // L'APPAIRAGE, LUI, NE SE DÉDUIT PAS DU RÉSEAU : le jeton est rangé ici, ou il
  // ne l'est pas. Un tailnet coupé ne l'efface pas, et le dire « inconnu » serait
  // remplacer un fait local par une supposition.
  #expect(etat(etapes, 5) == .franchie)
}

@Test("Un Mac hors ligne : la deuxième étape reste à franchir, les suivantes sont INCONNUES")
func macHorsLigne() {
  let etapes = machine(enLigne: false, sertDsh: nil)

  #expect(etat(etapes, 1) == .franchie)
  #expect(etat(etapes, 2) == .aFaire)
  // Une machine éteinte ne dit rien de son port ni de son plugin.
  #expect(etat(etapes, 3) == .inconnue)
  #expect(etat(etapes, 4) == .inconnue)
  #expect(EtapesServeur.premiereAEtapesFranchir(etapes) == 2)
}

@Test("L'explication de l'étape 2 SUIT son état — hors ligne ne se dit pas « en ligne »")
func explicationDeLaVisibilite() {
  // Défaut constaté sur capture, sur un Mac éteint : l'étape 2 était déclarée
  // « à faire » et s'expliquait pourtant par « Il est en ligne sur le tailnet,
  // donc la découverte le propose ». Une explication qui contredit son propre
  // titre fait douter du diagnostic entier, et envoie chercher au mauvais
  // endroit : ici, l'utilisateur croyait la machine joignable.
  let horsLigne = machine(enLigne: false, sertDsh: nil)
  let visibilite = etape(horsLigne, 2)
  #expect(visibilite?.etat == .aFaire)
  #expect(visibilite?.explication.contains(L("hors ligne")) == true)
  // La phrase de l'étape franchie ne doit plus pouvoir s'afficher ici.
  #expect(visibilite?.explication.contains("est en ligne") == false)

  // Le cas symétrique reste dit comme avant.
  let enLigne = machine(sertDsh: nil)
  #expect(etape(enLigne, 2)?.explication == L("Il est en ligne sur le tailnet, donc la découverte le propose."))

  // Et depuis un appareil hors tailnet, on ne peut RIEN dire de la visibilité de
  // ce Mac-là : l'explication le dit, au lieu d'affirmer qu'il est en ligne.
  // C'était le second endroit où la phrase de l'étape franchie s'affichait pour
  // une étape inconnue.
  let dAilleurs = machine(tailnet: false, sertDsh: true)
  let inconnue = etape(dAilleurs, 2)
  #expect(inconnue?.etat == .inconnue)
  #expect(inconnue?.explication.contains("est en ligne") == false)
}

@Test("Aucune explication n'affirme l'inverse de son état")
func explicationsCoherentesAvecLEtat() {
  // Même règle pour les deux étapes que la sonde juge : une étape « à faire »
  // décrit ce qui EST constaté, pas ce que l'étape franchie voulait dire.
  let portFerme = machine(sertDsh: false, cause: .rienNEcoute)
  let port = etape(portFerme, 3)
  #expect(port?.etat == .aFaire)
  #expect(port?.explication == L("Rien ne répond sur son port 80 : `tailscale serve` ne le publie pas."))
  #expect(port?.explication.contains("est publié") == false)

  let sansPlugin = machine(sertDsh: false, cause: .pluginAbsent)
  let plugin = etape(sansPlugin, 4)
  #expect(plugin?.etat == .aFaire)
  #expect(plugin?.explication == L("DSH Remote n'y répond pas : la machine ne peut pas servir l'application."))
  #expect(plugin?.explication.contains("y répond :") == false)
}

@Test("Port fermé : on n'accuse PAS le plugin, qui est peut-être installé")
func portFerme() {
  // `-1004` : la machine répond, mais rien n'écoute sur son port 80.
  let etapes = machine(sertDsh: false, cause: .rienNEcoute)

  #expect(etat(etapes, 1) == .franchie)
  #expect(etat(etapes, 2) == .franchie)
  #expect(etat(etapes, 3) == .aFaire)
  // Un port fermé ne dit RIEN du plugin : l'envoyer installer derrière un port
  // fermé ferait faire un travail inutile, dans le mauvais ordre.
  #expect(etat(etapes, 4) == .inconnue)
  #expect(EtapesServeur.premiereAEtapesFranchir(etapes) == 3)
}

@Test("Port ouvert sans plugin : seule la quatrième reste")
func portOuvertSansPlugin() {
  // `404` : quelque chose a répondu. C'est la mesure faite sur MacMini, dont le
  // port 80 est publié mais où le plugin n'est pas chargé.
  let etapes = machine(sertDsh: false, cause: .pluginAbsent)

  #expect(etat(etapes, 1) == .franchie)
  #expect(etat(etapes, 2) == .franchie)
  #expect(etat(etapes, 3) == .franchie)
  #expect(etat(etapes, 4) == .aFaire)
  #expect(EtapesServeur.premiereAEtapesFranchir(etapes) == 4)
}

@Test("DSH répond et l'appareil est appairé : les cinq étapes sont franchies")
func serveurPret() {
  let etapes = machine(sertDsh: true)

  #expect(etapes.allSatisfy { $0.etat == .franchie })
  #expect(EtapesServeur.premiereAEtapesFranchir(etapes) == nil)
}

// ── LA CINQUIÈME ÉTAPE : L'APPAIRAGE ─────────────────────────────────────────
//
// POURQUOI CES TESTS SONT LES PLUS IMPORTANTS DU FICHIER. Sans jeton rangé, la
// sonde ne partait pas, le verdict restait vide, et la page annonçait « pas de
// DSH » : l'utilisateur partait installer un plugin DÉJÀ INSTALLÉ sur une machine
// parfaitement prête. Le cas le plus fréquent — on installe l'application, le Mac
// tourne depuis longtemps — était celui qui mentait le plus.

@Test("Une machine prête mais NON APPAIRÉE le dit, au lieu de rester suspendue")
func serveurPretMaisPasAppaire() {
  // LE CŒUR DE LA REFONTE. Les quatre premières étapes sont franchies, la
  // cinquième ne l'est pas : la conclusion doit la NOMMER, et surtout ne pas
  // annoncer « Vérification en cours… » — il n'y a rien à vérifier, tout est su.
  let etapes = machine(sertDsh: true, appairage: .absent)

  #expect(etat(etapes, 4) == .franchie)
  #expect(etat(etapes, 5) == .aFaire)
  #expect(EtapesServeur.premiereAEtapesFranchir(etapes) == 5)
  #expect(EtapesServeur.resume(etapes) == "Il reste une étape : « Cet appareil est appairé ».")
  // Et la pastille de la machine ne dit plus « pas de DSH » : elle sert DSH.
  #expect(etape(etapes, 5)?.explication.contains("refusée") == true)
}

@Test("Un jeton REFUSÉ n'est pas un appairage")
func jetonRefuseNestPasUnAppairage() {
  // Un secret étranger rangé sous le nom de cette machine : la connexion échoue,
  // et le dire « appairé » enverrait chercher la panne du côté du réseau.
  let etapes = machine(sertDsh: true, appairage: .refuse)
  #expect(etat(etapes, 5) == .aFaire)

  // Le CONSTAT reste vrai dans les deux cas — c'est le remède qui les distingue,
  // et il est dans la méthode, pas ici.
  let absent = machine(sertDsh: true, appairage: .absent)
  #expect(etape(etapes, 5)?.explication == etape(absent, 5)?.explication)
}

@Test("Sonde pas encore rendue : on ne conclut NI sur le port NI sur le plugin")
func sondeEnCours() {
  let etapes = machine(sertDsh: nil)

  #expect(etat(etapes, 1) == .franchie, "constaté localement, déjà connu")
  #expect(etat(etapes, 2) == .franchie, "en ligne est un fait de Tailscale, déjà connu")
  #expect(etat(etapes, 3) == .inconnue)
  #expect(etat(etapes, 4) == .inconnue)
  #expect(EtapesServeur.premiereAEtapesFranchir(etapes) == 3)
}

@Test("Une erreur qui n'explique rien ne fait conclure sur le port")
func erreurSansCause() {
  // Délai, DNS, ou tout autre échec : la machine ne répond pas, mais on ne sait
  // pas si c'est le port ou le réseau. Dire « le port est fermé » enverrait
  // publier un port qui l'est peut-être déjà.
  let etapes = machine(sertDsh: false, cause: nil)

  #expect(etat(etapes, 2) == .franchie)
  #expect(etat(etapes, 3) == .inconnue)
  #expect(etat(etapes, 4) == .inconnue)
}

@Test("Tant qu'on n'a pas MESURÉ, la première étape est inconnue — pas « à faire »")
func reseauNonMesure() {
  // Défaut corrigé : `false` par défaut affichait « à faire » pour une étape que
  // personne n'avait constatée. Une capture l'a montré — l'ancre de vérification
  // court-circuite le démarrage, donc rien n'était mesuré, et le parcours
  // affirmait que Tailscale n'était pas connecté alors que le Mac l'était.
  let etapes = machine(tailnet: nil, sertDsh: true)
  #expect(etat(etapes, 1) == .inconnue)
  #expect(EtapesServeur.premiereAEtapesFranchir(etapes) == 1)

  let ajout = EtapesServeur.etapesDAjout(tailnetDeLAppareil: nil)
  #expect(ajout[0].etat == .inconnue)
}

@Test("Les étapes sont numérotées dans l'ordre où elles se franchissent")
func ordreDesEtapes() {
  let etapes = machine(sertDsh: nil)
  #expect(etapes.map(\.numero) == [1, 2, 3, 4, 5])
  #expect(etapes.allSatisfy { !$0.titre.isEmpty && !$0.explication.isEmpty })
  // Et la première parle bien de l'appareil, pas du Mac visé.
  #expect(etapes[0].titre == L("Tailscale est connecté sur cet appareil"))
  #expect(etapes[4].titre == L("Cet appareil est appairé"))
}

@Test("La liste d'ajout : deux étapes se constatent d'ici, trois sont le travail du Mac")
func etapesDAjout() {
  // Il n'y a pas encore de machine : les étapes 2 à 4 sont une LISTE de travail,
  // pas un verdict. Les deux qui concernent l'appareil — Tailscale, et
  // l'appairage à obtenir — disent leur état.
  let sansTailscale = EtapesServeur.etapesDAjout(tailnetDeLAppareil: false)
  #expect(sansTailscale.map(\.numero) == [1, 2, 3, 4, 5])
  #expect(sansTailscale[0].etat == .aFaire)
  #expect(sansTailscale.dropFirst().allSatisfy { $0.etat == .aFaire })
  #expect(EtapesServeur.premiereAEtapesFranchir(sansTailscale) == 1)

  let avecTailscale = EtapesServeur.etapesDAjout(tailnetDeLAppareil: true)
  #expect(avecTailscale[0].etat == .franchie)
  #expect(EtapesServeur.premiereAEtapesFranchir(avecTailscale) == 2)
  // Les étapes parlent du Mac À AJOUTER, pas d'une machine connue.
  #expect(avecTailscale[1].titre == L("La machine à ajouter est sur le tailnet"))
  // L'appairage est « à faire » PAR CONSTRUCTION : on vient ici pour en obtenir
  // un pour la machine qu'on ajoute, pas pour constater celui d'une autre.
  #expect(avecTailscale[4].etat == .aFaire)
  #expect(avecTailscale[4].responsable == .appareil)
}

@Test("Les étapes SUIVANT la frontière sont verrouillées")
func verrouDesEtapes() {
  // Demande du propriétaire : « si une étape de goal n'est pas réalisée, les
  // goals suivants sont grisés ». On ne publie pas un port sur un Mac qui n'est
  // pas sur le réseau, et on n'installe pas un plugin derrière un port fermé.
  let portFerme = machine(sertDsh: false, cause: .rienNEcoute, appairage: .absent)
  #expect(!EtapesServeur.estVerrouillee(portFerme[0], dans: portFerme), "franchie")
  #expect(!EtapesServeur.estVerrouillee(portFerme[1], dans: portFerme), "franchie")
  #expect(!EtapesServeur.estVerrouillee(portFerme[2], dans: portFerme), "c'est LA frontière")
  #expect(EtapesServeur.estVerrouillee(portFerme[3], dans: portFerme), "après la frontière")
  // ET L'APPAIRAGE VIENT APRÈS LE PLUGIN : on ne scanne pas le QR code d'un
  // panneau qui n'existe pas encore.
  #expect(EtapesServeur.estVerrouillee(portFerme[4], dans: portFerme))

  // Sans frontière — tout est franchi —, plus rien n'est verrouillé.
  let pret = machine(sertDsh: true)
  #expect(pret.allSatisfy { !EtapesServeur.estVerrouillee($0, dans: pret) })

  // Et le verrou suit la PREMIÈRE non franchie, pas la première « à faire » : une
  // étape inconnue bloque aussi ce qui la suit.
  let inconnu = machine(sertDsh: nil)
  #expect(!EtapesServeur.estVerrouillee(inconnu[2], dans: inconnu))
  #expect(EtapesServeur.estVerrouillee(inconnu[3], dans: inconnu))
}

@Test("Sur une liste de travail, le verrou ne traverse pas les côtés")
func verrouDuneListeDeTravail() {
  // POURQUOI CETTE RÈGLE. Sur « Ajouter un serveur », les étapes du Mac sont
  // « à faire » PAR CONSTRUCTION : on ne juge pas une machine qu'on n'a pas
  // encore. Si elles verrouillaient la suite, le seul geste que l'appareil a à
  // faire ici — prendre le QR code — resterait grisé derrière un travail qui se
  // fait ailleurs, sur une machine que l'application ne connaît même pas.
  let etapes = EtapesServeur.etapesDAjout(tailnetDeLAppareil: true)
  #expect(!EtapesServeur.estVerrouillee(etapes[1], dans: etapes, mode: .objectifs))
  #expect(EtapesServeur.estVerrouillee(etapes[2], dans: etapes, mode: .objectifs))
  #expect(EtapesServeur.estVerrouillee(etapes[3], dans: etapes, mode: .objectifs))
  #expect(
    !EtapesServeur.estVerrouillee(etapes[4], dans: etapes, mode: .objectifs),
    "l'appairage relève de l'appareil : le travail du Mac ne le précède pas")

  // MAIS SANS TAILSCALE SUR CET APPAREIL, L'APPAIRAGE EST VERROUILLÉ — par la
  // seule étape qui le précède DU MÊME CÔTÉ. Rien n'est joignable, donc il n'y a
  // rien à appairer.
  let sansReseau = EtapesServeur.etapesDAjout(tailnetDeLAppareil: false)
  #expect(EtapesServeur.estVerrouillee(sansReseau[4], dans: sansReseau, mode: .objectifs))

  // ET CE MODE N'EST PAS CELUI D'UN DIAGNOSTIC : là, on juge une machine, et les
  // cinq étapes forment une chaîne MESURÉE — le plugin manquant bloque le scan,
  // qui n'a nulle part où se faire.
  let jugees = machine(sertDsh: false, cause: .pluginAbsent, appairage: .absent)
  #expect(EtapesServeur.estVerrouillee(jugees[4], dans: jugees, mode: .diagnostic))
}

@Test("La conclusion du diagnostic distingue prêt, reste à faire, et pas encore su")
func resumeDuDiagnostic() {
  // Un diagnostic se lit par sa conclusion : « ce serveur est-il utilisable ? »
  // est la question, les cinq étapes sont la démonstration.
  let pret = machine(sertDsh: true)
  #expect(EtapesServeur.resume(pret) == "Ce serveur est prêt.")

  // UNE seule étape : on la NOMME — c'est l'information la plus utile, et elle
  // évite d'avoir à lire la liste pour savoir laquelle.
  let uneSeule = machine(sertDsh: false, cause: .pluginAbsent)
  #expect(EtapesServeur.resume(uneSeule).contains("une étape"))
  #expect(EtapesServeur.resume(uneSeule).contains("plugin"))

  // LE CAS QUI A MOTIVÉ LA CINQUIÈME ÉTAPE. Une machine parfaitement prête dont
  // l'appareil n'a pas le jeton : la conclusion NOMME l'appairage. Avant, elle
  // annonçait « Vérification en cours… » — indéfiniment, et à tort.
  let pasAppaire = machine(sertDsh: true, appairage: .absent)
  #expect(EtapesServeur.resume(pasAppaire) == "Il reste une étape : « Cet appareil est appairé ».")

  // PLUSIEURS ÉTAPES À FAIRE : on compte, sans en cacher aucune. C'est le cas
  // d'une machine hors ligne dont l'appareil n'a pas non plus de jeton.
  let deux = machine(enLigne: false, sertDsh: nil, appairage: .absent)
  #expect(EtapesServeur.resume(deux) == "Il reste 2 étapes sur 5.")

  // Cette liste-ci est construite à la main, pour couvrir la branche le jour où
  // les règles changeraient.
  let plusieurs = [
    EtapesServeur.Etape(numero: 1, titre: "a", explication: "a", etat: .franchie),
    EtapesServeur.Etape(numero: 2, titre: "b", explication: "b", etat: .aFaire),
    EtapesServeur.Etape(numero: 3, titre: "c", explication: "c", etat: .aFaire),
    EtapesServeur.Etape(numero: 4, titre: "d", explication: "d", etat: .inconnue),
  ]
  #expect(EtapesServeur.resume(plusieurs) == "Il reste 2 étapes sur 4.")

  // LA FRONTIÈRE INCONNUE L'EMPORTE : on ne peut rien affirmer des suivantes, et
  // compter des étapes qu'on ne sait pas juger serait affirmer à leur place.
  let enCours = machine(tailnet: nil, sertDsh: nil)
  #expect(EtapesServeur.resume(enCours) == "Vérification en cours…")
}

// ── DE QUI RELÈVE CHAQUE ÉTAPE ────────────────────────────────────────────────
//
// POURQUOI CES TESTS EXISTENT. La page « Ajouter un serveur » présentait les
// quatre étapes sur le même plan, comme un travail à faire au même endroit. C'est
// faux : sur l'application distante, DEUX étapes se constatent depuis l'appareil
// — Tailscale, et l'appairage —, et les trois autres appartiennent au Mac, que
// l'application vérifie déjà toute seule. Le jour où cette répartition se déplace
// (une étape ajoutée, une responsabilité changée), c'est la MISE EN PAGE qui
// change sans que rien ne le dise : ces tests la tiennent.

@Test("Deux étapes relèvent de l'appareil : Tailscale, et l'appairage")
func responsabiliteDeLAppareil() {
  for etapes in [
    EtapesServeur.etapesDAjout(tailnetDeLAppareil: nil),
    EtapesServeur.etapesDAjout(tailnetDeLAppareil: true),
  ] {
    let appareil = EtapesServeur.deLAppareil(etapes)
    #expect(appareil.count == 2, "l'application constate Tailscale, et son propre appairage")
    #expect(appareil.map(\.numero) == [1, 5])
    #expect(appareil.first?.titre.contains("Tailscale") == true)
  }
}

@Test("Les trois autres étapes relèvent du Mac, et aucune ne se perd")
func responsabiliteDuHote() {
  // LA RÉPARTITION DOIT COUVRIR TOUTES LES ÉTAPES : une étape qui ne serait ni de
  // l'appareil ni du Mac disparaîtrait des deux blocs, donc de l'écran.
  for etapes in [
    EtapesServeur.etapesDAjout(tailnetDeLAppareil: true),
    EtapesServeur.etapesDAjout(tailnetDeLAppareil: false),
    machine(sertDsh: true),
  ] {
    let appareil = EtapesServeur.deLAppareil(etapes)
    let hote = EtapesServeur.deLHote(etapes)
    #expect(appareil.count + hote.count == etapes.count, "une étape n'est rattachée à personne")
    #expect(hote.count == 3)
    #expect(hote.map(\.numero) == [2, 3, 4])
  }
}
