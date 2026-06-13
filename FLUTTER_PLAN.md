# Plano: Projeto Flutter (Android + Desktop) para o StackConnect

## Contexto

O StackConnect hoje é um app **iOS nativo** (SwiftUI, iOS 17+, ~40k linhas Swift, 51 módulos)
publicado na App Store. Ele é um painel para desenvolvedores gerenciarem contas de
**App Store Connect**, **Firebase** e **Google Play** num só lugar (apps, versões, builds,
TestFlight, reviews, analytics, certificados/perfis, Remote Config, FCM, etc.).

**Decisão:** *não* haverá migração. O app iOS atual (`StackConnect/`, `StackConnectWidget/`,
`Packages/` Swift) **permanece intocado**. Vamos criar uma pasta `flutter/` dentro do
repositório com um **projeto Flutter novo**, focado em **Android + Desktop
(Windows/macOS/Linux)**, reimplementando as funcionalidades. Gerenciamento de estado:
**Riverpod**.

O objetivo é reaproveitar o *conhecimento* do app iOS (modelos, contratos de API, fluxos de
auth JWT, formato de persistência), não o código Swift. Os contratos REST das três APIs são
estáveis e portáveis para Dart.

## Arquitetura alvo (mapeamento iOS → Flutter)

| iOS (atual) | Flutter (novo) |
|---|---|
| MVVM `@Published`/ViewModel | `@riverpod` `Notifier`/`AsyncNotifier` por tela |
| View SwiftUI | `ConsumerWidget` |
| Coordinator + `NavigationPath` | `go_router` (rotas tipadas + `ShellRoute`) |
| Deep links `stackconnect://` | `app_links` → parser → `router.go(...)` |
| `SwiftDataStorable` (blob: typeName+id+JSON) | `drift` (1 tabela `persisted_items`) |
| Keychain (credenciais) | `flutter_secure_storage` |
| UserDefaults (flags) | `shared_preferences` |
| `BGAppRefreshTask` (sync background) | `workmanager` (Android); timer/launch (desktop) |
| App Store Connect Swift SDK | cliente Dart próprio (Dio + JWT ES256) |
| Providers REST Firebase/Play (Swift) | clientes Dart (Dio + JWT RS256 → OAuth) |
| Padrão offline-first (cache → API → enriquece → persiste) | mesmo padrão via `AsyncNotifier` |

## Estrutura de pastas (`flutter/lib/`)

Feature-first com `core/` para transversais. Cada feature tem `data/` `domain/`
`presentation/`. `api/` concentra os clientes REST tipados.

```
flutter/
├── pubspec.yaml  analysis_options.yaml  build.yaml  l10n.yaml
├── android/ windows/ macos/ linux/   (runners gerados)
├── test/  integration_test/  tool/   (tool/ = script de conversão de l10n)
└── lib/
    ├── main.dart  app.dart  bootstrap.dart
    ├── core/
    │   ├── providers/   config/   theme/   widgets/   utils/   localization/
    │   ├── network/     (dio_client, auth_interceptor, api_exception, paging)
    │   ├── auth/        (jwt/asc_jwt_signer ES256, jwt/google_jwt_signer RS256,
    │   │                 google_oauth_authenticator, token_cache)
    │   ├── storage/     (database drift, blob_store, secure_credential_store, prefs)
    │   ├── sync/        (sync_service, sync_change, background/)
    │   ├── notifications/ (local_notification_service, deep_link_service)
    │   └── router/      (app_router, routes, deep_link_parser)
    ├── features/        (accounts, add_account, home, apps, versions, builds,
    │                     testflight, reviews, analytics, app_metadata, certificates,
    │                     users, localizations, firebase, remote_config, messaging,
    │                     firebase_analytics, google_play, settings, license)
    └── api/
        ├── apple/        (app_store_connect_client, endpoints/, models/)
        ├── firebase/     (management, remote_config, messaging, analytics_data clients)
        └── google_play/  (android_publisher_client, reporting_client, models/)
```

Convenção: `domain/` = modelos freezed (equivalentes a `StackConnect/Models/*.swift`);
`api/.../models/` = DTOs de fio, mapeados para domínio nos repositories (desacopla rede da UI).

## Dependências principais (pubspec)

- Estado: `flutter_riverpod` + `riverpod_annotation` (codegen `@riverpod`), `riverpod_lint`.
- Rotas/deep link: `go_router`, `app_links`.
- Rede: `dio` (+ `dio_smart_retry` opcional).
- JWT/cripto: `dart_jsonwebtoken` (assina ES256 do `.p8` Apple e RS256 do service-account
  Google; aceita PEM direto — simplifica vs. manipulação ASN.1 do Swift), `pointycastle`
  como fallback, `crypto`.
- Persistência: **`drift`** + `sqlite3_flutter_libs` (SQLite empacotado, suporte 1ª classe em
  Android **e** os três desktops — fator decisivo vs. isar/hive), `path_provider`/`path`;
  `flutter_secure_storage`; `shared_preferences`.
- Modelos/codegen: `freezed` + `json_serializable` (dev: `build_runner`).
- UI/charts/i18n: `fl_chart`, `intl`, `flutter_localizations`.
- Background/notif: `workmanager` (Android), `flutter_local_notifications`.
- Arquivos: `file_picker` (importar `.p8`, service-account JSON, `.mobileprovision`).
- Testes: `mocktail`, `integration_test`.

## Clientes de API em Dart (sem SDK pronto — feitos à mão)

Cada provedor: instância `Dio` própria + `auth_interceptor`.

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
e Play; cache por `(clientEmail, hash dos escopos)`. Clientes são stateless; providers
Riverpod `.family` constroem um cliente por `accountId`.

**Arquivos de referência para portar:**
- `Packages/APIProviderFirebase/Sources/APIProviderFirebase/JWT/FirebaseAuthenticator.swift`
  (fluxo RS256→OAuth)
- `Packages/StackCore/Sources/StackCore/SwiftDataStorable.swift` (contrato do blob store)
- `StackConnect/Models/AccountModel.swift` (conta + regras/papel/origem → freezed)
- `StackConnect/Infra/Sync/SyncService.swift` (full vs lightweight + notificações)
- `StackConnect/Infra/Notifications/DeepLink.swift` (gramática das rotas de deep link)

## Roadmap faseado (MVP primeiro)

- **Fase 0 — Fundação:** `flutter create --platforms=android,windows,macos,linux`;
  `ProviderScope`, shell go_router, tema, gen-l10n, `blob_store` (drift),
  `secure_credential_store`, Dio + interceptors, `api_exception`, codegen base, CI do
  `build_runner`. Sem features.
- **Fase 1 — Núcleo Apple (MVP demoável):** signer ES256 + `AppStoreConnectClient`. Telas:
  lista de contas, adicionar conta Apple (validar credenciais via `/v1/apps`), home básica,
  lista de apps, detalhe do app, ratings & reviews + all reviews (leitura) e responder review
  (escrita). Persistência offline de contas/apps/reviews.
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
  `workmanager` (Android); desktop = sync no launch + timer em processo + refresh manual.
  `flutter_local_notifications` para novos reviews / mudança de status; toque → deep link.
- **Fase 7 — Widgets & extras (por último):** widget de tela inicial Android via `home_widget`
  + código nativo Glance/AppWidget. Settings, License, polimento, passada completa de l10n.

## Concerns por plataforma / fora de escopo

- **iOS WidgetKit**: permanece no app nativo intocado — não reimplementado em Flutter.
- **Widget Android**: `home_widget` exige código nativo Glance/AppWidget em `flutter/android/`
  (Fase 7).
- **Widgets desktop**: não existem — fora de escopo.
- **Background quando fechado**: só Android (`workmanager`, ~15 min mín.). Desktop não tem API
  de background task → sync no launch + timer enquanto aberto + manual.
- **Notificações**: completas em Android/macOS/Linux; Windows best-effort; desktop só com app
  aberto. Pedir permissão em Android 13+.
- **Secure storage Linux**: precisa de libsecret + keyring; fallback de arquivo cifrado com
  passphrase para headless/CI.
- **Registro de deep link**: intent filter (Android), registro de protocolo (Windows),
  `CFBundleURLTypes` (macOS), `.desktop` MimeType (Linux) — via `app_links`.
- **Fora de escopo total**: target iOS, App Group, qualquer coisa WidgetKit/BGTask, reuso de
  Swift packages.

## Localização (reaproveitar `.xcstrings`)

Fonte: `StackConnect/Resources/Localizable.xcstrings` (catálogo JSON do Xcode), 13 idiomas
(en, de, es, es-MX, fr, it, ja, ko, nl, pt-BR, pt-PT, ru, sv, zh-Hant). Plano:
1. Script único em `flutter/tool/` lê o `.xcstrings` e gera um `app_<lang>.arb` por idioma,
   com fallback para `en`/chave quando `value` vazio.
2. Normalizar placeholders Apple (`%@`, `%lld`, `%1$@`) → ICU `{argN}` com metadados `@chave`.
3. Locales mapeiam direto (pt-BR, pt-PT, es-MX, zh-Hant válidos no Flutter); configurar
   `supportedLocales` + `localeResolutionCallback`.
4. `flutter gen-l10n` gera `AppLocalizations` tipado.

## Verificação / testes

- **Unit JWT/auth (prioridade máxima):** golden tests de `asc_jwt_signer` (ES256) e
  `google_jwt_signer` (RS256) com chave de teste; verificar header/claims/assinatura. Cache de
  token do `GoogleOAuthAuthenticator` (margem 60s) com Dio mockado.
- **Unit clientes API:** Dio mockado (`mocktail`) com fixtures JSON; assert URL/método/headers
  e mapeamento DTO→domínio; incluir paginação `links.next` e caminho do 403 pending-agreements.
- **Unit persistência:** `blob_store` em SQLite in-memory (`NativeDatabase.memory()`):
  `save/fetch/fetchAll/delete/deleteAll` + decode tolerante a campos novos.
- **Unit controllers/repos:** `ProviderContainer` com overrides; transições de `AsyncValue` e
  invalidação de dependentes em mutações.
- **Widget tests:** telas-chave (contas, reviews, add-account) com providers fixados.
- **Integração (`integration_test/`):** fluxo feliz (add account → apps → reviews) com rede
  stub, rodando em emulador Android e num target desktop (Linux no CI).
- **Deep-link:** unit do `deep_link_parser` nas 5 formas `stackconnect://`.
- **CI (GitHub Actions):** `build_runner`, `flutter analyze` (custom_lint/riverpod_lint),
  `flutter test`, build Linux desktop + `assembleDebug` Android.

## Primeiro passo concreto

Criar `flutter/` com
`flutter create --org <org> --platforms=android,windows,macos,linux flutter`, ajustar a
estrutura de pastas acima, configurar `pubspec.yaml`/codegen e entregar a Fase 0 (fundação)
antes de iniciar a Fase 1.
