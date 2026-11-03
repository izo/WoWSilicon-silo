XV · LE DIABLE — serruriere

# serruriere — Audit de sécurité : WoWSilicon-silo

> Date : 2026-11-03 | Commit : dfebb1d (195 commits) | Branche : `feat/bfa-x64-profile`
> Stack : Swift 6 · SwiftUI/AppKit (macOS 14+) · Wine embarqué en sous-processus · Sparkle 2.9.1 · Cloudflare Worker + D1 (télémétrie) · GitHub Actions (macos-26)
> Auditeur : serruriere (Claude Code), mode audit, lecture seule
> Périmètre exclu : `.build/`, `BFA/`, `wow-silo-client/`, `.wine-runtime/`, binaires de `Resources/Patching/`
> Audit précédent : aucun `serruriere-*.md`, donc pas de comparaison.

---

## Résumé exécutif

**Constats** : 0 critique / 1 haut / 4 moyens / 5 bas / 6 info
**Score** : 55/100 (barème : 100 − 15 par haut − 5 par moyen − 2 par bas)
**Verdict** : CONDITIONAL PASS

La construction des commandes shell est saine. Chaque chemin passe par `shellQuote`. Les clés d'environnement personnalisées sont filtrées par `[A-Za-z_][A-Za-z0-9_]*` et leurs valeurs sont entre apostrophes. `-d3d11` est une constante. Aucune injection n'a été trouvée sur le chemin de lancement x64. Le risque principal n'est pas dans le code de l'app : la chaîne de release et de mise à jour vise encore l'amont `WoWSilicon/*`. Elle pousse vers son dépôt Pages, son flux appcast et sa clé EdDSA, et la télémétrie part vers son Worker. Viennent ensuite la distribution signée ad hoc, le Worker de télémétrie, qui accepte des écritures sans authentification et publie les realmlists, et l'exécution de hooks git dans les dossiers d'addons.

### Top 3 des remédiations prioritaires

1. Réorienter la release, le flux Sparkle et la télémétrie vers des ressources contrôlées par `izo/WoWSilicon-silo`, ou désactiver le workflow et Sparkle dans le fork. Aujourd'hui, un tag `v*` tente d'écrire dans `WoWSilicon/wowsilicon.github.io`.
2. Neutraliser les hooks et la config locale de git pour les opérations sur les addons : `-c core.hooksPath=/dev/null -c core.fsmonitor=false`, et seulement sur les dépôts clonés par l'app.
3. Ajouter au Worker une limite de débit par IP, une liste blanche ou un hachage des realmlists avant publication, et une rétention bornée des tables `daily_*`.

---

## Constats détaillés

### [HAUTE] La release, le flux Sparkle et la clé de mise à jour visent le dépôt amont

**Axe** : 5 — Dépendances et chaîne d'approvisionnement
**Fichier(s)** :
- `.github/workflows/release.yml:91-96` (checkout de `WoWSilicon/wowsilicon.github.io` avec `PAGES_REPO_TOKEN`)
- `.github/workflows/release.yml:108` et `Makefile:10` (`DOWNLOAD_URL_PREFIX=https://github.com/WoWSilicon/WoWSilicon/releases/download/...`)
- `.github/workflows/release.yml:126-141` (`git push` vers le dépôt Pages amont)
- `Packaging/Info.plist` (`SUFeedURL` = `https://wowsilicon.github.io/appcast.xml`, `SUPublicEDKey` amont)
- `Makefile:140,147` (`--link https://wowsilicon.github.io/`)
- `docs/releasing.md:7-17` (secrets décrits pour `WoWSilicon/WoWSilicon`)

**Description** : le fork a gardé toute la chaîne de publication de l'amont. Un tag `v*.*.*` poussé sur `izo/WoWSilicon-silo` lance un job qui :
- clone le dépôt Pages de l'amont ;
- écrit un appcast dont les URL de téléchargement pointent vers les releases amont ;
- tente un `git push` vers ce dépôt.

L'app compilée depuis ce fork vérifie ses mises à jour contre le flux et la clé publique EdDSA de l'amont.

**Preuve** : `repository: WoWSilicon/wowsilicon.github.io` (release.yml:94), `git push` (release.yml:140), `SUFeedURL` et `SUPublicEDKey` dans `Packaging/Info.plist`.

**Impact** :
- Si un `PAGES_REPO_TOKEN` avec droit d'écriture sur l'amont est configuré dans le fork, chaque release écrit dans un dépôt tiers. Cela viole la règle de `CLAUDE.md`. Sans ce jeton, le job échoue à la fin, après avoir créé la release GitHub du fork.
- L'appcast publié annonce un DMG hébergé chez l'amont, pas celui du fork.
- Toute installation du fork se remplace silencieusement par le binaire amont dès que l'amont publie un numéro de build supérieur. Le détenteur de la clé EdDSA amont contrôle le code qui tourne chez les utilisateurs du fork. C'est une frontière de confiance déléguée à un tiers.

**Remédiation** :
- Générer une paire EdDSA propre au fork (`generate_keys`) et mettre `SUPublicEDKey` à jour.
- Héberger l'appcast sur un dépôt Pages du fork et paramétrer `repository:`, `DOWNLOAD_URL_PREFIX` et `--link` via `${{ github.repository }}`.
- En attendant, ajouter `if: github.repository == 'izo/WoWSilicon-silo'` aux étapes de publication et retirer le job Pages, ou vider `SUFeedURL` dans le fork (`UpdaterService.isConfigured` désactive alors Sparkle).

**Ref** : CWE-494 (Download of Code Without Integrity Check, ici par un tiers), CWE-829, OWASP A08:2021 Software and Data Integrity Failures

---

### [MOYENNE] Distribution signée ad hoc, sans hardened runtime ni notarisation

**Axe** : 6 — Configuration (plateforme macOS)
**Fichier(s)** : `Makefile:11` (`CODESIGN_IDENTITY ?= -`), `Makefile:104-107` (`codesign --force --deep --sign "-"`, sans `--options runtime`), `.github/workflows/release.yml:98-108` (aucune étape de notarisation)

**Description** : le DMG de release (`make dmg`) est signé ad hoc, sans hardened runtime ni notarisation. Le projet Xcode active `ENABLE_HARDENED_RUNTIME = YES` (`WoWSilicon.xcodeproj/project.pbxproj:315`), mais ce n'est pas le chemin de release. Le projet ne contient aucun fichier `.entitlements`.

**Impact** :
- Les utilisateurs doivent contourner Gatekeeper (`xattr -d`, clic droit puis Ouvrir), ce qui les habitue à lancer des binaires non vérifiés.
- Sans hardened runtime, `DYLD_INSERT_LIBRARIES` et les débogueurs peuvent s'injecter dans le processus de l'app.
- Une copie modifiée du DMG redistribuée ailleurs reste indiscernable de l'officielle. Seule la mise à jour Sparkle est protégée, par EdDSA.

**Remédiation** : signer avec un Developer ID (`codesign --options runtime --timestamp`), en déclarant les entitlements nécessaires à Wine (`com.apple.security.cs.allow-jit`, `disable-library-validation` si nécessaire), puis lancer `xcrun notarytool submit --wait` et `stapler staple` dans le workflow.

**Ref** : CWE-347, OWASP A08:2021

---

### [MOYENNE] Le Worker de télémétrie accepte des écritures sans authentification ni limite de débit

**Axe** : 9 — Limitation de débit et abus
**Fichier(s)** : `tools/telemetry-worker/worker.js:74-76`, `:96-197` (`handleEvent`), `:97-100` (contrôle de taille)

**Description** : `POST /event` n'exige aucune preuve d'origine. N'importe quel `install_id` de 16 à 64 caractères `[a-zA-Z0-9_-]` est accepté. Un événement `launch` ou `wow_start` déclenche jusqu'à 8 requêtes D1 en écriture : `installs`, `daily_event_installs`, jusqu'à 5 `daily_dimension_installs` et `active_sessions`. Le contrôle `MAX_BODY_BYTES` ne lit que l'en-tête `content-length`. Une requête sans cet en-tête (corps en flux) passe directement à `request.json()`. CORS est en `*`.

**Preuve** : `const contentLength = Number(request.headers.get("content-length") || "0")` (worker.js:97), puis `await request.json()` sans borne (worker.js:104).

**Impact** :
- Un script qui génère des `install_id` aléatoires gonfle « anonymous_installs », les versions et les realmlists publiés (empoisonnement des statistiques publiques).
- Il consomme le quota d'écritures D1 : coût, ou blocage de la télémétrie légitime une fois le quota atteint.
- Il permet d'injecter des chaînes arbitraires, mais assainies en `[a-z0-9._ -]` ou `[a-z0-9.:-]`, dans `/stats.json` et `/report.json`.

**Remédiation** : ajouter une règle Cloudflare Rate Limiting sur `/event`, par exemple 30 requêtes par minute et par IP. Lire le corps avec une borne (`await request.arrayBuffer()` puis contrôle de `byteLength`). Regrouper les écritures dans un `db.batch()`. En option, signer les événements avec un HMAC embarqué : il dissuade sans empêcher.

**Ref** : CWE-770, CWE-400, OWASP API4:2023 Unrestricted Resource Consumption

---

### [MOYENNE] La télémétrie publie les realmlists, sans rétention bornée, vers un Worker tiers

**Axe** : 7 — Données et RGPD
**Fichier(s)** :
- `Sources/WoWSiliconSwift/Services/TelemetryService.swift:25-29` (lecture du realmlist), `:67` (`https://telemetry.wowsilicon.workers.dev`), `:214-224`
- `tools/telemetry-worker/worker.js:212-217` (`/stats.json` publie toutes les dimensions, realmlist compris), `:426-434` (`/report.json` publie `realmlist`), `:325-330` (`sanitizeRealm` garde les IP et les ports)
- `tools/telemetry-worker/worker.js:141-144` (seule `active_sessions` est purgée ; `installs` et `daily_*` gardent les données sans limite)

**Description** : la télémétrie est opt-in, désactivée par défaut (`Models/UserPrefs.swift:29`), et le message de consentement mentionne le realmlist (`Views/MainDashboardView.swift:163`). Mais :
1. le realmlist peut être une IP résidentielle ou un nom d'hôte personnel (serveur privé local, `192.168.x.x`, DynDNS), conservé tel quel ;
2. les points d'accès publics, sans authentification, l'exposent, avec le nombre d'installations associées ;
3. l'`install_id` est un UUID persistant, une donnée pseudonyme au sens du RGPD, conservé sans durée limite ;
4. le point de collecte appartient à l'amont, donc le responsable de traitement n'est pas l'éditeur du fork.

**Impact** : un realmlist personnel envoyé par un utilisateur devient public, et `/report.json?period=day` permet de le dater au jour près. Le fork n'a ni maîtrise ni registre du traitement.

**Remédiation** :
- Côté Worker, publier un realmlist seulement s'il dépasse un seuil k d'installations distinctes (par exemple k ≥ 5).
- Rejeter les IP privées ou littérales.
- Purger `daily_*` et `installs` au-delà de 13 mois.
- Côté app, envoyer seulement le domaine enregistrable, ou un hachage, et pointer vers un Worker du fork. Documenter la finalité et la durée de conservation.

**Ref** : CWE-359, RGPD art. 5(1)(c) et (e), OWASP A01:2021 (exposition de données)

---

### [MOYENNE] Exécution de hooks et de configuration git présents dans des dossiers d'addons

**Axe** : 2 — Injection (exécution de commandes par configuration)
**Fichier(s)** : `Sources/WoWSiliconSwift/Services/AddonService.swift:169-171` (tout sous-dossier de `AddOns` avec `.git` est traité comme un dépôt), `:198` (`git pull`), `:656-675` (`git config`, `rev-parse`, `git fetch origin`), `:683-693` (`runGit` sans `-c` de durcissement)

**Description** : pour tout dossier `Interface/AddOns/<X>` contenant `.git/`, l'app lance `git fetch origin` quand l'utilisateur clique sur « Check updates » (`AddonManagerView.swift:89`), puis `git pull` sur « Update ». Git exécute alors les hooks et la configuration locale de ce dépôt : `post-merge` et `post-checkout` sur `pull`, `reference-transaction` sur la mise à jour des refs pendant `fetch`, `core.fsmonitor` sur les commandes qui lisent l'index. `safe.directory` ne protège pas ici, car le dossier appartient au même utilisateur.

**Impact** : un addon distribué en archive zip contenant un `.git/` piégé (fréquent pour les addons de serveurs privés copiés depuis un dépôt) exécute du code natif macOS avec les droits de l'utilisateur. On sort ainsi du bac à sable Lua de WoW. `git clone` ne copie pas les hooks distants, donc les dépôts installés par l'app ne sont exposés qu'après modification locale.

**Remédiation** : appeler git avec `-c core.hooksPath=/dev/null -c core.fsmonitor=false -c protocol.file.allow=user`. Vérifier les mises à jour seulement pour les dépôts clonés par l'app (`manifest.repositories`). Pour les autres, afficher « dépôt externe », sans action.

**Ref** : CWE-78 (par configuration), CWE-829, OWASP A03:2021

---

### [BASSE] Workflow : entrée `workflow_dispatch` interpolée dans le shell, actions non épinglées par SHA

**Axe** : 5 — Chaîne d'approvisionnement (CI)
**Fichier(s)** : `.github/workflows/release.yml:42` (`version="${{ inputs.version }}"`), `:23`, `:92` (`actions/checkout@v4`), `:14-15` (`contents: write` au niveau du workflow)

**Description** : l'expression `${{ inputs.version }}` est substituée dans le script avant l'exécution de bash. Une valeur comme `1.0.0"; curl …; "` s'exécute avant `version_to_build_number.sh`, qui la validerait (`tools/release/version_to_build_number.sh:8-16`). La branche « tag » est protégée par cette même validation et par les règles de nommage des refs git.

**Impact** : seule une personne ayant les droits d'écriture peut déclencher le workflow, mais elle obtient alors `SPARKLE_PRIVATE_KEY` et `PAGES_REPO_TOKEN` dans le même job. Un tag `v4` déplacé en amont du checkout touche aussi tout le job.

**Remédiation** : passer par l'environnement (`env: INPUT_VERSION: ${{ inputs.version }}` puis `"$INPUT_VERSION"`). Épingler `actions/checkout@<sha>`. Ne charger les secrets Sparkle et Pages que dans l'étape qui les utilise.

**Ref** : CWE-78, GitHub Security Lab « script injection », OWASP CI/CD-SEC-4

---

### [BASSE] Les addons peuvent être clonés en `http://`

**Axe** : 8 — Upload et fichiers
**Fichier(s)** : `Sources/WoWSiliconSwift/Services/AddonService.swift:238-242`

**Description** : `http`, `https` et `file` sont acceptés. Le `--` avant l'URL (`:254`) empêche bien l'injection d'options, et `ext::` est refusé.

**Impact** : un attaquant en position réseau (Wi-Fi public) remplace le contenu de l'addon. L'impact se limite au Lua de l'addon, combiné au constat précédent si un `.git` piégé est servi ensuite.

**Remédiation** : n'accepter que `https` (et `file`, si c'est voulu).

**Ref** : CWE-319

---

### [BASSE] Raccourci exporté : nom de profil injecté sans nettoyage, raccourci partageable

**Axe** : 2 — Injection
**Fichier(s)** : `Sources/WoWSiliconSwift/Services/LaunchService.swift:359-365` (`# Generated by WoWSilicon for “\(version.displayName)”.`), `Sources/WoWSiliconSwift/Services/ShortcutExportService.swift:41-47` (`shortcuts sign --mode anyone`)

**Description** : `displayName` est inséré dans une ligne de commentaire du script zsh. Un retour à la ligne dans le nom (collé dans le `TextField` de `MainDashboardView.swift:745`, ou écrit dans le JSON des profils) termine le commentaire, et le reste s'exécute comme commande à chaque lancement du raccourci. Le raccourci est signé en mode `anyone`, donc partageable. Il contient alors les chemins absolus (nom d'utilisateur macOS) et les valeurs des variables d'environnement personnalisées.

**Impact** : auto-injection, ou injection dans un raccourci partagé à un tiers qui l'importe. Fuite du nom d'utilisateur et des valeurs d'environnement si le raccourci est partagé. [NON VÉRIFIÉ : le `TextField` SwiftUI sur macOS conserve-t-il un `\n` collé ? Le chemin par le JSON des profils, lui, est certain.]

**Remédiation** : remplacer `\r` et `\n` par un espace dans `displayName` avant interpolation, ou passer le nom par `shortcutSafeName`. Signer en `--mode people-who-know-me`, ou avertir avant le partage.

**Ref** : CWE-78, CWE-200

---

### [BASSE] Redistribuable VC++ téléchargé et exécuté sans vérification d'intégrité

**Axe** : 5 — Chaîne d'approvisionnement
**Fichier(s)** : `Sources/WoWSiliconSwift/Services/DependencyService.swift:57-58`, `:280-289`

**Description** : `vc_redist.x86.exe` et `vc_redist.x64.exe` sont téléchargés depuis `aka.ms` (HTTPS, avec redirection), écrits sous un nom fixe dans `$TMPDIR`, puis exécutés dans Wine sans contrôle de hachage ni de signature Authenticode. Wine expose tout le disque via le lecteur Z:.

**Impact** : une compromission de la redirection `aka.ms` ou du CDN, ou une interception TLS par un proxy d'entreprise, donnerait une exécution de code avec les droits de l'utilisateur. Le risque est théorique, mais il n'y a aucune défense en profondeur.

**Remédiation** : vérifier la signature Authenticode (éditeur Microsoft) avec `osslsigncode verify`, ou épingler une version et son SHA-256. Écrire dans un dossier `mkdtemp` en 0700 plutôt que sous un nom fixe.

**Ref** : CWE-494

---

### [BASSE] Variables d'environnement personnalisées sans liste noire (DYLD_*, PATH)

**Axe** : 6 — Configuration
**Fichier(s)** : `Sources/WoWSiliconSwift/Services/BundledWineRuntime.swift:82`, `:102-120`, `:122-130`

**Description** : la syntaxe des clés est validée, ce qui rend l'injection shell impossible, mais `DYLD_INSERT_LIBRARIES`, `DYLD_LIBRARY_PATH`, `PATH` et `WINESERVER` passent dans l'environnement de `/bin/sh` et de `wine`. Wine n'est pas protégé par SIP. Seules les clés x87 et `WINEPREFIX` sont retirées.

**Impact** : cela n'a d'effet que si un fichier de profils est partagé ou importé d'un tiers. Il n'existe pas d'import aujourd'hui, mais c'est une surface latente.

**Remédiation** : refuser les préfixes `DYLD_` et `LD_` ainsi que `PATH`, ou exiger une confirmation.

**Ref** : CWE-426, CWE-15

---

### [INFO] Points vérifiés sans faille

1. **Construction des commandes de lancement** (`LaunchService.swift:502-565`, `:744-764`, `:582-594`) : tous les chemins (jeu, exécutable, Wine, runtime x87, `WINEPREFIX`, `VK_DRIVER_FILES`, `DYLD_LIBRARY_PATH`) sont quotés. Dans la commande x64, `-d3d11` est littéral. Les variables personnalisées sont placées avant `baseEnv`, donc elles ne peuvent pas écraser `WINEPREFIX` ni les variables de l'app.
2. **Lancement dans Terminal** (`LaunchService.swift:446-500`) : le script temporaire est nommé par UUID et créé en 0600. L'AppleScript échappe `\` et `"`, et le chemin est quoté dans le bootstrap.
3. **`PEArchitecture`** (`PEArchitecture.swift:13-37`) : les bornes sont vérifiées (`offset <= count - 6`, taille minimale 0x40) et la lecture est plafonnée à 64 Kio. Pas de dépassement ni de plantage sur une entrée malformée.
4. **Copie des DLL** (`PatchService.swift:31-101`, `:299-315`) : toutes les destinations sont sous `gameURL`. Pour le x64, la suppression de `d3d9.dll` n'a lieu que si le fichier est identique octet pour octet à un fichier fourni par l'app (`:264-280`). Une DLL tierce n'est pas touchée.
5. **Artefacts du runtime** : SHA-256 épinglés et vérifiés (`tools/wine-runtime/restore.sh:48-70`, `update-mtld3d.sh:98-108`, `update-x87sidecar.sh:63-67`). Sparkle 2.9.1 est épinglé par révision dans `Package.resolved`.
6. **Secrets** : `gitleaks git --log-opts=--all` ne trouve aucune fuite sur les 195 commits, et `gitleaks dir` ne trouve rien sur `Sources`, `tools`, `Packaging`, `docs`, `.github`, `Tests` et `Makefile`. `tools/telemetry-worker/wrangler.toml.example` contient un `database_id` D1 : c'est un identifiant, pas un secret. La clé Sparkle privée n'est lue que depuis `secrets.SPARKLE_PRIVATE_KEY` et transmise par l'entrée standard (`Makefile:135-137`).

### [INFO] Wine n'isole pas le client de jeu

Les clients de serveurs privés sont souvent des archives tierces. Ils tournent sous Wine avec les droits complets de l'utilisateur, le lecteur Z: étant mappé sur `/` (non désactivé : aucune référence à `dosdevices` dans `Sources/`). C'est inhérent au produit et mérite une mention dans la documentation utilisateur. Retirer `dosdevices/z:` du préfixe réduirait la surface, au risque de casser les chemins de jeu.

### [INFO] Surcharge du runtime par variable d'environnement

`WOWSILICON_WINE_RUNTIME` (`BundledWineRuntime.swift:4-16`) remplace le dossier Wine embarqué. Il ne peut être défini qu'au lancement de l'app (`launchctl setenv` ou lancement en ligne de commande), donc par un acteur local qui a déjà la main. À garder en tête si l'app obtient un jour des TCC ou des entitlements élevés.

### [INFO] Masquage partiel dans l'export de logs

`TroubleshootingService.swift:514-523` masque `/Users/<nom>` et `Z:\Users\<nom>`, mais pas le nom de machine, le realmlist ni les variables d'environnement éventuellement incluses. C'est acceptable pour un export volontaire.

---

## Synthèse par axe

| # | Axe | Constats | Criticité max | Statut |
|---|-----|----------|---------------|--------|
| 1 | Secrets et identifiants | 0 | — | 🟢 |
| 2 | Injection | 2 | MOYENNE | 🟡 |
| 3 | Authentification et sessions | 0 (pas d'auth dans l'app) | — | 🟢 |
| 4 | Autorisation et contrôle d'accès | 0 | — | 🟢 |
| 5 | Dépendances et chaîne d'approvisionnement | 3 | HAUTE | 🟠 |
| 6 | Configuration (plateforme et CI) | 2 | MOYENNE | 🟡 |
| 7 | Données et RGPD | 1 | MOYENNE | 🟡 |
| 8 | Upload et fichiers | 1 | BASSE | 🔵 |
| 9 | Limitation de débit et abus | 1 | MOYENNE | 🟡 |
| 10 | Journalisation et supervision | 0 (info seulement) | INFO | 🟢 |
| **TOTAL** | | **10 (+ 6 info)** | HAUTE | |

Nouveau code de la branche (`git diff main...HEAD`, 12 fichiers) : `PEArchitecture`, `makeX64ShellCommand`, `prefixSupports64Bit`, `removeEmbeddedD3D9DLL` et la télémétrie x64 sont sains. Aucun constat n'est propre à la branche.

---

## Annexes

### Commandes exécutées

- `grep -rn "shellQuote\|/bin/sh\|\"-c\"" Sources` : 33 sites, tous quotés.
- `grep -n "copyItem\|removeItem\|moveItem\|createSymbolicLink\|write(to" Services/*.swift` : écritures limitées au dossier de jeu, au préfixe, à `TMPDIR` et à Application Support.
- `grep -n "https\?://\|URLSession\|sha256" Services/*.swift` : 2 téléchargements (VC++ et télémétrie).
- `gitleaks git --redact --log-opts=--all .` : `no leaks found`.
- `gitleaks dir --redact <Sources|tools|Packaging|docs|.github|Makefile|Tests>` : `no leaks found` ×7.
- `git log --all --diff-filter=A --name-only | grep -iE "\.env|\.pem|\.p12|secret|wrangler\.toml$"` : seul `tools/release/normalize_sparkle_private_key.sh` (script de normalisation, sans valeur de clé).
- Lecture : `LaunchService.swift`, `BundledWineRuntime.swift`, `TelemetryService.swift`, `worker.js`, `schema.sql`, `release.yml`, `Makefile`, `Info.plist`, `AddonService.swift`, `PatchService.swift`, `PEArchitecture.swift`, `ShortcutExportService.swift`, `DependencyService.swift`, `ProcessRunner.swift`, `restore.sh`.

### Éléments non vérifiés

- [NON VÉRIFIÉ — pas de déploiement accessible] Configuration réelle du Worker en production (règles de limitation de débit Cloudflare au niveau de la zone, journaux d'IP).
- [NON VÉRIFIÉ — secrets GitHub illisibles] Présence de `PAGES_REPO_TOKEN` et de `SPARKLE_PRIVATE_KEY` dans le fork, et portée du jeton.
- [NON VÉRIFIÉ — comportement d'AppKit] Conservation d'un `\n` collé dans le `TextField` du nom de profil.
- [NON VÉRIFIÉ — runtime absent du périmètre] Contenu et signatures de `.wine-runtime/` et des DLL de `Resources/Patching/` (exclus du périmètre). Seul l'épinglage SHA-256 des archives a été vérifié.
- Le déclenchement du hook `reference-transaction` sur `git fetch` repose sur la documentation git (≥ 2.28), sans test local. Le hook `post-merge` sur `git pull` est certain.
