// DÉCODEUR QR INDÉPENDANT — outil de TEST, pas de production.
//
// POURQUOI IL EXISTE. Un encodeur QR éprouvé par lui-même ne prouve rien : une
// matrice peut être cohérente avec son propre code et illisible pour tout le
// monde. Ce décodeur ne partage AUCUNE ligne avec l'encodeur du dépôt — c'est
// Vision, le framework d'Apple — et il rend la charge utile qu'il lit.
//
// C'est la même méthode qui a validé l'encodeur de `share-qr` (décodage par
// Vision/macOS) avant que ce plugin ne quitte le dépôt, appliquée ici à la COPIE
// EMBARQUÉE dans le bundle du panneau.
//
// Usage : swift decoder-qr.swift <fichier.bmp>
// Sortie : une ligne par code trouvé (la charge utile), exit 3 si aucun code.

import Foundation
import Vision
import ImageIO

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
  FileHandle.standardError.write(Data("usage: decoder-qr.swift <image>\n".utf8))
  exit(1)
}

let adresse = URL(fileURLWithPath: arguments[1])
guard let source = CGImageSourceCreateWithURL(adresse as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
  FileHandle.standardError.write(Data("image illisible\n".utf8))
  exit(2)
}

let requete = VNDetectBarcodesRequest()
requete.symbologies = [.qr]

do {
  try VNImageRequestHandler(cgImage: image, options: [:]).perform([requete])
} catch {
  FileHandle.standardError.write(Data("analyse impossible: \(error)\n".utf8))
  exit(2)
}

let observations = requete.results ?? []
if observations.isEmpty {
  FileHandle.standardError.write(Data("aucun code detecte\n".utf8))
  exit(3)
}

for observation in observations {
  print(observation.payloadStringValue ?? "")
}
