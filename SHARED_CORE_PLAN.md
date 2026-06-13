# Plano: Core compartilhado em Rust (iOS nativo + Flutter)

## Ideia central

Um único crate **Rust** `stack_core` concentra **toda a lógica** — clientes das 3 APIs
(App Store Connect / Firebase / Google Play), assinatura JWT (ES256/RS256), OAuth token cache,
persistência SQLite (blob store), sync, modelos de domínio e tradução de erros. Esse crate é
consumido **nativamente** por dois mundos, via dois geradores de *language bindings*:

```
                ┌──────────────── stack_core (Rust) ────────────────┐
                │  api · auth(JWT/OAuth) · storage(SQLite) · sync ·  │
                │  domain models · error translation                │
                └───────┬───────────────────────────────┬───────────┘
                        │                                 │
                  UniFFI (Swift)                  flutter_rust_bridge (Dart)
                        │                                 │
                  StackCore.xcframework            stack_core_dart (.so/.dll)
                        │                                 │
              iOS nativo: wrap em            Flutter: wrap em Riverpod
              @Observable → SwiftUI          AsyncNotifier → Material / Fluent
```

> ⚠️ **Muda a premissa "iOS intocado".** O app iOS deixa de usar seus packages Swift
> (`Packages/StackCore`, `Packages/APIProviderFirebase`, etc.) e passa a consumir o core Rust
> via XCFramework. Recomenda-se migração **incremental (strangler)**: trocar um provedor por vez
> atrás dos protocolos já existentes, mantendo o app compilável a cada passo.

## O que entra no core (Rust) vs. o que fica nativo

**Dentro do core (compartilhado):**
- `api/` — clientes Apple/Firebase/Play (HTTP tipado, paginação `links.next`, envelopes JSON:API).
- `auth/` — signers JWT ES256 (`.p8` Apple) e RS256 (service-account Google), `GoogleOAuthAuthenticator` (cache c/ margem 60s).
- `storage/` — blob store SQLite (`typeName+id+JSON`), equivalente ao `SwiftDataStorable`.
- `sync/` — `SyncService` (full vs. lightweight), diffs de mudança.
- `domain/` — modelos (structs `serde`), equivalentes a `StackConnect/Models/*.swift`.
- `error/` — tradução de erros (incl. 403 "pending agreements" do Apple).
- `routing/` — parser de deep link `stackconnect://` e tipos de rota (lógica pura, sem UI).

**Fica nativo por plataforma (NÃO entra no core):**
- Gerência de estado / controllers (Riverpod no Flutter, `@Observable`/`ObservableObject` no iOS).
- Widgets / Views; navegação concreta (`go_router` / `NavigationStack`).
- **Secure storage** — via *callback* (trait `CredentialStore`): Keychain (iOS), `flutter_secure_storage` (Flutter).
- Strings de UI / l10n (`.xcstrings` no iOS, `.arb` no Flutter). O core só carrega texto de domínio/erro se necessário.
- Charts, background scheduling (BGTask iOS / `workmanager` Android), notificações locais, widgets de home.

## Ferramentas / crates

**Lógica (Rust):**
- HTTP: `reqwest` (TLS via `rustls`).
- JWT: `jsonwebtoken` (ES256 + RS256, aceita PEM/`.p8` direto — simplifica vs. ASN.1 do Swift).
- JSON/modelos: `serde` + `serde_json`.
- SQLite: `rusqlite` (feature `bundled` — SQLite embarcado) ou `sqlx`.
- Async: `tokio`. Erros: `thiserror`. Datas: `time`/`chrono`. Utils: `uuid`, `base64`.

**Bindings:**
- **UniFFI** (Mozilla) → Swift. Anotações `#[uniffi::export]` (ou UDL). Suporta `async` →
  Swift `async/await`, *callback interfaces* (para o `CredentialStore`), enums de erro tipados.
  Build como static lib para os targets Apple → empacota **XCFramework** → consumido no app
  via SPM `binaryTarget`.
- **flutter_rust_bridge v2** → Dart. Codegen lê a API Rust e gera Dart idiomático: `async fn`
  → `Future`, streams → `Stream`, structs espelhadas, enums de erro. *DartFn* para callbacks.
  Build via `cargo-ndk` (Android `.so`) e cdylib (Windows `.dll` / Linux `.so`); integra com
  build hooks / native assets do Flutter.

**Padrão facade:** núcleo puro agnóstico de binding + `bindings/uniffi/` + `bindings/frb/`.
Cada facade adapta tipos ao que seu gerador prefere; o núcleo nunca depende de UniFFI/FRB.

## Build matrix (targets Rust)

- **Apple (iOS, + macOS se o app nativo macOS compartilhar):** `aarch64-apple-ios`,
  `aarch64-apple-ios-sim`, `x86_64-apple-ios` (sim Intel), `aarch64-apple-darwin`,
  `x86_64-apple-darwin` → unidos num `.xcframework`.
- **Android (Flutter):** `aarch64-linux-android`, `armv7-linux-androideabi`,
  `x86_64-linux-android` (via `cargo-ndk`).
- **Desktop (Flutter):** `x86_64-pc-windows-msvc`, `x86_64-unknown-linux-gnu` (+ `aarch64`).

## Estrutura no repositório

```
repo/
├── StackConnect/            (app iOS — passa a linkar StackCore.xcframework)
├── core/                    (Cargo workspace — o stack_core Rust)
│   ├── Cargo.toml
│   ├── crates/
│   │   └── stack_core/
│   │       ├── src/  api/ auth/ storage/ sync/ domain/ error/ routing/
│   │       └── tests/
│   ├── bindings/
│   │   ├── uniffi/          (facade + scaffolding Swift)
│   │   └── frb/             (facade + saída flutter_rust_bridge)
│   └── build/               (scripts: xcframework, cargo-ndk, codegen)
└── flutter/                 (ver FLUTTER_PLAN.md — apps consomem stack_core_dart)
    ├── packages/stack_core_dart/   (Dart gerado pelo FRB + libs nativas + controllers Riverpod)
    └── apps/stack_mobile  apps/stack_desktop
```

## Camadas por plataforma

| Camada | iOS nativo | Flutter |
|---|---|---|
| Core (lógica) | `stack_core` Rust (mesmo binário) | `stack_core` Rust (mesmo binário) |
| Binding | UniFFI → `StackCore.xcframework` | FRB → `stack_core_dart` |
| Estado | `@Observable`/ViewModel | Riverpod `AsyncNotifier` (controllers) |
| UI | SwiftUI | Material (`stack_mobile`) / Fluent (`stack_desktop`) |
| Secure storage | Keychain (impl. do `CredentialStore`) | `flutter_secure_storage` (impl. do `CredentialStore`) |
| Strings | `Localizable.xcstrings` | `.arb` / `AppLocalizations` |

## Migração do iOS (strangler, incremental)

1. Compilar o `stack_core` Rust + XCFramework e adicioná-lo ao `project.yml`.
2. Implementar o `CredentialStore` em Swift sobre o `KeychainStorable` atual.
3. Trocar **um provedor por vez** (ex.: primeiro App Store Connect) para chamar o core via
   binding, mantendo a mesma interface/protocolo que as ViewModels já consomem.
4. Migrados todos, remover os packages Swift `StackCore`/`APIProvider*` legados.

## Verificação / testes

- **Rust (grosso da cobertura):** unit de `api/` com HTTP mockado (`wiremock`/`mockito`) e
  fixtures JSON (URL/método/headers + DTO→domínio + paginação + 403 pending-agreements);
  golden de JWT ES256/RS256; cache OAuth (margem 60s); blob store em SQLite `:memory:`.
- **Bindings (smoke):** um teste por lado garantindo que a chamada atravessa a fronteira e
  retorna o tipo certo (Swift `XCTest` chamando o XCFramework; Dart test chamando o FRB).
- **Por plataforma:** ViewModels iOS e controllers Riverpod (Flutter) testados com o core
  mockado atrás do binding.

## CI (GitHub Actions)

- **Core:** `cargo test` + `cargo clippy` + `cargo fmt --check`; build do XCFramework; build
  Android `.so` via `cargo-ndk`; checagem de que o codegen FRB está atualizado.
- **Apps:** depois do core, builds por plataforma (iOS, `assembleDebug` Android, desktop Linux).

## Trade-offs / riscos

- **Terceira linguagem** (Rust) — curva de aprendizado da equipe.
- **Dois geradores de binding** para manter alinhados (mitigado pelo padrão facade).
- **Bridging async** e **build matrix** aumentam a complexidade de CI/tooling.
- Compensação: a lógica crítica (auth, API, persistência, sync) é escrita e **testada uma vez**
  e roda idêntica no iOS nativo e nos três alvos Flutter.
