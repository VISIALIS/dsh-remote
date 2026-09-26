#!/usr/bin/env python3
"""Écrit les deux tables de traduction depuis les clés du code.

POURQUOI CE SCRIPT EST VERSIONNÉ, ET PAS SEULEMENT LES TABLES. La table française
EST la liste des clés du code : l'écrire à la main garantit qu'elle dérivera. Ici,
les clés sont RELUES dans les sources, et le script REFUSE de produire une table
anglaise incomplète — la parité n'est donc pas seulement vérifiée à l'exécution par
un test (`TraductionTests.swift`), elle est exigée à l'écriture.

Ce fichier porte aussi les traductions : une seule source pour l'anglais, relue
d'un coup d'œil, et modifiable sans toucher au code Swift.

Usage :
    python3 Scripts/traduire.py            # écrit les deux tables
    python3 Scripts/traduire.py --verifier # n'écrit rien, et échoue si incomplet

LES CLÉS SONT LES PHRASES FRANÇAISES : le code, les commentaires et les clés
restent en français (RÈGLE #1) ; l'anglais est une traduction AJOUTÉE.
"""

import json
import pathlib
import re
import sys

PAQUET = pathlib.Path(__file__).resolve().parents[1]
SOURCES = PAQUET / "Sources"
SOURCE = SOURCES / "DSHRemoteKit"
RESSOURCES = SOURCE / "Ressources"
# LES LIBELLÉS DU MENU macOS ET DES WIDGETS VIVENT HORS DE LA BIBLIOTHÈQUE,
# et ils sont localisés comme les autres.
DOSSIERS_DE_CODE = [SOURCE, SOURCES / "DSHRemoteApp", PAQUET / "Widgets"]
VERIFIER = "--verifier" in sys.argv

APPEL = re.compile(r'\b[TL]\("((?:[^"\\]|\\.)*)"\)')


def desechapper(texte: str) -> str:
    """Rend le texte RÉEL d'un littéral Swift (guillemets, antislashs, sauts)."""
    return re.sub(
        r"\\(.)",
        lambda m: {"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(m.group(1), m.group(1)),
        texte,
    )


def echapper(texte: str) -> str:
    """Rend un texte écrivable dans un `.strings` (format d'Apple)."""
    return texte.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


TRADUCTIONS = {
    # ── Installation du plugin (démarches) ────────────────────────────────────
    "Le plugin `dsh-remote` n'est pas installé sur cette machine. DSH y tourne et son port 80 est publié — mais rien n'y expose DSH Remote.":
        "The `dsh-remote` plugin is not installed on that machine. DSH runs there and its port 80 is published — but nothing there serves DSH Remote.",
    "Aucun service n'écoute sur le port 80 de cette machine. Le tailnet, lui, fonctionne : la machine répond.":
        "No service is listening on that machine's port 80. The tailnet itself works: the machine answers.",
    "Le jeton n'est pas en cause ici : rien n'a pu être joint. Attention, il est PROPRE À CHAQUE HÔTE — celui de cette machine ne vaudra pas pour un autre.":
        "The token is not what failed here: nothing could be reached. Note that it is SPECIFIC TO EACH HOST — this machine's token will not work for another.",

    # ── Adresse et jeton ──────────────────────────────────────────────────────
    "Adresse": "Address",
    "Adresse de la machine": "Machine address",
    "Jeton d'appareil": "Device token",
    "Le coffre du harness de cette machine contient un AUTRE jeton.":
        "The harness vault on that machine holds a DIFFERENT token.",
    "Il s'affiche une seule fois, dans la sortie du harness, au premier chargement du plugin sur cette machine. Il est gardé au trousseau — jamais dans les préférences — et n'est jamais renvoyé par une route.":
        "It is shown only once, in the harness output, when the plugin first loads on that machine. It is kept in the keychain — never in the preferences — and is never returned by a route.",
    "Le service a refusé ce jeton. Chaque machine a le sien : recopiez celui de CET hôte.":
        "The service refused this token. Each machine has its own: copy the one for THIS host.",
    "Le service a refusé ce jeton. Collez celui de CET hôte : chaque machine a le sien.":
        "The service refused this token. Paste the one for THIS host: each machine has its own.",
    "Essayer le jeton du coffre": "Try the vault token",
    "Coller le jeton depuis le presse-papier": "Paste the token from the clipboard",
    "Effacer le jeton": "Clear the token",
    "Effacer le jeton saisi": "Clear the entered token",
    "« Se connecter » vise cette adresse tout de suite. « Tester l'adresse » ne change pas de serveur : elle dit seulement ce qu'elle a trouvé.":
        "“Connect” targets this address right away. “Test the address” does not change server: it only reports what it found.",
    "test de l'adresse…": "testing the address…",
    "Se connecter": "Connect",
    "Tester l'adresse": "Test the address",
    "Terminé": "Done",
    "Ou, en ligne de commande :": "Or, on the command line:",

    # ── Parcours d'un serveur ─────────────────────────────────────────────────
    "Allumez cette machine-là, et vérifiez que Tailscale y est connecté :":
        "Turn that machine on, and check that Tailscale is connected there:",
    "S'il n'y est pas connecté :": "If it is not connected there:",
    "Vérifiez l'état du tailnet, sur cette machine-là ou sur une autre :":
        "Check the tailnet state, on that machine or on another:",
    "Vérifiez sur cette machine ce qui est publié :":
        "Check what is published on this machine:",
    "Ajouter un serveur": "Add a server",
    "Chercher une machine": "Find a machine",
    "Saisir une adresse": "Enter an address",
    "à vérifier": "to check",
    "serveur courant": "current server",
    "serveur actif": "active server",
    "Serveurs": "Servers",
    "Sélectionne ce serveur": "Selects this server",
    "Ouvre la page de ce serveur": "Opens this server's page",
    "Ouvrir la page": "Open page",
    "Affiche ce serveur": "Shows this server",
    "Ouvre la page d'ajout et d'appairage": "Opens the add and pair page",
    "Réglages de cette machine": "Settings for this machine",
    "Détail technique": "Technical detail",
    "Suivre l'activité": "Follow activity",
    "Chargées en mémoire seulement": "Loaded in memory only",

    # ── Sessions et journal ───────────────────────────────────────────────────
    "Aucune session ouverte": "No session open",
    "Aucune session en mémoire": "No sessions in memory",
    "Aucune session": "No sessions",
    "Aucun événement": "No events",
    "Cette session n'a encore rien écrit.": "This session has not written anything yet.",
    "Choisissez une session dans la liste pour lire son journal.":
        "Choose a session in the list to read its journal.",
    "Les sessions de cette machine apparaîtront ici. Lancez-en une sur le Mac, ou choisissez une autre machine ci-dessus.":
        "This machine's sessions will appear here. Start one on the host, or choose another machine above.",
    "Le journal n'a pas pu être lu.": "The journal could not be read.",
    "Lecture du journal…": "Reading the journal…",
    "Réessayer": "Try again",
    "Les afficher toutes": "Show them all",
    "Marquer comme vu": "Mark as seen",
    "Vu": "Seen",
    "Copier le titre": "Copy the title",
    "Copier l'identifiant": "Copy the identifier",
    "Copier l'adresse": "Copy the address",
    "Oublier ce serveur": "Forget this server",
    "aucune session": "no sessions",
    "Ajouter": "Add",
    "Rechercher une session, un projet…": "Search a session or a project…",
    "Effacer la recherche": "Clear the search",

    # ── Écriture ──────────────────────────────────────────────────────────────
    "Écrire à cette session…": "Write to this session…",
    "Envoyer": "Send",
    "Envoyer le message": "Send the message",
    "À la suite": "Queued",
    "Tout de suite (interrompt)": "Right away (interrupts)",
    "Interrompre": "Interrupt",
    "Interrompre le tour en cours": "Interrupt the current turn",
    "Interrompre le tour en cours — la file d'attente est conservée":
        "Interrupt the current turn — the queue is kept",
    "Le travail déjà fait est conservé, et la file d'attente aussi.":
        "Work already done is kept, and so is the queue.",
    "Annuler": "Cancel",

    # ── Réglages ──────────────────────────────────────────────────────────────
    "Réglages": "Settings",
    "Cet appareil": "This device",
    "Alertes": "Alerts",
    "Me prévenir quand l'agent attend ou termine":
        "Notify me when the agent waits or finishes",
    "Une alerte part quand une session se met à ATTENDRE une réponse, ou quand un tour se termine — jamais pour ce que vous êtes en train de regarder. Elle n'est envoyée que tant que l'application tourne : iOS la suspend en arrière-plan, et la réveiller demanderait un serveur de notification, que ce projet n'a pas.":
        "An alert is sent when a session STARTS waiting for an answer, or when a turn finishes — never for what you are already looking at. It is only sent while the application is running: iOS suspends it in the background, and waking it up would require a notification server, which this project does not have.",
    "Vérifier maintenant": "Check now",
    "Diagnostic": "Diagnostic",
    "Copier le chemin du fichier": "Copy the file path",
    "Les erreurs qu'aucune explication ne couvre y sont écrites : l'adresse visée, le message, la longueur du jeton et une empreinte de celui-ci. Le jeton lui-même n'y est jamais recopié.":
        "Errors that no explanation covers are written there: the address targeted, the message, the token length and a fingerprint of it. The token itself is never copied there.",
    "Aucun dossier de documents : cette exécution n'écrit pas de diagnostic.":
        "No documents folder: this run does not write a diagnostic.",
    "À propos": "About",

    # ── Divers ────────────────────────────────────────────────────────────────
    "DSH Remote": "DSH Remote",
}

RESSOURCES = SOURCE / "Ressources"

APPEL = re.compile(r'\b[TL]\(\s*"((?:[^"\\]|\\.)*)"', re.MULTILINE)


def desechapper(texte: str) -> str:
    """Rend le texte RÉEL d'un littéral Swift (guillemets, antislashs, sauts)."""
    return re.sub(
        r"\\(.)",
        lambda m: {"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(m.group(1), m.group(1)),
        texte,
    )


def echapper(texte: str) -> str:
    """Rend un texte écrivable dans un `.strings` (format d'Apple)."""
    return texte.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def clefs_du_code() -> set[str]:
    clefs: set[str] = set()
    fichiers = [f for dossier in DOSSIERS_DE_CODE for f in sorted(dossier.glob("*.swift"))]
    for fichier in fichiers:
        for ligne in fichier.read_text(encoding="utf-8").splitlines():
            if ligne.lstrip().startswith("//"):
                continue
            for brut in APPEL.findall(ligne):
                # Une clé interpolée devient à l'exécution un motif de format
                # (`%lld sessions…`) que la table ne peut pas porter telle quelle ;
                # une clé vide ne dit rien. Les deux restent donc en français, et
                # c'est écrit dans le README parmi ce qui reste à faire.
                if "\\(" in brut or brut.strip() == "":
                    continue
                clefs.add(desechapper(brut))
    return clefs


def main() -> int:
    clefs = clefs_du_code()
    manquantes = sorted(c for c in clefs if c not in TRADUCTIONS)
    inutilisees = sorted(c for c in TRADUCTIONS if c not in clefs)

    if inutilisees:
        print(f"NOTE : {len(inutilisees)} traduction(s) sans clé dans le code :")
        for clef in inutilisees:
            print(f"  · {clef}")
    if manquantes:
        print(f"REFUS : {len(manquantes)} clé(s) sans traduction anglaise :")
        for clef in manquantes:
            print(f"  · {clef}")
        return 1

    print(f"{len(clefs)} clés, toutes traduites")
    if VERIFIER:
        return 0

    entete = (
        "/* Table {langue} — ÉCRITE PAR Scripts/traduire.py, ne pas éditer à la main.\n"
        "   Les clés sont les phrases FRANÇAISES : le code, les commentaires et les clés\n"
        "   restent en français (RÈGLE #1) ; l'anglais est une traduction ajoutée.\n"
        "   {nombre} clés. */\n\n"
    )
    for langue in ("fr", "en"):
        lignes = [entete.format(langue="française" if langue == "fr" else "anglaise",
                                nombre=len(clefs))]
        for clef in sorted(clefs, key=lambda c: c.lower()):
            valeur = clef if langue == "fr" else TRADUCTIONS[clef]
            lignes.append(f'"{echapper(clef)}" = "{echapper(valeur)}";\n')
        dossier = RESSOURCES / f"{langue}.lproj"
        dossier.mkdir(parents=True, exist_ok=True)
        (dossier / "Localizable.strings").write_text("".join(lignes), encoding="utf-8")
        print(f"  {langue}.lproj/Localizable.strings : {len(clefs)} clés")
    return 0



# ── Les messages du MODÈLE ────────────────────────────────────────────────────
#
# DEUXIÈME MOITIÉ DE LA TRANCHE DE LOCALISATION. Ces phrases ne sont pas dans les
# vues : elles sont CONSTRUITES par le modèle — états d'une machine, constats du
# diagnostic, refus d'écriture, alertes —, puis affichées telles quelles. Elles se
# traduisent au même endroit que les autres, et la parité est tenue par le même
# test.
TRADUCTIONS.update({
    # Les mots d'état d'une machine.
    "hors ligne": "offline",
    "pas de DSH": "no DSH",
    "vérification…": "checking…",
    "Rien ne peut être joint sur cette machine tant qu'elle est hors ligne sur le tailnet.":
        "Nothing can be reached on this machine while it is offline on the tailnet.",

    # Les mots d'état d'une session, lus par VoiceOver.
    "au repos": "idle",
    "tour en cours": "turn in progress",
    "attend votre réponse": "waiting for your answer",
    "terminée, pas encore lue": "finished, not read yet",
    "état inconnu": "unknown state",

    # Le parcours d'un serveur — titres et constats.
    "Tailscale est connecté sur cet appareil": "Tailscale is connected on this device",
    "Sans cela, aucune machine du tailnet n'est joignable — ni celui-ci, ni un autre.":
        "Without it, no machine on the tailnet can be reached — neither this one nor any other.",
    "Cette machine est visible": "This machine is visible",
    "Il est en ligne sur le tailnet, donc la découverte le propose.":
        "It is online on the tailnet, so discovery offers it.",
    "Il est hors ligne sur le tailnet : la découverte ne le propose donc pas.":
        "It is offline on the tailnet: discovery does not offer it.",
    "On ne peut pas le savoir d'ici : Tailscale n'est pas connecté sur cet appareil.":
        "It cannot be known from here: Tailscale is not connected on this device.",
    "Le port de DSH est ouvert": "The DSH port is open",
    "Rien ne répond sur son port 80 : `tailscale serve` ne le publie pas.":
        "Nothing answers on its port 80: `tailscale serve` does not publish it.",
    "Le plugin `dsh-remote` est installé": "The `dsh-remote` plugin is installed",
    "DSH Remote y répond : la machine peut servir l'application.":
        "DSH Remote answers there: the machine can serve the application.",
    "DSH Remote n'y répond pas : la machine ne peut pas servir l'application.":
        "DSH Remote does not answer there: the machine cannot serve the application.",
    "DSH Remote doit y répondre pour que la machine serve l'application.":
        "DSH Remote must answer there for the machine to serve the application.",

    # Le parcours « Ajouter un serveur » — les mêmes étapes, en travail à faire.
    "La machine à ajouter est sur le tailnet": "The machine to add is on the tailnet",
    "Le port de DSH y est ouvert": "The DSH port is open there",
    "Le plugin `dsh-remote` y est installé": "The `dsh-remote` plugin is installed there",
    "DSH Remote doit y répondre : publier DSH ne suffit pas.":
        "DSH Remote must answer there: publishing DSH is not enough.",

    # Les messages du modèle affichés par les vues.
    "Le serveur joint ne voit aucune machine sur le tailnet. Saisissez l'adresse ci-dessous.":
        "The server you reached sees no machine on the tailnet. Enter the address below.",
    "aucun": "none",

    # Les alertes.
    "Une session attend votre réponse": "A session is waiting for your answer",
    "L'agent est bloqué sur une décision.": "The agent is blocked on a decision.",
    "L'agent est bloqué sur une décision, dans plusieurs sessions.":
        "The agent is blocked on a decision, in several sessions.",
    "Un tour vient de se terminer": "A turn just finished",
    "Le résultat est dans le journal de cette session.":
        "The result is in this session's journal.",
    "Le résultat est dans le journal de ces sessions.":
        "The result is in these sessions' journals.",

    # Les refus d'écriture, traduits pour l'utilisateur.
    "cette session n'existe plus sur l'hôte": "this session no longer exists on the host",
    "aucun modèle n'est disponible pour cette session : choisissez-en un sur l'hôte":
        "no model is available for this session: choose one on the host",
    "l'agent n'a pas pu prendre ce message maintenant":
        "the agent could not take this message right now",
    "cette session ne peut pas être interrompue maintenant":
        "this session cannot be interrupted right now",
    "le fuseau horaire envoyé n'est pas reconnu": "the time zone sent is not recognised",
    "l'hôte a refusé la demande": "the host refused the request",
    "à la suite": "queued",
    "tout de suite (interrompt le tour en cours)": "right away (interrupts the current turn)",

    # Les erreurs du protocole.
    "origine refusée (403) — un client natif ne doit jamais envoyer d'en-tête Origin":
        "origin refused (403) — a native client must never send an Origin header",
})

# Les en-têtes de section et les valeurs de l'écran de réglages.
TRADUCTIONS.update({
    "Serveur DeepSeek Harness": "DeepSeek Harness server",
    "Demande votre attention": "Needs your attention",
    "Espaces de travail": "Workspaces",
    "Un nouvel événement — aller à la fin du journal":
        "A new event — go to the end of the journal",
    "installé": "installed",
    "absent": "absent",
    "connecté": "connected",
})

# Les formes abrégées de l'état d'une machine, sous sa vignette.
TRADUCTIONS.update({
    "DSH": "DSH",
    "DSH · hôte": "DSH · host",
    "DSH · hôte interrogé": "DSH · host queried",
})

# Les libellés du menu macOS, et l'infobulle de la vignette sur iPhone.
TRADUCTIONS.update({
    "Rafraîchir": "Refresh",
    "Rechercher une session": "Search for a session",
})

# ── L'APPAIRAGE, LA RÉINITIALISATION, ET LA FICHE D'UN SERVEUR ────────────────
#
# TRANCHE DE RATTRAPAGE, ET POURQUOI ELLE A ÉTÉ NÉCESSAIRE. Les tables `.strings`
# portaient exactement les clés qu'elles portaient : ni plus, ni moins. Une clé
# AJOUTÉE au code après la dernière écriture n'y entrait pas — et l'application,
# elle, la servait en FRANÇAIS dans une interface anglaise. Le test de parité ne
# pouvait pas le voir : il compare les deux TABLES entre elles, et toutes deux
# ignoraient la même clé. C'est `--verifier` qui l'attrape, en relisant le code —
# et il faut donc le lancer, ce que `scripts/verifier.sh` ne faisait pas.
# Le résumé d'un espace de travail (`Regroupement.texte`) : il était écrit en
# dur, et s'affichait « 1 · 1 en attente » dans l'interface anglaise ; de même
# la raison « sans écriture » du modèle.
TRADUCTIONS.update({
    "%d en attente": "%d pending",
    "%d terminée": "%d finished",
    "%d terminées": "%d finished",
    "Application": "App",
    "Protocole lu": "Protocol supported",
    "version": "version",
    "Plateforme": "Platform",
    "Politique de confidentialité": "Privacy Policy",
    "Ce jeton lit sans écrire : l'écriture demande un jeton de portée « ecriture », tiré par un harness relancé avec DSH_REMOTE_PORTEE=ecriture.":
        "This token can read but not write: writing needs a token with the « ecriture » scope, issued by a harness relaunched with DSH_REMOTE_PORTEE=ecriture.",
    "Cet hôte n'annonce pas l'écriture : cette composition ne monte pas le service qui permet d'envoyer un message.":
        "This host does not advertise writing: its setup does not include the service that sends messages.",
})

TRADUCTIONS.update({
    # L'appairage : les gestes.
    "Appairer": "Pair",
    "Appairer un appareil": "Pair a device",
    "Appairer avec ce texte": "Pair with this text",
    "Scanner le QR code": "Scan the QR code",
    "Coller un appairage": "Paste a pairing",
    "Ou renseignez le texte du QR code": "Or enter the QR code text",
    "Caméra indisponible": "Camera unavailable",
    "Serveur sélectionné": "Server selected",
    "Sélectionne cette machine ; un second appui ouvre sa page":
        "Selects this machine; a second tap opens its page",
    "Ses sessions et ses espaces de travail sont à gauche. Touchez à nouveau sa carte pour ouvrir sa page.":
        "Its sessions and workspaces are on the left. Tap its card again to open its page.",
    "Ses sessions et ses espaces de travail sont à gauche. Cliquez à nouveau sur sa carte pour ouvrir sa page.":
        "Its sessions and workspaces are on the left. Click its card again to open its page.",

    # L'appairage : ce que le panneau est, et où il est.
    "Le panneau « Appairer un appareil » de l'interface DSH affiche un QR code et le texte qui va avec : le scanner (ou le collage) remplit l'adresse ET le jeton d'un seul geste, puis se connecte.":
        "The « Appairer un appareil » panel in the DSH interface shows a QR code and its text: scanning (or pasting) fills in the address AND the token in one gesture, then connects.",
    "Le texte affiché sous le QR code commence par `dshremote://` et contient le nom du Mac. Un texte d'un autre genre est refusé, avec la raison.":
        "The text shown under the QR code starts with `dshremote://` and contains the Mac's name. Text of another kind is refused, with the reason.",
    "Rien à coller : le presse-papier est vide. Copiez le texte affiché sous le QR code du panneau « Appairer un appareil ».":
        "Nothing to paste: the clipboard is empty. Copy the text shown under the QR code in the « Appairer un appareil » panel.",
    "Ce simulateur n'a pas de caméra, ou ce modèle ne sait pas analyser un QR code en direct. Utilisez « Coller un appairage » : le texte affiché sous le QR code du panneau fait exactement la même chose.":
        "This simulator has no camera, or this model cannot read a QR code live. Use « Coller un appairage »: the text shown under the QR code in the panel does exactly the same thing.",

    # L'appairage : les refus, et ce qu'ils demandent.
    "Ce code d'appairage a expiré.": "This pairing code has expired.",
    "Ce code d'appairage n'est plus valable : il a déjà servi, ou il n'a jamais été émis.":
        "This pairing code is no longer valid: it has already been used, or it was never issued.",
    "demandez un nouveau code dans le panneau « Appairer un appareil » du Mac.":
        "ask for a new code in the Mac's « Appairer un appareil » panel.",
    "appairage refusé :": "pairing refused:",
    "cet hôte ne sait pas échanger un code d'appairage : son plugin dsh-remote est plus ancien que cette application. Mettez le plugin à jour, ou collez le jeton d'appareil à la main.":
        "this host cannot exchange a pairing code: its dsh-remote plugin is older than this app. Update the plugin, or paste the device token by hand.",
    "Cette version d'appairage n'est pas connue de cette application.":
        "This app does not know that pairing version.",
    "Ce genre d'appairage n'existe pas.": "That kind of pairing does not exist.",
    "Ce texte n'est pas une charge utile d'appairage.": "This text is not a pairing payload.",
    "Ce lien n'est pas un appairage DSH.": "This link is not a DSH pairing.",
    "Ce lien vise la boucle locale : un autre appareil ne peut pas la joindre.":
        "This link points at the loopback address: another device cannot reach it.",
    "Le nom de machine est vide ou mal formé.": "The machine name is empty or malformed.",
    "Le secret est absent, tronqué ou mal formé.": "The secret is missing, truncated or malformed.",

    # L'appairage : l'état d'une machine, et le cinquième constat du parcours.
    "à appairer": "not paired",
    "jeton refusé": "token refused",
    "Cet appareil est appairé": "This device is paired",
    "Il a son propre jeton pour cette machine : rien à recopier, jamais.":
        "It has its own token for this machine: nothing to copy, ever.",
    "Il n'a pas de jeton accepté par cette machine : la connexion serait refusée.":
        "It has no token accepted by this machine: the connection would be refused.",
    "On ne sait pas encore si cet appareil est appairé à cette machine.":
        "It is not yet known whether this device is paired with this machine.",
    "Le jeton rangé a été refusé : c'est celui d'une autre machine. Appairez à nouveau pour le remplacer.":
        "The stored token was refused: it belongs to another machine. Pair again to replace it.",
    "Jeton d'appareil de cet hôte — à la main": "Device token for this host — by hand",
    "Sur le Mac : le bouton « DSH Remote », en bas de la barre latérale — il ouvre un QR code et son texte, valables deux minutes.":
        "On the Mac: the « DSH Remote » button at the bottom of the sidebar — it opens a QR code and its text, valid for two minutes.",
    "Le bouton d'appairage est en bas de la barre latérale, sous le nom « DSH Remote ». Rechargez l'onglet : les routes du plugin s'activent à chaud, mais un bouton ajouté n'apparaît pas dans une page déjà ouverte (mesuré).":
        "The pairing button is at the bottom of the sidebar, labelled « DSH Remote ». Reload the tab: the plugin's routes come up hot, but a button added afterwards does not appear in an already-open page (measured).",

    # La fiche d'un serveur : le verdict, et le travail à faire.
    "prêt": "ready",
    "erreur": "error",
    "information": "information",
    "en attente": "pending",
    "sur le Mac": "on the Mac",
    "après l'étape": "after step",
    "Sur cet appareil, deux choses se font : que Tailscale soit connecté, et l'appairage. Tout le reste se passe sur le Mac qui héberge DSH — et l'application le vérifie toute seule, dès qu'une machine répond.":
        "Two things happen on this device: Tailscale being connected, and pairing. Everything else happens on the Mac hosting DSH — and the app checks it on its own, as soon as a machine answers.",
    "Sur le Mac qui héberge DSH — pas sur cet appareil : ouvrez une session DSH sur ce Mac, et collez-lui ceci :":
        "On the Mac hosting DSH — not on this device: open a DSH session on that Mac and paste this into it:",
    "1. Sur cette machine-là, DSH doit tourner. S'il n'y est pas — Node.js est requis :":
        "1. DSH must be running on that machine. If it is not — Node.js is required:",
    "2. Publiez ensuite son port 80 sur le tailnet :":
        "2. Then publish its port 80 on the tailnet:",
    "Et vérifiez, sur cette machine-là :": "And check, on that machine:",
    "Le plugin `dsh-remote` doit AUSSI y être chargé : publier DSH ne suffit pas. S'il manque, l'étape 4 donne sa démarche d'installation.":
        "The `dsh-remote` plugin must ALSO be loaded there: publishing DSH is not enough. If it is missing, step 4 gives the installation steps.",
    "Si vous préférez vérifier vous-même, depuis ce Mac : `401` ou `200` veut dire que le plugin répond (`401` = jeton absent, c'est normal).":
        "If you prefer to check yourself, from that Mac: `401` or `200` means the plugin is answering (`401` = no token, which is normal).",

    # La réinitialisation.
    "Réinitialiser": "Reset",
    "Réinitialiser l'application": "Reset the application",
    "Réinitialiser l'application ?": "Reset the application?",
    "Tout effacer": "Erase everything",
    "Les jetons gardés sur cet appareil seront effacés : il faudra réappairer pour retrouver l'accès. Cette action ne se défait pas.":
        "The tokens kept on this device will be erased: you will have to pair again to regain access. This action cannot be undone.",
    "Efface les jetons d'appareil gardés sur cet appareil — TOUS, y compris ceux de machines que vous ne visitez plus —, l'adresse et le nom mémorisés, les préférences par serveur, la dernière session consultée, le réglage des alertes et le fichier de diagnostic. Le jeton du harness, sur le Mac, n'est pas touché. Un fichier d'amorçage déposé à la main n'est PAS effacé : il ramènerait l'adresse et le jeton au prochain lancement, et le compte rendu le dit.":
        "Erases the device tokens kept on this device — ALL of them, including those of machines you no longer visit —, the remembered address and name, the per-server preferences, the last session opened, the alert setting and the diagnostic file. The harness token, on the Mac, is untouched. A bootstrap file placed by hand is NOT erased: it would bring the address and the token back on the next launch, and the report says so.",
    "%d jeton(s) d'appareil effacé(s)": "%d device token(s) erased",
    "%d préférence(s) oubliée(s)": "%d preference(s) forgotten",
    "aucun jeton n'était gardé": "no token was stored",
    "aucune préférence à oublier": "no preference to forget",
    "diagnostic effacé": "diagnostic erased",
})

# La CONCLUSION du diagnostic — composée de morceaux, parce qu'une phrase
# interpolée ne peut pas être une clé de table (voir `EtapesServeur.resume`).
TRADUCTIONS.update({
    "Ce serveur est prêt.": "This server is ready.",
    "Vérification en cours…": "Checking…",
    "Il reste une étape :": "One step left:",
    "Étapes restantes :": "Steps left:",
    "sur": "of",
})

# Les phrases des étapes et des messages du modèle qui étaient écrites NUES.
# Une phrase nue n'est pas une clé : elle n'entrait dans aucune table et restait
# donc en français dans une interface anglaise. Constaté à l'écran.
TRADUCTIONS.update({
    "Il doit avoir Tailscale installé et connecté : c'est ce qui le rend visible depuis cet appareil.":
        "It must have Tailscale installed and connected: that is what makes it visible from this device.",
    "Son port 80 doit être publié par `tailscale serve` — sans quoi rien ne répond à son adresse.":
        "Its port 80 must be published by `tailscale serve` — without that, nothing answers at its address.",
    "Son port 80 est publié par `tailscale serve`, donc quelque chose répond à son adresse.":
        "Its port 80 is published by `tailscale serve`, so something answers at its address.",
    "Le panneau « Appairer un appareil » du Mac affiche un QR code et son texte : ils portent l'adresse ET un code à usage unique, et remplacent les deux saisies.":
        "The Mac's « Appairer un appareil » panel shows a QR code and its text: they carry the address AND a single-use code, and replace both manual entries.",

    # Les messages du modèle — les morceaux fixes, les nombres restant interpolés.
    "aucun jeton : collez-le d'abord": "no token: paste it first",
    "jeton incomplet :": "incomplete token:",
    "caractères au lieu de 43": "characters instead of 43",
    "caractères au lieu de 43. Recopiez-le en entier.":
        "characters instead of 43. Copy it in full.",
    "est hors ligne sur le tailnet. Allumez-le, ou choisissez une machine en ligne : la liste se rafraîchit toute seule.":
        "is offline on the tailnet. Turn it on, or choose a machine that is online: the list refreshes on its own.",
    "Cet appareil n'est pas appairé à cette machine. Ouvrez sa page et prenez le QR code du panneau « Appairer un appareil » — ou, sur le Mac lui-même, recopiez le jeton que le harness n'affiche qu'une fois, au premier chargement du plugin.":
        "This device is not paired with that machine. Open its page and take the QR code from the « Appairer un appareil » panel — or, on the Mac itself, copy the token the harness shows only once, when the plugin first loads.",
})

TRADUCTIONS.update({
    "Son port 80 doit être publié par `tailscale serve` pour que quelque chose réponde à son adresse.":
        "Its port 80 must be published by `tailscale serve` for anything to answer at its address.",
})

# Les libellés d'ACTION de la fiche, et les quelques phrases qui étaient restées
# nues. Constaté à l'écran : « Reconnecter » s'affichait en français sous
# « This server is ready. » — la table ne peut pas voir un littéral qui ne lui est
# pas présenté.
TRADUCTIONS.update({
    "Se connecter": "Connect",
    "Reconnecter": "Reconnect",
    "Revérifier": "Check again",
    "Rafraîchir la liste": "Refresh the list",
    "Choisir": "Choose",
    "Ouvrir Tailscale": "Open Tailscale",
    "Installer Tailscale": "Install Tailscale",
    "Ouvrez Tailscale sur cet appareil, et connectez-le au tailnet.":
        "Open Tailscale on this device, and connect it to the tailnet.",
    "Installez Tailscale sur cet appareil, puis connectez-le au tailnet.":
        "Install Tailscale on this device, then connect it to the tailnet.",
    "Tailscale n'a pas pu être ouvert sur cet appareil.":
        "Tailscale could not be opened on this device.",
    "jeton d'appareil": "device token",
    "déjà enregistré — saisir pour remplacer": "already stored — type to replace",
    "jeton complet (43 caractères)": "complete token (43 characters)",
    "Ces deux réglages valent pour cet hôte, et s'appliquent maintenant : c'est le serveur connecté. « Chargées » veut dire prêtes à être reprises instantanément, pas en train de travailler.":
        "Both settings apply to this host, and take effect now: it is the connected server. « Loaded » means ready to be picked up instantly, not currently working.",
    "Ces deux réglages valent pour cet hôte et seront appliqués quand vous vous y connecterez.":
        "Both settings apply to this host and will take effect when you connect to it.",
})

TRADUCTIONS.update({
    "joignable": "reachable",
    "joignables": "reachable",
})

# ── Widgets (iOS & macOS) ─────────────────────────────────────────────────────
TRADUCTIONS.update({
    "(sans titre)": "(untitled)",
    "Aucune session active": "No active session",
    "Déconnecté": "Disconnected",
    "En ligne": "Online",
    "Prêt": "Ready",
    "En veille": "Standby",
    "Tout est calme": "All is quiet",
    "Touchez pour synchroniser": "Tap to sync",
    "Prêt pour la suite": "Ready for what's next",
    "Session": "Session",
    "au travail": "working",
    "session active": "active session",
    "sessions actives": "active sessions",
    "session suivie": "tracked session",
    "sessions suivies": "tracked sessions",
    "relevé": "as of",
    "DSH Remote": "DSH Remote",
    "Affiche l'état du serveur DeepSeek Harness et les sessions en cours.":
        "Displays DeepSeek Harness server status and running sessions.",
    "Projet": "Project",
    "Tour en cours": "Turn in progress",
    "événement": "event",
    "événements": "events",
    "évt": "event",
    "évts": "events",
    "à l'instant": "just now",
    "j": "d",
    "mois": "mo",
    "franchie": "done",
    "à faire": "to do",
    ", sur le Mac": ", on the Mac",
    "après l'étape %d": "after step %d",
    "Étape %d": "Step %d",
    "Journal (%d affichés)": "Journal (%d shown)",
    "%d nouveaux événements": "%d new events",
    "1 nouvel événement": "1 new event",
    "%d nouveaux événements — aller à la fin du journal": "%d new events — go to the end of the journal",
    "%d session(s) — adresse et jeton acceptés": "%d session(s) — address and token accepted",
    "aucune exception déclarée": "no exception declared",
    "1 exception déclarée": "1 exception declared",
    "%d exceptions déclarées": "%d exceptions declared",
    "réflexion :": "reasoning:",
    "(message assistant)": "(assistant message)",
    "outil": "tool",
    "(résultat d'outil)": "(tool result)",
    "(titre)": "(title)",
    "(objectif)": "(objective)",
    "preset :": "preset:",
    "bac à sable :": "sandbox:",
    "adresse invalide :": "invalid address:",
    "échec de transport :": "transport failed:",
    "réponse illisible :": "unreadable response:",
    "réponse inattendue (HTTP %d)": "unexpected response (HTTP %d)",
    "protocole incompatible : le serveur annonce la version %d, ce client sait lire la %d":
        "incompatible protocol: the server announces version %d, this client can read %d",
    "refus de l'hôte%@ : %@ (HTTP %d)": "host refused%@: %@ (HTTP %d)",
    "l'hôte n'a rien renvoyé : la liste était marquée inchangée, et ce client n'en a pas de copie":
        "the host sent nothing back: the list was marked unchanged, and this client has no copy of it",
    "Découverte automatique indisponible (%@). Saisissez l'adresse de la machine ci-dessous.":
        "Automatic discovery is unavailable (%@). Enter the machine address below.",
    "Aucune machine trouvée sur le tailnet. Vérifiez que Tailscale est connecté, puis rafraîchissez.":
        "No machine found on the tailnet. Check that Tailscale is connected, then refresh.",
    "Tailscale ne semble pas installé : installez-le, connectez-vous, puis rafraîchissez.":
        "Tailscale does not appear to be installed: install it, sign in, then refresh.",
    "Saisissez l'adresse d'une machine ci-dessous, puis connectez-vous : elle publiera ensuite la liste des machines de votre tailnet.":
        "Enter a machine address below, then connect: it will then publish the list of machines on your tailnet.",
    "jeton refusé (401) — le jeton d'appareil est absent, révoqué ou faux. Recopiez celui qu'affiche le harness, puis collez-le dans le champ « Jeton d'appareil » : sur la page de cette machine, ou dans la feuille « Adresse » quand vous saisissez une adresse à la main.":
        "token refused (401) — the device token is missing, revoked, or wrong. Copy the one the harness shows, then paste it into the “Device token” field: on this machine's page, or in the “Address” sheet when you type an address by hand.",
    "écriture refusée (403) — ce jeton autorise la lecture, pas l'écriture. Le harness a tiré un jeton en lecture seule : relancez-le avec DSH_REMOTE_PORTEE=ecriture, puis saisissez le nouveau jeton.":
        "write refused (403) — this token can read, not write. The harness issued a read-only token: relaunch it with DSH_REMOTE_PORTEE=ecriture, then enter the new token.",
})

if __name__ == "__main__":
    raise SystemExit(main())
