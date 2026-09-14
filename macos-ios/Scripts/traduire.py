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

SOURCES = pathlib.Path(__file__).resolve().parents[1] / "Sources"
SOURCE = SOURCES / "DSHRemoteKit"
RESSOURCES = SOURCE / "Ressources"
# LES LIBELLÉS DU MENU macOS VIVENT DANS LA CIBLE DE L'APPLICATION, et ils sont
# localisés comme les autres : les oublier ici laissait le menu en français dans
# une application anglaise, sans que rien ne le signale.
DOSSIERS_DE_CODE = [SOURCE, SOURCES / "DSHRemoteApp"]
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
    "1. Avoir le dépôt `dsh-plugins` sur cette machine, et y prendre `plugins/dsh-remote`.":
        "1. Have the `dsh-plugins` repository on that machine, and take `plugins/dsh-remote` from it.",
    "2. Déclarer le plugin dans `~/.dsh/profiles/web/cordis.patch.yml` :":
        "2. Declare the plugin in `~/.dsh/profiles/web/cordis.patch.yml`:",
    "3. Relancer le harness sur cette machine — ici `dsh web`. Le CODE d'un plugin n'est pas rechargé à chaud : sans redémarrage, l'ancien processus continue de répondre.":
        "3. Restart the harness on that machine — here, `dsh web`. A plugin's CODE is not hot-reloaded: without a restart, the old process keeps answering.",
    "Le plugin `dsh-remote` n'est pas installé sur cette machine. DSH y tourne et son port 80 est publié — mais rien n'y expose DSH Remote.":
        "The `dsh-remote` plugin is not installed on that machine. DSH runs there and its port 80 is published — but nothing there serves DSH Remote.",
    "Le plugin `dsh-remote` doit AUSSI y être chargé : publier DSH ne suffit pas. S'il manque, la page de cette machine donnera sa démarche d'installation.":
        "The `dsh-remote` plugin must ALSO be loaded there: publishing DSH is not enough. If it is missing, that machine's page gives the installation steps.",
    "Aucun service n'écoute sur le port 80 de cette machine. Le tailnet, lui, fonctionne : la machine répond.":
        "No service is listening on that machine's port 80. The tailnet itself works: the machine answers.",
    "Vérifiez sur cette machine : `401` ou `200` veut dire que le plugin répond (`401` = jeton absent, c'est normal).":
        "Check on that machine: `401` or `200` means the plugin is answering (`401` = no token, which is normal).",
    "Le jeton n'est pas en cause ici : rien n'a pu être joint. Attention, il est PROPRE À CHAQUE HÔTE — celui de cette machine ne vaudra pas pour un autre.":
        "The token is not what failed here: nothing could be reached. Note that it is SPECIFIC TO EACH HOST — this machine's token will not work for another.",
    "Sur cette machine-là, publiez l'instance DSH :":
        "On that machine, publish the DSH instance:",
    "Vérifiez ensuite, sur cette machine-là :":
        "Then check, on that machine:",

    # ── Adresse et jeton ──────────────────────────────────────────────────────
    "Adresse": "Address",
    "Adresse de la machine": "Machine address",
    "Jeton d'appareil": "Device token",
    "Jeton d'appareil de cet hôte": "Device token for this host",
    "Le coffre du harness de cette machine contient un AUTRE jeton.":
        "The harness vault on that machine holds a DIFFERENT token.",
    "Il s'affiche une seule fois, dans la sortie du harness, au premier chargement du plugin sur cette machine. Il est gardé au trousseau — jamais dans les préférences — et n'est jamais renvoyé par une route.":
        "It is shown only once, in the harness output, when the plugin first loads on that machine. It is kept in the keychain — never in the preferences — and is never returned by a route.",
    "Il s'affiche une seule fois, dans la sortie du harness, au premier chargement du plugin sur cette machine. Il n'est jamais renvoyé par une route.":
        "It is shown only once, in the harness output, when the plugin first loads on that machine. It is never returned by a route.",
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
    "Sur cette machine-là : installez Tailscale, connectez-le, puis vérifiez :":
        "On that machine: install Tailscale, connect it, then check:",
    "Il doit y apparaître en ligne, avec un nom en `.ts.net`.":
        "It should appear there online, with a name ending in `.ts.net`.",
    "Une machine devient un serveur DSH en quatre étapes. Elles se font dans cet ordre : chacune suppose la précédente.":
        "A machine becomes a DSH server in four steps. They are done in this order: each assumes the previous one.",
    "L'ordre est celui du travail : chaque étape suppose la précédente. Les étapes grisées restent lisibles — dépliez « Voir la méthode » si vous les avez déjà faites, ou pour savoir ce qui vous attend.":
        "The order is the order of the work: each step assumes the previous one. Greyed steps stay readable — unfold “See the method” if you have already done them, or to see what awaits you.",
    "Ajouter un serveur": "Add a server",
    "Chercher une machine": "Find a machine",
    "Saisir une adresse": "Enter an address",
    "à vérifier": "to check",
    "serveur courant": "current server",
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
    "Ouvre la page de cette machine": "Opens this machine's page",
})

if __name__ == "__main__":
    raise SystemExit(main())