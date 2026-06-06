# StackConnect — Plano de Port para Windows

> Objetivo: rodar o StackConnect no Windows **mantendo o iOS no mesmo código**, reaproveitando
> a lógica Swift existente. UI Windows em **SwiftCrossUI**. A UI iOS (SwiftUI) permanece.
>
> Premissa central: **SwiftUI não roda no Windows**. O que se compartilha é a *lógica* (Swift puro
> + Foundation + swift-crypto), nunca a camada de tela. Toda a UI Windows é reescrita.

---

## Estado atual (mapeamento do código real)

| Item | Onde está | Dependência Apple-only | Ação |
|------|-----------|------------------------|------|
| `AccountCrypto` (AES-GCM export `.scexport`) | `StackConnect/Infra/Crypto/` (target do app) | `CryptoKit`, `CommonCrypto`, `Security` | Mover p/ package + migrar p/ swift-crypto |
| `GoogleJWT` (RS256) | `Packages/APIProviderFirebase/.../JWT/` | `Security` (`SecKeyCreateSignature`) | Migrar p/ `_CryptoExtras` (`_RSA.Signing`) |
| `PlayJWT` (RS256) | `Packages/APIProviderPlay/.../JWT/` | `Security` | Migrar p/ `_CryptoExtras` |
| `FirebaseConfiguration` / `PlayConfiguration` | packages | `SecKey` + parsing PEM→DER manual | Trocar por `_RSA.Signing.PrivateKey(pemRepresentation:)` (simplifica) |
| `PersistentStorable` (protocolo) | `Packages/StackCore/` | Nenhuma (Foundation) | Mantém |
| `SwiftDataStorable` | `Packages/StackCore/` | `SwiftData` | Gate `#if canImport(SwiftData)` |
| `KeyStorable` (protocolo) | `StackConnect/Storage/` (target do app) | Nenhuma | **Mover p/ StackProtocols** |
| `KeychainStorable` | `StackConnect/Storage/` (target do app) | `Security` | Gate `#if canImport(Security)` |
| `netfox` | dep iOS DEBUG | UIKit | Excluir do Windows |
| `appstoreconnect-swift-sdk` | dep externa (fork) | a validar | **Gate de validação no Windows** |

Todos os `Package.swift` declaram `platforms: [.iOS(.v17)]` e nenhum produto cross-platform.

---

## Decisões técnicas-chave

### Crypto (substituição total CryptoKit/CommonCrypto/Security → swift-crypto)

Adotar **uma única** implementação para iOS e Windows (sem `#if`), via `apple/swift-crypto`:

- `AES.GCM`, `SHA256`, `HKDF`, `SymmetricKey` → produto **`Crypto`** (API idêntica à CryptoKit; troca `import CryptoKit` → `import Crypto`).
- **PBKDF2-SHA256** (hoje `CCKeyDerivationPBKDF`) → produto **`_CryptoExtras`**: `KDF.Insecure.PBKDF2.deriveKey(...)`.
- **Assinatura RS256** (hoje `SecKeyCreateSignature` PKCS1v1.5 SHA256) → **`_CryptoExtras`**: `_RSA.Signing.PrivateKey.signature(for:padding: .insecurePKCS1v1_5)`.
  - "insecure" é só o nome legado do padding PKCS#1 v1.5 — é exatamente o que RS256 exige.
- **Bytes aleatórios** (`SecRandomCopyBytes`) → `SystemRandomNumberGenerator` (CSPRNG em todas as plataformas).
- **Chave privada RSA**: `FirebaseConfiguration.loadRSAPrivateKey` (parsing manual PEM→PKCS#1→`SecKey`) vira `_RSA.Signing.PrivateKey(pemRepresentation:)`, que lê o PEM PKCS#8 do service account direto. Tipo do campo muda de `SecKey` → `_RSA.Signing.PrivateKey`.

> Nota: a App Store Connect API usa ES256 (P-256, chave `.p8`) e isso é assinado **dentro** do
> `appstoreconnect-swift-sdk`, não no nosso código. RS256/RSA é só do Firebase/Play.

**Rede de segurança:** os testes em `StackConnectTests/Crypto` devem continuar verdes — round-trip de
encrypt/decrypt e decriptação dos formatos legados v1/v2/v3 do `.scexport`. Nada de mudar o formato.

### Persistência (SwiftData no iOS, SQLite no Windows)

- `PersistentStorable` (já existe, Foundation puro) é a fronteira — não muda.
- `SwiftDataStorable` recebe gate `#if canImport(SwiftData)`.
- Nova `SQLitePersistentStorable` implementando o mesmo protocolo.
  - Modelo de dados hoje é um **blob key-value**: `PersistedItem(typeName, identifier, payload, updatedAt)`.
  - Tabela única: `persisted_item(type_name TEXT, identifier TEXT, payload BLOB, updated_at REAL, PRIMARY KEY(type_name, identifier))`.
  - Mesma estratégia de JSON-blob por `(typeName, id)`.
- **SQLite engine:** vendorizar a *amalgamation* do SQLite num C target (`CSQLite`) dentro do StackCore + wrapper Swift fino. Evita dependência externa de portabilidade incerta e compila em qualquer plataforma.
- **Bootstrap `shared`/`make`:** condicional por plataforma. iOS monta `ModelContainer`; Windows monta SQLite em `%APPDATA%\StackConnect\store.sqlite`.
- Replicar os métodos concretos com `typeName` explícito (usados hoje pelo widget) na impl SQLite, p/ manter uma única superfície de protocolo (o widget é iOS-only, mas evita divergência).

### Segredos (Keychain no iOS, Credential Manager no Windows)

- Mover o protocolo `KeyStorable` para `StackProtocols` (hoje no target do app).
- `KeychainStorable` recebe gate `#if canImport(Security)`.
- Nova `WindowsCredentialStorable` (`#if os(Windows)`) via `import WinSDK` → `CredWriteW`/`CredReadW`/`CredDeleteW` (Windows Credential Manager). Alternativa: DPAPI.

---

## Fases

### Fase 0 — Preparação (zero mudança de comportamento no iOS)
1. Mover protocolo `KeyStorable` → `Packages/StackProtocols`.
2. Mover `AccountCrypto` (+ `AccountCryptoError`) → package (StackCore ou novo `StackCrypto`). Tirar `String(localized:)` de dentro do crypto (devolver erro tipado; localizar na UI) — Foundation de localização é frágil no Windows.
3. Adicionar `.macOS(.v14)` aos `platforms` dos packages (permite build no host de dev) sem remover iOS.
4. `xcodegen generate --spec project.yml` e **confirmar que o iOS compila** + testes verdes.

### Fase 1 — Migração de crypto para swift-crypto (iOS continua verde)
1. Adicionar dependência `apple/swift-crypto` (produtos `Crypto` e `_CryptoExtras`) nos packages relevantes.
2. `AccountCrypto`: AES.GCM/SHA256/HKDF → `Crypto`; PBKDF2 → `_CryptoExtras`; random → `SystemRandomNumberGenerator`.
3. `GoogleJWT`, `PlayJWT`: `SecKeyCreateSignature` → `_RSA.Signing`.
4. `FirebaseConfiguration`, `PlayConfiguration`: `SecKey` → `_RSA.Signing.PrivateKey(pemRepresentation:)`.
5. Rodar `StackConnectTests/Crypto` — round-trip + decriptação de v1/v2/v3 **devem passar**. Esse é o critério de aceite da fase.

### Fase 2 — Abstração de storage + SQLite
1. Gate `#if canImport(SwiftData)` em `SwiftDataStorable`.
2. C target `CSQLite` (amalgamation vendorizada) + `SQLitePersistentStorable`.
3. Bootstrap `shared` condicional por plataforma.
4. Testes de storage cross-platform (mesma suíte rodando contra SQLite).

### Fase 3 — Validação no toolchain Windows (Prova de Conceito headless)
1. Instalar o Swift toolchain para Windows (swift.org) + Visual Studio Build Tools.
2. Executável headless ligando StackCore + APIProvider* + crypto que faça, no Windows:
   - carregar um service account, **assinar um JWT**, trocar por token, **1 chamada de API real**;
   - `save` + `fetch` no SQLite;
   - `WindowsCredentialStorable` write/read.
3. **Gate crítico:** validar se `appstoreconnect-swift-sdk` compila no Windows. Se não, decidir entre patch/fork ou reimplementar o client ASC com a mesma base swift-crypto (ES256).
4. Saída da fase: prova de que toda a stack não-UI roda no Windows.

### Fase 4 — UI Windows com SwiftCrossUI
1. Novo package executável `StackConnectWindows` dependendo de StackCore/StackProtocols/APIProvider* + `SwiftCrossUI` (backend WinUI).
2. Portar telas incrementalmente. **1ª tela = HOME** (decidido no refinamento de 2026-06-06; antes era "lista de contas"). Próximas: lista de contas → adicionar conta → detalhe.
3. Reusar ViewModels onde forem Foundation-puro; adaptar os que tocam SwiftUI/`@Published` ao modelo do SwiftCrossUI.

> **Refinamento da Home no Windows (2026-06-06):** `docs/refinements/2026-06-06-windows-home-screen.md` — paridade total ao iOS (cards + nav, banner de sync, alertas de expiração, sistema de widgets). 12 user stories, 30 tarefas (5 blocos), 92 casos de teste. Decisão central: extrair **`Packages/StackHomeCore`** (Foundation-puro: models + `HomeViewModel` + `SyncService` gateado + protocolo `HomeWidget` sem `makeView()` + 3 widgets) consumido por iOS **e** Windows; bridge Combine→callback/`AsyncStream`; split de `ProviderType`; novo `KeyStorable` em arquivo (`%APPDATA%`) p/ prefs não-secretas; `WindowsHomeCoordinator` (sem NavigationStack); alertas como InfoBar inline; rotas de destino = placeholders no v1; +7º gate (GUI Home) no `Test-WindowsPort.ps1`.

### Fase 5 — Empacotamento/distribuição (depois)
- Instalador MSIX / bundle, ícones, code signing Windows.

---

## Riscos & pontos de atenção
- **`appstoreconnect-swift-sdk` no Windows** — maior incógnita externa (Fase 3, gate).
- **`String(localized:)` / localização** no swift-corelibs-foundation do Windows — manter strings localizáveis na UI, não na lógica.
- **`@ModelActor` vs actor** — a impl SQLite será um `actor` próprio implementando `PersistentStorable: Sendable`; cuidar de concorrência no acesso ao handle do SQLite.
- **netfox** — manter sob `#if canImport(UIKit)` / DEBUG iOS; nunca linkar no Windows.
- **SwiftCrossUI** — projeto da comunidade, ainda imaturo; tratar a Fase 4 como a de maior esforço/risco de UX.

## Ordem recomendada de execução
Fase 0 → Fase 1 (com testes de crypto como rede) → Fase 2 → **Fase 3 (gate Windows)** → Fase 4.
Não investir em UI (Fase 4) antes do gate da Fase 3 passar.
