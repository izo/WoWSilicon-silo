---
title: Design — WoWSilicon
project: WoWSilicon
tags: [design, source-of-truth, ulk, macos, liquid-glass]
updated: 2026-10-11
owner: coloriste
contributors: [jony]
direction: "atelier de lancement — outil sobre, laiton sur verre"
philosophy_falsifiable: true
brand_type: ui-rich
platform: macOS 26 uniquement (Liquid Glass), aucun repli macOS 14/15
modes: [light, dark]
a11y_target: AA
hig_vault: "ulk-appledesign, capture 2026-09-15 (hig-ask)"
---

# Design — WoWSilicon

Launcher macOS pour anciens clients World of Warcraft (Vanilla 1.12.1, TBC 2.4.3,
WotLK 3.3.5a) et profils « Non-WoW » Direct3D 9, sur Mac Apple Silicon, via un
runtime Wine embarqué. Ce fichier est la **source de vérité** du design. Le code
s'aligne sur lui, jamais l'inverse.

> [!info] Portée de la v1 (2026-10-11)
> Design system complet + refonte de la fenêtre principale. Cible **macOS 26
> uniquement**, matériau **Liquid Glass**. Aucun rendu de repli pour macOS 14/15 :
> le relèvement du déploiement minimal est une décision à confirmer côté
> implémentation (voir [[design-wireframe/main-window/CARD|Spec Card]] § Brief isaac).

## Philosophie

> [!info] Tension design
> 1. **Un outil, pas une affiche.** La fenêtre sert à savoir en une seconde si le
>    profil est prêt, puis à lancer. Aucune surface n'est consacrée à la promotion
>    de l'app (icône géante, slogan, numéro de version en vedette). *Falsifiable :
>    si un élément de la fenêtre principale n'aide ni à choisir un profil, ni à le
>    rendre prêt, ni à le lancer, il sort de la fenêtre.*
> 2. **Le verre appartient au système, le contenu reste mat.** Liquid Glass habille
>    uniquement la barre d'outils et la barre latérale, fournies par le système.
>    Aucun composant maison n'est en verre. *Falsifiable : un `.glassEffect` posé
>    à la main dans la zone de détail est un défaut.*
> 3. **Une seule couleur de marque, et une seule fonction pour elle.** Le laiton
>    (accent) marque l'action principale et la sélection. Les états (prêt, à faire,
>    erreur) passent par les couleurs système **et** un symbole **et** un texte.
>    *Falsifiable : du laiton sur un élément non actionnable, ou un état signalé par
>    la seule couleur, est un défaut.*
> 4. **Clair et sombre sont deux dessins.** Le sombre n'est pas l'inverse du clair :
>    les cartes perdent leur filet en sombre, la teinte du bouton Lancer passe du
>    laiton profond au laiton lumineux, et le libellé suit le système
>    (`.borderedProminent`), sans couleur figée.

### Ce que l'état actuel (`docs/assets/launcher-preview.png`) enseigne

Jugé, pas recopié. Chaque défaut ci-dessous fonde une décision de la v1.

| Constat sur l'existant | Règle HIG | Décision v1 |
|---|---|---|
| Icône 160 px, pastille de version, slogan en italique occupent la moitié haute de la fenêtre | `launching-005` (Downplay the launch experience), `launching-008` (Don't advertise) | Supprimés de la fenêtre. Version dans « À propos » et le menu app. |
| Le sélecteur de profil est déguisé en titre (« WoWSilicon ⌄ ») + bouton « + » isolé | `pop-up-buttons-003` (Give people a way to predict a pop-up button's options) | Les profils deviennent une **barre latérale** visible en permanence. |
| Fond en dégradé bleu/jaune derrière des contrôles, bouton Play en dégradé | `color-013`, `buttons-005`, `toolbars-005` | Fond système mat, accent uni. |
| « Applied » et le chemin en texte vert sur blanc : contraste mesuré **2,22:1** (`#34C759` sur `#FFFFFF`) | `accessibility-004` (4,5:1 jusqu'à 17 pt), `color-007` | Texte toujours en couleur d'étiquette ; la couleur passe sur le symbole. |
| « Wine idle » en gris pâle | `accessibility-004` | Statut runtime en sous-titre de fenêtre, `secondaryLabel`. |
| Options / Troubleshooting / Addons / Mods / Play alignés en bas de fenêtre | `layout-013`, `windows-009` (Avoid … critical actions in a bottom bar) | Outils en haut (barre d'outils), Lancer dans l'en-tête du détail. |
| Boutons Patch (désactivé) + Unpatch côte à côte | `layout-004` (progressive disclosure) | Une seule action contextuelle par ligne d'état. |
| Pilules maison fond blanc / texte noir | `buttons-028` | Boutons système (`.bordered`, `.borderedProminent`). |
| Fenêtre de taille fixe | `windows-001`, `layout-020` (In general, support resizing) | Fenêtre redimensionnable, tailles mini définies. |

> [!warning] Icône de marque — incohérence à trancher
> Le brief désigne une tortue ; le fichier
> `Sources/WoWSiliconSwift/Resources/Icons/turtlesilicon_icon.png` montre **trois
> engrenages laiton sur carré bleu roi** (héritage TurtleSilicon). La palette de
> marque ci-dessous dérive de ce fichier (bleu roi + laiton). La refonte de l'icône
> au format Liquid Glass (Icon Composer, couches, variantes sombre/teintée —
> `app-icons-001`, `app-icons-015`, `app-icons-016`) est **hors périmètre v1**.

## Tokens

Convention : un token pointe d'abord vers un **nom système** (SwiftUI / AppKit).
Les hex ne sont que des **aperçus** pour le canvas `/design` : le code n'en code
aucun en dur pour une couleur système (`color-010`). Seuls les tokens de marque
(`accent.*`) portent une valeur propre, dans l'Asset Catalog avec variantes
clair / sombre / contraste élevé (`color-002`).

Colonne **HIG** : id de règle renvoyé par `hig-ask` (vault capturé le 2026-09-15).
« choix maison » = aucune règle du vault ne fixe cette valeur.

### Couleur — marque

| Token | Clair | Sombre | Usage | HIG |
|---|---|---|---|---|
| `accent.fill` | `#8C6A1C` laiton profond | `#D9B65C` laiton lumineux | Fond du bouton Lancer, sélection, contrôles actifs | `branding-002`, `color-012` |
| `accent.onFill` | Libellé système (`.borderedProminent`) ; `#FFFFFF` à titre de référence (5,01:1 sur `#8C6A1C`) | Libellé système ; `#1C1606` à titre de référence (9,25:1 sur `#D9B65C`) | Libellé posé sur `accent.fill` quand l'accent est le laiton. Pas de couleur de libellé figée | `accessibility-004` |
| `accent.fill.highContrast` | `#7A5C14` (6,23:1 avec blanc) | `#E3C26A` (10,45:1 avec encre) | Variante « Augmenter le contraste » | `color-002` |
| `brand.cobalt` | `#1F4FA0` | `#1F4FA0` | Réservé à l'icône d'app et à « À propos ». Jamais dans l'UI. | choix maison |

> [!note] Accent système
> Si l'utilisateur choisit une couleur d'accentuation autre que « multicolore »
> dans Réglages Système, macOS remplace le laiton partout (comportement documenté
> page Color › macOS › App accent colors). Le design doit tenir avec l'accent
> bleu, graphite, etc. Le libellé de Lancer suit alors le système. Aucune promesse
> de rendu identique hors multicolore : l'artboard `Main-Light-Ready-GraphiteAccent`
> reste à produire et à vérifier.

### Couleur — sémantique (système, aucune valeur en dur)

| Token | Nom système | Aperçu clair | Aperçu sombre | Usage | HIG |
|---|---|---|---|---|---|
| `bg.window` | `windowBackgroundColor` | `#ECECEC` | `#1E1E1E` | Fond de la zone de détail | `color-010`, `materials-001` |
| `bg.group` | `controlBackgroundColor` (`Form` `.grouped`) | `#FFFFFF` | `#2A2A2C` | Cartes de section | `color-010` |
| `text.primary` | `labelColor` | `#000000 @85 %` | `#FFFFFF @85 %` | Titres, valeurs | `accessibility-005` |
| `text.secondary` | `secondaryLabelColor` | `#000000 @50 %` | `#FFFFFF @55 %` | Libellés non critiques, sous-titre de fenêtre. ≈ 3,9:1 en clair : **jamais** d'information critique (état, raison de blocage, valeur) | `accessibility-004`, `accessibility-005` |
| `text.tertiary` | `tertiaryLabelColor` | `#000000 @26 %` | `#FFFFFF @25 %` | Indices non essentiels uniquement | `accessibility-004` |
| `separator` | `separatorColor` | `#000000 @10 %` | `#FFFFFF @10 %` | Filets entre lignes de section | `color-010` |
| `status.ready` | `systemGreen` | `#34C759` | `#30D158` | **Symbole** `checkmark.circle.fill` uniquement | `color-007`, `color-011` |
| `status.action` | `systemOrange` | `#FF9500` | `#FF9F0A` | **Symbole** `exclamationmark.circle.fill` (patch requis, runtime absent) | `color-007`, `color-011` |
| `status.error` | `systemRed` | `#FF3B30` | `#FF453A` | **Symbole** `xmark.octagon.fill` + texte d'explication | `color-007`, `feedback-006` |

Règle : **un état = symbole coloré + texte en `text.primary`**. Jamais de texte
coloré pour porter un état (`color-007`, `accessibility-006`).

### Matériaux

| Token | Valeur | Où | HIG |
|---|---|---|---|
| `material.chrome` | Liquid Glass **regular**, fourni par le système | Barre d'outils, barre latérale (`NavigationSplitView`), popovers, menus | `materials-002`, `materials-003` |
| `material.content` | Aucun verre ; `bg.window` mat | Toute la zone de détail, cartes, listes d'addons | `materials-001` |
| `material.clear` | **Non utilisé** | — (aucun fond visuellement riche dans l'app) | `materials-003` |
| `material.custom` | **Interdit** sur composants maison | — | `materials-002` |
| `effect.scrollEdge` | Automatique (système) | Bord haut du détail sous la barre d'outils | `scroll-views-007`, `scroll-views-008`, `scroll-views-009` |
| `effect.vibrancy` | Couleurs d'étiquette système sur verre | Libellés de la barre latérale | `materials-005` |
| `chrome.tint` | **Aucune teinte** sur la barre d'outils ; seul Lancer est coloré | Barre d'outils monochrome | `toolbars-004`, `color-012`, `color-013` |

> [!note] Accessibilité du verre
> « Réduire la transparence » et « Augmenter le contraste » modifient le rendu du
> verre (page Materials › Liquid Glass). Aucun contenu ne doit dépendre de la
> transparence : un artboard de contrôle par mode est demandé au canvas.

### Typographie — SF Pro, styles intégrés macOS

Source des tailles : tableau *macOS built-in text styles* (page Typography ›
Specifications). Pas de Dynamic Type sur macOS. Une seule famille (SF Pro + SF Mono).

| Token | Style système | Taille / interligne (pt) | Graisse | Usage | HIG |
|---|---|---|---|---|---|
| `type.profileTitle` | Large Title | 26 / 32 | Bold (emphasized) | Nom du profil, en-tête du détail | `typography-009`, `typography-004` |
| `type.sectionTitle` | Headline | 13 / 16 | Bold | Titres de section (« État », « Lancement ») | `typography-009` |
| `type.body` | Body | 13 / 16 | Regular | Lignes d'état, valeurs | `typography-009`, `typography-001` |
| `type.bodyEmph` | Body emphasized | 13 / 16 | Semibold | Valeur d'état (« Patch appliqué ») | `typography-004` |
| `type.secondary` | Callout | 12 / 15 | Regular | Explications sous une ligne, chemin du dossier | `typography-009` |
| `type.sidebarHeader` | Subheadline | 11 / 14 | Semibold | En-têtes de groupe de la barre latérale | `typography-019` |
| `type.badge` | Caption 2 | 10 / 13 | Semibold | Badge de version (« 3.3.5a ») | `typography-009` |
| `type.mono` | SF Mono, Callout | 12 / 15 | Regular | Chemins, realmlist, variables d'environnement | choix maison |

Interdits : graisses Light/Thin (`typography-003`), italique décoratif (choix
maison), troisième famille (`typography-005`).

### Espacement — grille 4 pt

| Token | Valeur | Usage | HIG |
|---|---|---|---|
| `space.1` | 4 | Symbole ↔ texte serré | `layout-018` |
| `space.2` | 8 | Entre contrôles d'un même groupe | `layout-018` |
| `space.3` | 12 | Autour des éléments à bordure | `accessibility-012` |
| `space.4` | 16 | Marge interne des cartes | `layout-018` |
| `space.5` | 20 | Marge latérale du détail | choix maison |
| `space.6` | 24 | Entre sections ; autour des éléments sans bordure | `accessibility-012`, `layout-017` |
| `space.8` | 32 | Sous l'en-tête du profil | choix maison |

### Dimensions

| Token | Valeur | HIG |
|---|---|---|
| `size.control.min` | 20 × 20 pt (mini macOS) | `accessibility-011` |
| `size.control.default` | 28 pt de haut | `accessibility-011` |
| `size.launch` | `.controlSize(.extraLarge)`, ≥ 44 pt de haut, ≥ 140 pt de large | `buttons-003`, `buttons-004` |
| `size.sidebar` | 220 pt (min 200, max 280) | `split-views-005` |
| `size.window.min` | 760 × 520 pt | `windows-001`, `layout-020` |
| `size.window.default` | 960 × 620 pt | choix maison (`windows-012` ne vaut que pour visionOS) |
| `size.detail.maxReadable` | 720 pt de contenu, centré au-delà | choix maison |
| `size.profileGlyph` | 28 × 28 pt (ligne de barre latérale) | choix maison |

### Rayons

| Token | Valeur | HIG |
|---|---|---|
| `radius.window` | Système (macOS 26) — jamais redessiné | `windows-008` |
| `radius.control` | Système : capsule pour boutons | `buttons-029` |
| `radius.glyph` | 7 pt (glyphe de profil 28 pt) | choix maison |

### Mouvement

| Token | Valeur | HIG |
|---|---|---|
| `motion.state` | Fondu 0,2 s (`.easeOut`) au changement d'état d'une ligne | `motion-001` |
| `motion.launch` | Bouton Lancer → « En cours » : transition de contenu du symbole (`.contentTransition(.symbolEffect)`) | `sf-symbols-004` |
| `motion.reduce` | « Réduire les animations » : coupe fondus et effets de symbole, garde les changements d'état | `motion-002` |
| `motion.none` | Aucune animation sur la sélection de profil (fréquente) | `motion-005` |

### Iconographie

| Token | Valeur | HIG |
|---|---|---|
| `icon.set` | SF Symbols uniquement dans l'UI | `dark-mode-008`, `buttons-007` |
| `icon.rendering` | Hiérarchique pour les états, monochrome dans la barre d'outils | `sf-symbols-001` |
| `icon.profile` | Glyphe maison : carré 28 pt, `bg.group`, numéro de version court (« 1.12 », « 2.4 », « 3.3 », « D3D9 ») en `type.badge`. **Monochrome** : aucune couleur par extension (évite le conflit avec les verts/oranges d'état) | `color-001`, `sidebars-008` |

## Composants (index)

Décrits en détail dans [[design-wireframe/main-window/CARD|Spec Card — fenêtre principale]].

| Composant | Base système | Matériau | Règles clés |
|---|---|---|---|
| `ProfileSidebar` | `NavigationSplitView` sidebar + `List(selection:)` | Glass (système) | `sidebars-005`, `sidebars-006`, `sidebars-012`, `split-views-001` |
| `ProfileRow` | `Label` + glyphe + sous-titre d'état | Glass (système) | `lists-and-tables-004`, `sidebars-004` |
| `MainToolbar` | `.toolbar` : sélecteur de vue (segmenté), groupe d'outils | Glass (système) | `toolbars-001`, `toolbars-016`, `toolbars-024` |
| `ProfileHeader` | Titre + chemin + `LaunchButton` | Mat | `layout-001`, `buttons-003` |
| `LaunchButton` | `Button` `.borderedProminent`, `.extraLarge` | Mat (contenu) — **pas de verre** | `buttons-003`, `buttons-009`, `buttons-011`, `materials-001` |
| `ReadinessSection` | `Form` `.grouped`, 4 `StatusRow` | Mat | `feedback-002`, `layout-003` |
| `StatusRow` | Symbole d'état + libellé + valeur + 1 action | Mat | `color-007`, `buttons-013`, `progress-indicators-001` |
| `EmptyState` | `ContentUnavailableView` + zone de dépôt | Mat | `writing-012`, `drag-and-drop-001`, `drag-and-drop-010` |
| `AddonsView` / `ModsView` / `RealmlistView` | `Table` / `List` / éditeur | Mat | `lists-and-tables-001`, `lists-and-tables-012` |
| `SettingsWindow` | `Settings { TabView }` : Général · Graphismes · Dépannage | Barre d'outils système | `settings-009`, `settings-011`, `settings-013` |

## Pages (index)

- [[design-wireframe/main-window/CARD|Fenêtre principale]] · status: draft

## Thèmes — clair et sombre, dessinés séparément

| Aspect | Clair | Sombre | HIG |
|---|---|---|---|
| Fond du détail | `bg.window` gris clair, cartes blanches **avec** filet `separator` | `bg.window` anthracite, cartes `bg.group` **sans** filet, l'écart de valeur suffit | `dark-mode-002`, `dark-mode-007` |
| Bouton Lancer | Laiton profond `#8C6A1C` (multicolore), libellé système | Laiton lumineux `#D9B65C` (multicolore), libellé système | `dark-mode-006`, `accessibility-004` |
| Ombre du bouton Lancer | Aucune | Aucune (pas de halo lumineux) | choix maison |
| Symboles d'état | Variantes claires système | Variantes sombres système | `dark-mode-005` |
| Glyphe de profil | Fond blanc, chiffres `text.secondary` | Fond `#3A3A3C`, chiffres `text.primary` | `dark-mode-003` |
| Barre latérale | Verre clair, la sélection prend l'accent | Verre sombre, idem | `materials-003` |

Aucun réglage d'apparence propre à l'app : on suit le système (`dark-mode-001`).

## Raccourcis clavier et menus (native feel)

Chaque élément de la barre d'outils existe dans la barre de menus (`toolbars-024`).
Raccourcis standard respectés (`keyboards-002`, `keyboards-003`).

| Action | Menu | Raccourci |
|---|---|---|
| Lancer le profil sélectionné | Profil › Lancer | ⌘↩ |
| Nouveau profil (choisir un dossier de jeu) | Fichier › Nouveau profil… | ⌘N |
| Afficher le dossier de jeu dans le Finder | Profil › Afficher dans le Finder | ⇧⌘R |
| Aperçu / Addons / Mods / Realmlist | Présentation | ⌘1 / ⌘2 / ⌘3 / ⌘4 |
| Afficher / masquer la barre latérale | Présentation | ⌃⌘S (standard) |
| Réglages… | WoWSilicon | ⌘, |
| Rechercher les mises à jour… | WoWSilicon | — |
| Profil précédent / suivant | — | ↑ / ↓ dans la barre latérale |

Glisser-déposer : un dossier de jeu déposé sur la barre latérale ou l'état vide
crée un profil (`drag-and-drop-001`, `drag-and-drop-010`) ; un addon `.zip` ou une URL Git déposés sur
la vue Addons l'installent.

## Anti-patterns

1. Liquid Glass sur un composant maison ou dans la zone de détail (`materials-001`, `materials-002`).
2. Texte coloré pour porter un état (« Applied » en vert) — `color-007`.
3. Dégradé sur un fond de fenêtre ou sur un bouton (`color-013`, `buttons-005`).
4. Action principale ou outil en bas de fenêtre (`layout-013`, `windows-009`).
5. Icône d'app, slogan ou numéro de version mis en scène dans la fenêtre principale (`launching-008`).
6. Deux boutons proéminents visibles en même temps (`buttons-003`, `buttons-004`).
7. Bouton « Patch » désactivé à côté de « Unpatch » : une seule action, celle qui a du sens (`layout-004`).
8. Pilules maison fond blanc / texte noir (`buttons-028`).
9. Couleur par extension (Vanilla, TBC, WotLK) : collision avec les couleurs d'état (`color-001`).
10. Hex de couleur système codé en dur dans le code (`color-010`).
11. Alerte de confirmation pour retirer le patch (action réversible) — `alerts-003`.
12. Interrupteur « Thème clair / sombre » dans les réglages (`dark-mode-001`).
13. Indicateur rotatif avec libellé (`progress-indicators-013`) ; un téléchargement de runtime est **déterminé** (`progress-indicators-001`).
14. Information critique en `text.secondary` (≈ 3,9:1 en clair, sous le seuil de 4,5:1 de `accessibility-004`).
15. Couleur de libellé figée sur le bouton Lancer, qui casse dès que l'accent système change.

## Audit findings (rolling)

> [!warning] jony — 2026-10-11 — passe `impeccable` (critique + audit) sur la v1
> Verdict et corrections appliquées : voir [[design-wireframe/main-window/CARD|Spec Card]] § Verdict impeccable.

## Changelog

- 2026-10-11 · jony · Passe impeccable (Assessment A 25/40, détecteur non concluant) : états d'erreur ajoutés à la CARD, libellé de Lancer rendu au système, `text.secondary` retiré des informations critiques, `type.launch` et `radius.card` retirés, `status.idle` et `status.running` retirés, anti-patterns 14 et 15 ajoutés.
- 2026-10-11 · jony · Création du design system v1 : macOS 26 uniquement, Liquid Glass réservé au chrome système, accent laiton (clair `#8C6A1C` / sombre `#D9B65C`), états symbole + texte, typo SF macOS intégrée, fenêtre principale refondue en `NavigationSplitView` redimensionnable (profils en barre latérale, Lancer en en-tête). Rejet documenté de la mise en page de `launcher-preview.png`.
