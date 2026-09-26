# Privacy Policy — DSH Remote Companion

*Last updated: September 26, 2026*

DSH Remote Companion ("the app") is an open-source companion for DeepSeek Harness (DSH), available for iPhone, iPad and Mac. This policy explains what the app does with your data. The short version: **it collects nothing.**

## Data we collect

None. The app has no account system, no analytics, no advertising, no crash-reporting SDK and no tracking of any kind. The developer operates no server that receives data from the app.

## How the app communicates

The app connects **only to the DSH host you pair it with** — a computer you run yourself, reached over your local network or your private Tailscale network. Session content (messages, tool calls, file names, token counts) travels directly between your device and your own computer. It never passes through a third-party service operated by the developer.

## Data stored on your device

- **Device token**: issued by your DSH host at pairing, stored in the Apple Keychain. It never leaves your device except to authenticate to your own host.
- **Preferences** (remembered host address, display options): stored locally in the app's settings.
- **Widget snapshots**: a short summary of session status, shared between the app and its widgets through an App Group on the same device. It contains no token.

Deleting the app removes all of this data. You can also revoke a device's token at any time from the DSH web panel.

## Camera

The camera is used only to scan the pairing QR code displayed by DSH. No image is saved or transmitted.

## Notifications

Local notifications (for example, "a session is waiting for your answer") are generated on your device from the data your own host sends. No push-notification service operated by the developer is involved.

## Children

The app is a developer tool and is not directed at children.

## Changes

Changes to this policy are published in this file, in the project's public repository.

## Contact

Please open an issue on the project's GitHub repository: <https://github.com/VISIALIS/dsh-remote/issues>.

---

# Politique de confidentialité — DSH Remote Companion

*Dernière mise à jour : 26 septembre 2026*

DSH Remote Companion (« l'app ») est un compagnon open source de DeepSeek Harness (DSH) pour iPhone, iPad et Mac. **L'app ne collecte aucune donnée.**

- **Aucune collecte** : ni compte, ni statistiques, ni publicité, ni outil de rapport de plantage, ni pistage. Le développeur n'exploite aucun serveur recevant des données de l'app.
- **Communications** : l'app ne se connecte qu'à l'hôte DSH que vous avez appairé — votre propre ordinateur, joint par votre réseau local ou votre réseau privé Tailscale. Le contenu des sessions ne transite par aucun service tiers du développeur.
- **Stockage local** : le jeton d'appareil est rangé dans le trousseau Apple ; les préférences et un résumé d'état destiné aux widgets restent sur l'appareil. Supprimer l'app efface ces données ; le jeton peut aussi être révoqué depuis le panneau web de DSH.
- **Caméra** : utilisée uniquement pour scanner le QR code d'appairage ; aucune image n'est enregistrée ni transmise.
- **Notifications** : locales, produites sur l'appareil à partir des données de votre propre hôte.
- **Contact** : ouvrez un ticket sur <https://github.com/VISIALIS/dsh-remote/issues>.
