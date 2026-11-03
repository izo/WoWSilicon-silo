# Décisions

## ADR-001 — macOS 26 minimum (#34)

- **Date** : 2026-11-03
- **Décision** : WoWSilicon cible macOS 26 uniquement. Le `MACOSX_DEPLOYMENT_TARGET` passera de 14.0 à 26.0 (Xcode et `Package.swift`) au lot 1 de la refonte.
- **Alternatives écartées** : macOS 14 avec SDK 26 (recommandation de l'audit jony : aucun utilisateur perdu, Liquid Glass via les composants système) ; macOS 15.
- **Conséquences** : les utilisateurs sur macOS 14 et 15 ne recevront plus de mise à jour ; les API macOS 26 (Liquid Glass, `glassEffect`, nouveaux styles de barre d'outils) sont utilisables sans `#available`.

## ADR-002 — Identité sobre, icône à engrenages (#36, #37)

- **Date** : 2026-11-03
- **Décision** : interface sobre. La signature visuelle tient en trois points : l'icône, le bouton Lancer en laiton et ses états, les glyphes de profil. L'icône est refaite dans Icon Composer (engrenages laiton sur cobalt, variantes clair, sombre, teintée). Toute trace de tortue est retirée (`turtle.icns`, `APPICON_NAME = turtle`, symbole `tortoise.fill`, changement d'icône du Dock à l'exécution).
- **Alternatives écartées** : direction « fantasy » (risque de marque Blizzard, bruit visuel) ; garder l'existant.

## ADR-003 — Options rangées en trois portées (#38)

- **Date** : 2026-11-03
- **Décision** : par profil (graphismes, audio, x87, environnement, lanceur) dans une vue Profil de la fenêtre principale ; par bouteille Wine (bouteille, Retina, Option → Alt, winecfg) dans Réglages › Wine ; global (mises à jour, statistiques, dépendances, dépannage) dans les autres onglets de Réglages (⌘,).
- **Alternative écartée** : tout dans Réglages avec un sélecteur de profil (proche du défaut actuel).

## ADR-004 — Guide UI AuDHD appliqué

- **Date** : 2026-11-03
- **Décision** : la refonte applique le guide AuDHD (`tierces-design:audhd-ui-guide`) : charge cognitive réduite, états toujours explicites (symbole + texte), peu d'interruptions, pas d'animation en boucle, respect de « Réduire les animations ».
