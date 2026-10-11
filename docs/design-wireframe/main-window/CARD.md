---
title: Fenêtre principale — WoWSilicon
slug: main-window
type: page
status: draft
parents: []
children: [ProfileSidebar, ProfileRow, MainToolbar, ProfileHeader, LaunchButton, ReadinessSection, StatusRow, EmptyState, SettingsWindow]
tokens_used: [accent.fill, accent.onFill, bg.window, bg.group, text.primary, text.secondary, separator, status.ready, status.action, status.error, material.chrome, material.content, type.profileTitle, type.sectionTitle, type.body, type.secondary, type.mono, type.launch, space.4, space.6, radius.card, size.sidebar, size.window.min, size.launch]
canvas: "à produire — /design non lancé"
updated: 2026-10-11
owner: jony
---

# Fenêtre principale

> [!note] Slug
> Le dossier s'appelle `main-window` à la demande de l'utilisateur ; la convention
> ulk voudrait `page-main-window`. Renommage possible plus tard, sans effet sur le contenu.

## Intention

Choisir un profil (un dossier de jeu), voir en une ligne par prérequis s'il est
prêt, corriger ce qui manque à l'endroit où le manque est signalé, puis lancer.
Les outils du profil (addons, mods DLL, realmlist) sont à un clic, en haut. Les
réglages globaux (graphismes, mises à jour, dépannage) vivent dans la fenêtre
Réglages (⌘,), pas dans la fenêtre principale (`settings-003`, `settings-009`).

## Structure

`NavigationSplitView` à deux colonnes, fenêtre **redimensionnable**.

- Justification du redimensionnement : la liste d'addons et l'éditeur de realmlist
  ont besoin de largeur, et un profil par client multiplie les lignes de la barre
  latérale (`windows-001`, `layout-020`). Mini 760 × 520, défaut 960 × 620.
- Barre de titre : style unifié système, feux tricolores intégrés au verre de la
  barre latérale (`windows-006`, `windows-008`). Fini le `hiddenTitleBar` : le
  titre de fenêtre = nom du profil, sous-titre = état du runtime
  (`toolbars-008`).
- Sous 820 pt de large, la barre latérale se replie automatiquement (`sidebars-011`).

## Wireframe ASCII — clair, profil prêt

```
┌──────────────────────┬──────────────────────────────────────────────────────────┐
│ ● ● ●            [⊞] │ WotLK 3.3.5a        [ Aperçu|Addons|Mods|Realmlist ]  ⚙︎  │ ← verre (système)
│                      │ Runtime Wine prêt                                         │
│ WORLD OF WARCRAFT    ├──────────────────────────────────────────────────────────┤
│ ┌──┐ Vanilla 1.12.1  │                                                          │
│ │1.12 Prêt           │  WotLK 3.3.5a                         ┌──────────────┐   │
│ └──┘                 │  ~/Games/WotLK  ↗                      │  ▶  Lancer   │   │ ← accent.fill
│ ┌──┐ TBC 2.4.3       │                                        └──────────────┘   │
│ │2.4 Patch requis    │                                                          │
│ └──┘                 │  ÉTAT                                                     │
│▐┌──┐ WotLK 3.3.5a   ▌│  ┌────────────────────────────────────────────────────┐  │
│▐│3.3 Prêt           ▌│  │ ✓ Dossier de jeu   WoW.exe trouvé      Changer…   │  │
│▐└──┘                ▌│  │ ✓ Patch            Appliqué            Retirer     │  │
│                      │  │ ✓ Runtime Wine     r17 · MTLd3D 0.7.0              │  │
│ NON-WOW (D3D9)       │  │ ✓ Rosetta 2        Installé (x87)                  │  │
│ ┌──┐ Mon jeu D3D9    │  └────────────────────────────────────────────────────┘  │
│ │D3D9 Prêt           │                                                          │
│ └──┘                 │  LANCEMENT                                                │
│                      │  ┌────────────────────────────────────────────────────┐  │
│ [+] Nouveau profil…  │  │ Realmlist          logon.example.org   Modifier…   │  │
│  (en tête de liste,  │  │ Addons             24 installés · 3 mises à jour   │  │
│   pas en pied)       │  │ Mods DLL           2 actifs                         │  │
│                      │  └────────────────────────────────────────────────────┘  │
└──────────────────────┴──────────────────────────────────────────────────────────┘
   barre latérale 220 pt          détail mat, contenu ≤ 720 pt, marges 20 pt
```

Note de placement : « Nouveau profil… » est un bouton `+` dans l'en-tête de la
barre latérale (barre d'outils de la colonne), **pas** en pied de barre latérale
(`sidebars-012`). Le dessin ci-dessus le liste en bas pour la lisibilité ASCII seulement.

## Anatomie

**1. Barre latérale `ProfileSidebar`** (verre système)
- Deux groupes, un seul niveau sous chaque titre (`sidebars-006`, `sidebars-007`) :
  « World of Warcraft » et « Non-WoW (Direct3D 9) ». Le groupe vide est masqué.
- `ProfileRow` : glyphe de version 28 pt monochrome + nom (`type.body`) + état court
  (`type.secondary` : « Prêt », « Patch requis », « Runtime manquant »).
  L'état court est du texte, jamais une pastille de couleur seule (`color-007`).
- Sélection persistante surlignée (`split-views-001`). Menu contextuel : Lancer,
  Afficher dans le Finder, Renommer, Supprimer le profil… (le dossier de jeu n'est
  jamais supprimé ; libellé explicite).
- Réordonnable par glisser (`sidebars-002`). Dépôt d'un dossier = nouveau profil
  (`drag-and-drop-001`, `drag-and-drop-010`).
- Masquable (`sidebars-005`).

**2. Barre d'outils `MainToolbar`** (verre système, monochrome — `toolbars-004`)
- Centre : contrôle segmenté **Aperçu · Addons · Mods · Realmlist** (`segmented-controls-001`, `segmented-controls-004`), libellés texte uniquement (`segmented-controls-006`).
- Droite : rien d'autre. Réglages via le menu app (⌘,). Moins d'items = barre lisible (`toolbars-001`).
- Chaque item doublé dans le menu Présentation, ⌘1 à ⌘4 (`toolbars-024`).
- Lancer **n'est pas** dans la barre d'outils : une seule action proéminente par vue.

**3. En-tête `ProfileHeader`** (mat)
- Nom du profil en `type.profileTitle` (26 pt bold). Dessous : chemin du dossier
  en `type.mono` `text.secondary`, cliquable = Afficher dans le Finder (⇧⌘R).
- À droite, aligné sur la ligne de base du titre : `LaunchButton`.

**4. `LaunchButton`** (mat — contenu, donc **pas** de verre : `materials-001`)
- `.borderedProminent`, `.controlSize(.extraLarge)`, capsule, `accent.fill` /
  `accent.onFill`, symbole `play.fill` + « Lancer » (`buttons-003`, `buttons-029`).
- États :

| État | Rendu | Règle |
|---|---|---|
| Prêt | « ▶ Lancer », actif | `buttons-009` |
| Bloqué | Désactivé + **raison sous le bouton** en `type.secondary` (« Appliquez le patch pour lancer. ») | `feedback-006` |
| Démarrage | Indicateur d'activité dans le bouton, libellé « Démarrage… » | `buttons-011` |
| En cours | « ■ Arrêter » en `.bordered` (non proéminent), sous-titre de fenêtre « WoW en cours » | `buttons-004`, `feedback-002` |

**5. Section « État » `ReadinessSection`** — `Form` `.grouped`, 4 `StatusRow` :

| Ligne | Valeur prête | Valeur à corriger | Action unique |
|---|---|---|---|
| Dossier de jeu | « WoW.exe trouvé » | « Exécutable introuvable » (✗) | Changer… |
| Patch | « Appliqué » | « Requis » (!) | Appliquer le patch / Retirer (selon l'état, jamais les deux) |
| Runtime Wine | « r17 · MTLd3D 0.7.0 » | « Téléchargement 42 % » (barre déterminée) | Réessayer (si échec) |
| Rosetta 2 | « Installé (x87) » | « Requis » (!) | Installer… |

- `StatusRow` = symbole d'état coloré (`status.*`) + libellé `type.body` +
  valeur `type.bodyEmph` en `text.primary` + action `.bordered` `.small` alignée à droite.
- Libellé d'action avec ellipse s'il ouvre une fenêtre ou un panneau (`buttons-013`).
- « Retirer » le patch : pas d'alerte, action réversible (`alerts-003`).
- Progression du runtime **déterminée**, au même endroit à chaque fois (`progress-indicators-001`, `progress-indicators-007`).

**6. Section « Lancement »** — résumé cliquable des outils : Realmlist, Addons
(compte + mises à jour disponibles), Mods DLL (compte actifs). Chaque ligne mène à
l'onglet correspondant (progressive disclosure, `layout-004`).

**7. Onglets Addons / Mods / Realmlist** (mat, même fenêtre)
- Addons : `Table` (Nom · Version · Source · Mise à jour), colonnes redimensionnables
  (`lists-and-tables-012`). Barre au-dessus de la table : « Installer depuis une URL Git… »,
  « Tout mettre à jour », menu « Importer / Exporter la liste… ». Dépôt d'URL ou de `.zip` accepté.
- Mods DLL : `List` avec interrupteur par mod.
- Realmlist : éditeur `type.mono`, une ligne, validation inline.

**8. Fenêtre Réglages** (⌘,) — barre d'outils non personnalisable (`settings-011`),
titre = volet courant (`settings-012`), dernier volet restauré (`settings-013`) :
- Général : mises à jour (Sparkle) « Rechercher automatiquement », « Rechercher maintenant ».
- Graphismes : Retina, échelle du curseur, Option comme Alt, Metal HUD ;
  variables d'environnement derrière un `DisclosureGroup` « Avancé » (`layout-004`).
- Dépannage : actions de réparation + « Afficher les journaux ».

> [!question] Hypothèse à confirmer
> Les options graphiques sont traitées comme **globales** (le bouton « Options »
> actuel est global). Si elles sont par profil, elles passent en section
> « Lancement » du détail, sous un `DisclosureGroup`.

## États

| État | Rendu | Règle |
|---|---|---|
| Aucun profil | `ContentUnavailableView` : symbole `folder.badge.plus`, « Aucun profil », « Choisissez le dossier d'un client WoW 1.12, 2.4.3 ou 3.3.5a, ou déposez-le ici. », bouton « Choisir un dossier… » (proéminent, seul) | `writing-012`, `drag-and-drop-010` |
| Premier lancement, runtime en téléchargement | Profil visible, ligne Runtime avec barre déterminée, Lancer bloqué avec raison | `progress-indicators-001`, `feedback-006` |
| Dossier déplacé / introuvable | Ligne Dossier ✗ + « Changer… », barre latérale « Dossier introuvable » | `feedback-006` |
| Jeu en cours | Bouton « Arrêter », sous-titre de fenêtre, profil marqué « En cours » | `feedback-002` |
| Fenêtre étroite (< 820 pt) | Barre latérale repliée, bouton de barre latérale visible | `sidebars-011` |

## Tokens utilisés

`accent.fill`, `accent.onFill`, `bg.window`, `bg.group`, `text.primary`,
`text.secondary`, `separator`, `status.ready`, `status.action`, `status.error`,
`material.chrome`, `material.content`, `type.profileTitle`, `type.sectionTitle`,
`type.body`, `type.bodyEmph`, `type.secondary`, `type.mono`, `type.launch`,
`type.badge`, `space.4`, `space.5`, `space.6`, `space.8`, `radius.card`,
`size.sidebar`, `size.window.min`, `size.launch` — valeurs dans [[../../design|docs/design.md]].

## Règles

- Un seul bouton proéminent visible par vue (Lancer, ou « Choisir un dossier… » dans l'état vide).
- Aucun verre maison ; le verre vient de `NavigationSplitView` et `.toolbar`.
- Aucun contrôle ni information critique en bas de fenêtre (`layout-013`).
- Un état = symbole + texte ; la couleur seule ne porte rien (`accessibility-006`).
- La fenêtre ne montre ni l'icône de l'app, ni la version, ni de slogan (`launching-008`).

## Brief canvas `/design` (à lancer par l'utilisateur)

Non lancé : le canvas est déclenché par l'utilisateur. Sources attendues dans
`docs/design-wireframe/main-window/canvas/` ; entrée = `Main.dc.html`.
Tokens à reprendre tels quels depuis `docs/design.md` (laiton `#8C6A1C` / `#D9B65C`,
SF Pro via la pile `-apple-system`, rayons 12 pt). Le verre s'approxime en HTML par
`backdrop-filter: blur(30px) saturate(180%)` + liseré spéculaire 1 px, **seulement**
sur barre latérale et barre d'outils.

| # | Artboard | Taille | Contenu |
|---|---|---|---|
| 1 | `Main` (= Main-Light-Ready) | 960 × 620 | Profil WotLK prêt, 4 profils dans la barre latérale |
| 2 | `Main-Dark-Ready` | 960 × 620 | Même écran, thème sombre dessiné à part (polarité Lancer inversée, cartes sans filet) |
| 3 | `Main-Light-PatchRequired` | 960 × 620 | TBC, ligne Patch « Requis » + « Appliquer le patch », Lancer bloqué avec raison |
| 4 | `Main-Dark-FirstRun` | 960 × 620 | Runtime en téléchargement 42 %, barre déterminée |
| 5 | `Main-Dark-Running` | 960 × 620 | Jeu en cours, bouton « Arrêter », sous-titre de fenêtre |
| 6 | `Main-Light-Empty` | 960 × 620 | Aucun profil, zone de dépôt |
| 7 | `Main-Light-Addons` | 960 × 620 | Onglet Addons, table + « Installer depuis une URL Git… » |
| 8 | `Main-Light-Narrow` | 760 × 520 | Barre latérale repliée |
| 9 | `Main-Light-Ready-GraphiteAccent` | 960 × 620 | Accent système graphite : le design tient sans laiton |
| 10 | `Main-Light-ReduceTransparency` | 960 × 620 | Verre opacifié, lisibilité intacte |
| 11 | `Settings-Light-Graphics` | 560 × 420 | Volet Graphismes, « Avancé » déplié |
| 12 | `Tokens` | 1200 × 800 | Planche : accent clair/sombre + contrastes, états, échelle typo |

Après le canvas : `hig-audit` sur les artboards, puis lien du canvas publié dans le
frontmatter (`canvas:`) de cette carte.

## Verdict impeccable

> [!warning] Passe `impeccable` (critique + audit) — 2026-10-11
> Voir le rapport de session de jony ; corrections reportées ci-dessous.

- (rempli après la passe)

## Brief isaac (implémentation SwiftUI)

> [!info] Contexte compact pour isaac — implémente le design en SwiftUI
> - Source : `docs/design.md` (tokens) + cette carte. Ne pas inférer le design depuis le code existant.
> - **Décision à confirmer avant de coder** : macOS 26 uniquement impose de relever
>   le déploiement minimal — `Package.swift` `.macOS(.v14)` → `.macOS(.v26)`,
>   `MACOSX_DEPLOYMENT_TARGET` du `.xcodeproj` → 26.0, `LSMinimumSystemVersion`
>   de l'Info.plist → 26.0. Jony n'a touché à aucun de ces fichiers. Conséquence :
>   les utilisateurs sous macOS 14/15 ne reçoivent plus de mise à jour Sparkle —
>   prévoir le `sparkle:minimumSystemVersion` dans l'appcast.
> - Scène : `WindowGroup` + `NavigationSplitView(columnVisibility:)` ; retirer
>   `windowResizability(.contentSize)` et `.windowStyle(.hiddenTitleBar)` ;
>   `.defaultSize(960, 620)`, `.frame(minWidth: 760, minHeight: 520)`,
>   `.navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)`.
> - Verre : uniquement celui du système (barre latérale, `.toolbar`). **Aucun**
>   `.glassEffect()` ni `.buttonStyle(.glass)` dans le détail.
> - Lancer : `.buttonStyle(.borderedProminent)`, `.controlSize(.extraLarge)`,
>   `.tint(Color("AccentColor"))`, `.keyboardShortcut(.return, modifiers: .command)`.
> - Accent : Asset Catalog `AccentColor` avec variantes Any / Dark / High Contrast
>   (`#8C6A1C`, `#D9B65C`, `#7A5C14`, `#E3C26A`). Libellé sur accent : blanc en
>   clair, `#1C1606` en sombre (couleur d'asset `AccentLabel`).
> - Couleurs d'état : `Color.green/.orange/.red` sur les **symboles** seulement.
> - Section État : `Form { Section("État") { … } }.formStyle(.grouped)`.
> - État vide : `ContentUnavailableView` + `.dropDestination(for: URL.self)`.
> - Réglages : scène `Settings { TabView { … } }`, Sparkle dans le volet Général.
> - Menus : `CommandMenu("Profil")`, ⌘1–⌘4 dans `CommandGroup(after: .sidebar)`.
> - Après livraison : woz — audite le SwiftUI livré contre la guidance Apple.

## Liens

- Design system : [[../../design|docs/design.md]]
- État jugé : `docs/assets/launcher-preview.png`
