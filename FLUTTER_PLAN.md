# Plano: Projeto Flutter (Android + Desktop) para o StackConnect

## Contexto

O StackConnect hoje é um app **iOS nativo** (SwiftUI, iOS 17+, ~40k linhas Swift, 51 módulos)
publicado na App Store. Ele é um painel para desenvolvedores gerenciarem contas de
**App Store Connect**, **Firebase** e **Google Play** num só lugar (apps, versões, builds,
TestFlight, reviews, analytics, certificados/perfis, Remote Config, FCM, etc.).

**Decisão:** *não* haverá migração. O app iOS atual (`StackConnect/`, `StackConnectWidget/`,
`Packages/` Swift) **permanece intocado**. Vamos criar uma pasta `flutter/` dentro do
repositório com um **monorepo Flutter novo**, focado em **Android + Desktop (Windows/Linux)**,
reimplementando as funcionalidades. macOS **não** entra no escopo Flutter — já é coberto pelo
app nativo Apple. Gerenciamento de estado: **Riverpod**.

**Core compartilhado em Rust (ver `SHARED_CORE_PLAN.md`):** a lógica — clientes de API,
persistência, auth/JWT, OAuth, sync e modelos de domínio — **não** é escrita em Dart; vive num
crate **Rust `stack_core`** consumido via **`flutter_rust_bridge`** (e pelo app iOS nativo via
UniFFI). No lado Flutter, o pacote **`stack_core_dart`** carrega as bindings geradas pelo FRB +
as libs nativas (`.so`/`.dll`) e **os controllers Riverpod** (`AsyncNotifier`) que envolvem as
chamadas do core e expõem `AsyncValue` para a UI. Strings (l10n) e secure storage ficam no lado
Flutter (este último injetado no core via callback `CredentialStore`).

**UI por plataforma:** cada plataforma é um app Flutter **fino** que só desenha a interface
ligada aos providers do `stack_core_dart`:
- **`stack_mobile`** (Android) → **Material Design 3**.
- **`stack_desktop`** (Windows/Linux) → **Fluent Design** (`fluent_ui`).

Assim cada UI fica 100% idiomática à sua plataforma, sem camada de abstração Material↔Fluent;
nenhuma regra de negócio é duplicada (está no core Rust) e a mesma lógica roda no iOS nativo.

O conhecimento do app iOS (modelos, contratos de API, fluxos de auth JWT, formato de
persistência) é reescrito **uma vez em Rust** (`SHARED_CORE_PLAN.md`) e compartilhado entre o
iOS nativo e este projeto Flutter — em vez de portado para Dart. Os contratos REST das três
APIs são estáveis e a lógica roda idêntica nos dois mundos.

## Arquitetura alvo (mapeamento iOS → Flutter)

| iOS (atual) | Flutter (novo) |
|---|---|
| MVVM `@Published`/ViewModel | `@riverpod` `AsyncNotifier` por tela (Dart, envolve o core) — **em `stack_core_dart`** |
| View SwiftUI | `ConsumerWidget` no app de UI (`stack_mobile` Material / `stack_desktop` Fluent) |
| Coordinator + `NavigationPath` | `go_router` (rotas tipadas + `ShellRoute`); parser de deep link **no core Rust** |
| Deep links `stackconnect://` | parser **no core Rust** → `router.go(...)` (Flutter usa `app_links` p/ receber) |
| `SwiftDataStorable` (blob: typeName+id+JSON) | **SQLite no core Rust** (`rusqlite`), não `drift` |
| Keychain (credenciais) | `flutter_secure_storage` via callback `CredentialStore` do core |
| UserDefaults (flags) | `shared_preferences` (lado Flutter) |
| `BGAppRefreshTask` (sync background) | `workmanager` (Android) dispara o sync **do core**; timer/launch (Windows/Linux) |
| App Store Connect Swift SDK | **core Rust** (`reqwest` + JWT ES256) via FRB |
| Providers REST Firebase/Play (Swift) | **core Rust** (`reqwest` + JWT RS256 → OAuth) via FRB |
| Padrão offline-first (cache → API → enriquece → persiste) | **no core Rust**; Flutter expõe via `AsyncNotifier` |

## Monorepo: `stack_core_dart` (bindings + controllers) + apps de UI (Material / Fluent)

O `flutter/` é um **monorepo** com **pub workspace** (nativo no Dart ≥3.6, via `workspace:` no
pubspec; `melos` opcional para orquestrar scripts/CI). A **lógica em si** está no crate Rust
`stack_core` (`SHARED_CORE_PLAN.md`); o Flutter tem o pacote de bindings + dois apps:

**`packages/stack_core_dart`** — pacote Flutter que **liga a UI ao core Rust**:
- `bindings/` — código Dart **gerado pelo `flutter_rust_bridge`** + libs nativas (`.so`/`.dll`)
  do `stack_core`. Não há `api/`, `auth/`, `storage/` em Dart — isso é tudo Rust.
- **`controllers/`** — peça central do lado Flutter: os providers Riverpod
  (`@riverpod AsyncNotifier`) que chamam as funções async do core (via bindings), tratam
  `AsyncValue`, e expõem dados/mutações para a UI.
- `credential_store.dart` — implementa o callback `CredentialStore` do core sobre
  `flutter_secure_storage`; injetado no core na inicialização.
- `l10n/` (strings geradas, re-exportadas) e os **contratos de rota** que os dois apps usam
  para montar o `GoRouter` (o parser de deep link em si vem do core Rust).
- Depende de `flutter_riverpod`, `ffi`/`flutter_rust_bridge`, `flutter_secure_storage`,
  `shared_preferences`. **Não** depende de `material` nem `fluent_ui`.

**`apps/stack_mobile`** (Android, **Material 3**) e **`apps/stack_desktop`** (Windows/Linux,
**`fluent_ui`**) — cada um é um app Flutter **fino**:
- Dependem de `stack_core_dart`. Envolvem a árvore num `ProviderScope`.
- `stack_mobile`: `MaterialApp.router`, `NavigationBar`/`NavigationRail`, widgets `material.dart`.
- `stack_desktop`: `FluentApp.router`, `NavigationView`/`NavigationPane`, `ContentDialog`,
  `InfoBar`, etc.
- Constroem o `GoRouter` a partir dos contratos de rota, mapeando cada rota para o
  `ConsumerWidget` daquela plataforma.
- A tela só faz: `ref.watch(algumControllerProvider)` → desenhar → `ref.read(...).acao()`.
  Nenhuma chamada de API, persistência ou regra de negócio mora nos apps.

**Tema:** os **tokens de marca** (cores, espaçamentos, tipografia) ficam em `stack_core_dart`
num formato neutro; cada app os converte para `ThemeData` (mobile) ou `FluentThemeData`
(desktop), com light/dark. **Charts** (`fl_chart`) e **strings** (`AppLocalizations`) são
compartilhados pelos dois apps.

**Regra de ouro:** a lógica testável (auth, API, persistência, sync) vive no core **Rust** e é
testada uma vez; `stack_core_dart` só faz binding + estado; os apps só fazem UI. Nenhum app
importa lógica de negócio; o core nunca importa design system.

## Estrutura de pastas (monorepo `flutter/`)

Pub workspace no root. A **lógica** está no crate Rust `core/` na raiz do repo
(`SHARED_CORE_PLAN.md`); aqui ficam as **bindings + controllers** (`packages/stack_core_dart`)
e a **UI** (`apps/`).

```
flutter/
├── pubspec.yaml          (workspace root: members = packages/* apps/*)
├── melos.yaml            (opcional — scripts: bootstrap, frb-gen, analyze, test)
├── analysis_options.yaml
├── tool/                 (script de conversão de l10n .xcstrings → .arb)
│
├── packages/
│   └── stack_core_dart/  PACOTE FLUTTER — bindings do core Rust + estado, sem telas
│       ├── pubspec.yaml  l10n.yaml  flutter_rust_bridge.yaml
│       ├── test/         (controllers com core mockado atrás do binding)
│       └── lib/
│           ├── stack_core_dart.dart   (barrel: API pública do pacote)
│           ├── bindings/   (Dart GERADO pelo flutter_rust_bridge + loader das libs nativas)
│           ├── controllers/ (providers Riverpod @riverpod AsyncNotifier — envolvem o core)
│           ├── credential_store.dart  (impl. do callback CredentialStore via secure_storage)
│           ├── theme/      (tokens neutros de marca — cores/espaços/tipografia)
│           ├── router/     (contratos de rota que os apps usam p/ montar o GoRouter)
│           └── l10n/       (AppLocalizations gerado + re-export)
│
└── apps/
    ├── stack_mobile/     APP ANDROID — Material 3 (depende de stack_core_dart)
    │   ├── pubspec.yaml
    │   ├── android/       (build do .so do core via cargo-ndk no Gradle)
    │   ├── integration_test/
    │   └── lib/
    │       ├── main.dart  bootstrap.dart   (ProviderScope + MaterialApp.router)
    │       ├── theme/      (tokens → ThemeData light/dark)
    │       ├── router/     (GoRouter: rota → ConsumerWidget Material)
    │       ├── shell/      (NavigationBar/NavigationRail)
    │       └── features/   (telas Material por feature — só widgets)
    │
    └── stack_desktop/    APP WINDOWS/LINUX — fluent_ui (depende de stack_core_dart)
        ├── pubspec.yaml
        ├── windows/  linux/   (link da .dll/.so do core)
        ├── integration_test/
        └── lib/
            ├── main.dart  bootstrap.dart   (ProviderScope + FluentApp.router)
            ├── theme/      (tokens → FluentThemeData light/dark)
            ├── router/     (GoRouter: rota → ConsumerWidget Fluent)
            ├── shell/      (NavigationView/NavigationPane)
            └── features/   (telas Fluent por feature — só widgets)
```

Convenção: modelos de domínio e DTOs vivem no **core Rust** (mapeados de fio → domínio lá
dentro); o Dart recebe os tipos já espelhados pelo FRB. `controllers/` em `stack_core_dart` =
os `AsyncNotifier`; os dois apps consomem os mesmos providers. Os apps só têm `features/` de
widgets — sem `domain/`, `data/` ou chamadas de rede.

## Dependências principais (pubspec)

> A lógica (HTTP, JWT, SQLite, OAuth, sync) está no **crate Rust** `stack_core` — ver
> `SHARED_CORE_PLAN.md` para os crates (`reqwest`, `jsonwebtoken`, `rusqlite`, `serde`, `tokio`).
> Abaixo só o lado Flutter.

**No `stack_core_dart`** (bindings + estado — compartilhado pelos dois apps):
- Bindings: `flutter_rust_bridge` + `ffi` (Dart gerado a partir do core Rust).
- Estado: `flutter_riverpod` + `riverpod_annotation` (codegen `@riverpod`), `riverpod_lint`.
- Secure storage / prefs (impl. dos callbacks do core): `flutter_secure_storage`,
  `shared_preferences`.
- i18n: `intl`, `flutter_localizations` (gera `AppLocalizations` dentro do pacote).
- Deep link (receber no Flutter; o parsing é do core): `app_links`. Tipos de rota: `go_router`
  (construção do `GoRouter` fica em cada app).
- Notif/arquivos: `flutter_local_notifications`, `workmanager` (Android, dispara o sync do
  core), `file_picker` (importar `.p8`, service-account JSON, `.mobileprovision`).
- Dev/codegen: `build_runner` (para `@riverpod`), `flutter_rust_bridge_codegen`.

**Em `stack_mobile`** (Android): Material 3 (built-in) + `fl_chart`. Depende de `stack_core_dart`.

**Em `stack_desktop`** (Windows/Linux): **`fluent_ui`** + `fl_chart`. Depende de `stack_core_dart`.

**Dev/test (todos os pacotes):** `build_runner`, `mocktail`, `integration_test`.

## Clientes de API no core Rust (sem SDK pronto — feitos à mão)

Implementados em **Rust** (`stack_core`, ver `SHARED_CORE_PLAN.md`) e expostos a Swift (UniFFI)
e Dart (FRB). Cada provedor: cliente `reqwest` próprio + camada de auth. Contratos abaixo.

1. **App Store Connect v1** — base `api.appstoreconnect.apple.com`. Auth: JWT **ES256**
   (header `kid`=keyId; claims `iss`=issuerId, `aud`=`appstoreconnect-v1`, `exp`≈now+20min),
   `Authorization: Bearer`. Envelope JSON:API genérico `AscResponse<T>` + paginação por
   `links.next`. Endpoints (por feature): `/v1/apps`, `appStoreVersions`, `builds`,
   `betaGroups`/`betaTesters`, `customerReviews`(+responses), `certificates`, `profiles`,
   `bundleIds`, `devices`, `users`/`userInvitations`, `ageRatingDeclarations`, `appInfos`,
   relatórios de analytics. Portar tradução de erros de
   `StackConnect/Infra/Errors/AppleAPIErrorTranslator.swift` (inclui detecção do 403 de
   "pending agreements").
2. **Firebase Management** — JWT **RS256** → troca por token OAuth (cache c/ margem 60s).
   Escopos: `firebase`, `cloud-platform`, `analytics.readonly`, `firebase.messaging`. Hosts:
   `firebase.googleapis.com/v1beta1`, Remote Config `firebaseremoteconfig.googleapis.com/v1`
   (ETag/`If-Match` no PUT), FCM `fcm.googleapis.com`, GA4 `analyticsdata.googleapis.com/v1beta`.
3. **Google Play** — mesmo fluxo RS256→OAuth, escopos `androidpublisher`,
   `playdeveloperreporting`. Hosts `androidpublisher.googleapis.com/.../v3`,
   `playdeveloperreporting.googleapis.com/v1beta1`.

`GoogleOAuthAuthenticator` único parametrizado por (service account, escopos) serve Firebase
e Play; cache por `(clientEmail, hash dos escopos)`. Clientes são stateless no core Rust;
no Flutter, providers Riverpod `.family` expõem o core por `accountId` (no iOS, ViewModels).

**Arquivos de referência para portar:**
- `Packages/APIProviderFirebase/Sources/APIProviderFirebase/JWT/FirebaseAuthenticator.swift`
  (fluxo RS256→OAuth)
- `Packages/StackCore/Sources/StackCore/SwiftDataStorable.swift` (contrato do blob store)
- `StackConnect/Models/AccountModel.swift` (conta + regras/papel/origem → freezed)
- `StackConnect/Infra/Sync/SyncService.swift` (full vs lightweight + notificações)
- `StackConnect/Infra/Notifications/DeepLink.swift` (gramática das rotas de deep link)

## Roadmap faseado (MVP primeiro)

A partir da Fase 1, **cada feature** entrega três camadas: lógica no **core Rust** (api +
persistência + expor função async, testada) → controller Riverpod em `stack_core_dart` → tela
nos **dois apps** Flutter (Material no `stack_mobile`, Fluent no `stack_desktop`). A mesma
lógica do core é consumida pelo app iOS nativo via UniFFI (ver `SHARED_CORE_PLAN.md`).

- **Fase 0 — Fundação (core Rust + monorepo Flutter):** criar o crate Rust `stack_core` com
  esqueleto (`blob_store` SQLite, `CredentialStore` trait, `api_exception`, deep_link_parser) e
  as duas facades de binding (UniFFI + FRB) com uma função de *smoke* atravessando a fronteira;
  build do XCFramework e do `.so` Android. No **pub workspace** Flutter: `packages/stack_core_dart`
  (bindings FRB + `ProviderScope`/codegen Riverpod + impl. do `CredentialStore` via
  `flutter_secure_storage` + tokens de tema + gen-l10n) e `apps/stack_mobile` + `apps/stack_desktop`
  com `MaterialApp.router` / `FluentApp.router`, conversão de tokens → `ThemeData` /
  `FluentThemeData`, `GoRouter` a partir dos contratos do core e shell de navegação com tela
  placeholder. CI: `cargo test`/`clippy` + checagem do codegen FRB + `analyze`/`test` no
  workspace. Sem features.
- **Fase 1 — Núcleo Apple (MVP demoável):** no core Rust — signer ES256 + `AppStoreConnectClient`
  + persistência. Telas (nos dois apps Flutter, e disponíveis ao iOS via core): lista de contas,
  adicionar conta Apple (validar credenciais via `/v1/apps`), home básica, lista de apps,
  detalhe do app, ratings & reviews + all reviews (leitura) e responder review (escrita).
  Persistência offline de contas/apps/reviews no core.
- **Fase 2 — Amplitude Apple:** versões (incl. phased release), builds, TestFlight
  (grupos/testers), certificados, perfis, bundle IDs, devices (+ parser de `.mobileprovision`,
  portar `DeviceImportParser.swift`), user access, age rating/privacy/accessibility/app info,
  manage localizations, screenshots.
- **Fase 3 — Firebase:** `GoogleOAuthAuthenticator` + clientes; adicionar conta, projetos
  (lista/detalhe), apps Firebase, Remote Config (leitura + escrita com ETag), FCM campaigns,
  dashboard de analytics.
- **Fase 4 — Google Play:** Android Publisher + Reporting; adicionar conta, lista de apps,
  reviews, reporting/vitals.
- **Fase 5 — Analytics & charts:** visualizações `fl_chart` (ASC, GA4, Play); cache de
  relatórios (portar `AnalyticsFileCache.swift`).
- **Fase 6 — Sync & notificações:** `SyncService` (full/lightweight); background via
  `workmanager` (Android); Windows/Linux = sync no launch + timer em processo + refresh manual.
  `flutter_local_notifications` para novos reviews / mudança de status; toque → deep link.
- **Fase 7 — Widgets & extras (por último):** widget de tela inicial Android via `home_widget`
  + código nativo Glance/AppWidget. Settings, License, polimento, passada completa de l10n.

## Concerns por plataforma / fora de escopo

- **iOS / macOS**: permanecem 100% no app nativo Apple intocado — fora do escopo Flutter.
- **iOS WidgetKit**: permanece no app nativo intocado — não reimplementado em Flutter.
- **Widget Android**: `home_widget` exige código nativo Glance/AppWidget em `flutter/android/`
  (Fase 7).
- **Widgets desktop**: não existem — fora de escopo.
- **Background quando fechado**: só Android (`workmanager`, ~15 min mín.). Desktop (Windows/Linux)
  não tem API de background task → sync no launch + timer enquanto aberto + manual.
- **Notificações**: completas em Android/Linux; Windows best-effort; desktop só com app
  aberto. Pedir permissão em Android 13+.
- **Secure storage Linux**: precisa de libsecret + keyring; fallback de arquivo cifrado com
  passphrase para headless/CI.
- **Registro de deep link**: intent filter (Android), registro de protocolo (Windows),
  `.desktop` MimeType (Linux) — via `app_links`.
- **Fora de escopo total**: targets iOS e macOS, App Group, qualquer coisa WidgetKit/BGTask,
  reuso de Swift packages.

## Localização (reaproveitar `.xcstrings`)

Fonte: `StackConnect/Resources/Localizable.xcstrings` (catálogo JSON do Xcode), 13 idiomas
(en, de, es, es-MX, fr, it, ja, ko, nl, pt-BR, pt-PT, ru, sv, zh-Hant). Plano:
1. Script único em `flutter/tool/` lê o `.xcstrings` e gera um `app_<lang>.arb` por idioma
   dentro de `packages/stack_core` (`l10n.yaml` do core), com fallback para `en`/chave quando
   `value` vazio.
2. Normalizar placeholders Apple (`%@`, `%lld`, `%1$@`) → ICU `{argN}` com metadados `@chave`.
3. Locales mapeiam direto (pt-BR, pt-PT, es-MX, zh-Hant válidos no Flutter); configurar
   `supportedLocales` + `localeResolutionCallback` em cada app a partir da lista exposta pelo core.
4. `flutter gen-l10n` gera `AppLocalizations` **em `stack_core_dart`**, re-exportado pelo
   barrel; os dois apps consomem as mesmas strings — traduz-se uma vez só. (As strings de UI
   ficam no lado Flutter; o iOS nativo segue com seu próprio `.xcstrings`.)

## Verificação / testes

> O grosso da cobertura (auth, API, persistência, sync, deep-link) é **`cargo test` no core
> Rust** — ver `SHARED_CORE_PLAN.md`. Abaixo só o lado Flutter.

- **Core Rust (prioridade máxima):** golden de JWT ES256/RS256; cache OAuth (margem 60s);
  clientes API com HTTP mockado + fixtures JSON (URL/método/headers, DTO→domínio, paginação
  `links.next`, 403 pending-agreements); `blob_store` em SQLite `:memory:`; `deep_link_parser`
  nas 5 formas `stackconnect://`.
- **Smoke de binding:** um teste por lado garantindo que a chamada atravessa a fronteira FRB e
  retorna o tipo esperado (Dart test; o lado Swift no `SHARED_CORE_PLAN.md`).
- **Unit controllers (Flutter):** `ProviderContainer` com o core mockado atrás do binding;
  transições de `AsyncValue` e invalidação de dependentes em mutações.
- **Widget tests:** telas-chave (contas, reviews, add-account) com providers fixados.
- **Integração (`integration_test/`):** fluxo feliz (add account → apps → reviews) com o core
  apontando p/ rede stub, em emulador Android e num target desktop (Linux no CI).
- **CI (GitHub Actions):** `cargo test`/`clippy` no core + checagem do codegen FRB; no workspace
  Flutter `build_runner`, `flutter analyze` (riverpod_lint), `flutter test` e widget/integration
  nos apps; build de release do `stack_desktop` (Linux) + `assembleDebug` do `stack_mobile`.

## Primeiro passo concreto

1. **Core Rust** (`core/` na raiz do repo): `cargo new --lib`, configurar as facades UniFFI e
   FRB, e uma função *smoke* (ex.: `ping()`/validar credenciais) — ver `SHARED_CORE_PLAN.md`.
2. Montar o **pub workspace** Flutter em `flutter/`:
   - `flutter create --template=package packages/stack_core_dart` (depois plugar o FRB).
   - `flutter create --org <org> --platforms=android apps/stack_mobile`.
   - `flutter create --org <org> --platforms=windows,linux apps/stack_desktop`.
   - `pubspec.yaml` root com `workspace: [packages/stack_core_dart, apps/stack_mobile,
     apps/stack_desktop]`; os apps declaram `stack_core_dart` via `path`. `melos.yaml` opcional.
3. Rodar o codegen FRB + `build_runner`, validar a função *smoke* atravessando o binding nos dois
   apps, e entregar a Fase 0 antes de iniciar a Fase 1.
