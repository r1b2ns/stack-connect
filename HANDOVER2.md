# StackConnect — Port para Windows · Handoff

Feature: portar o StackConnect (iOS/SwiftUI) para **Windows**, compartilhando a
lógica e reescrevendo só a UI.

**Estado:** Fases 0–3 **concluídas e validadas numa VM Windows real** (Swift 6.3.2,
aarch64-windows-msvc). Toda a camada não-UI compila e roda no Windows.
**Fase 4 — Bloco A ✅ (A1+A2), B1a ✅ e B1b-1 (build) ✅ validados na VM.** Na última run da VM **os 6 gates passaram** (todo o stack não-UI + app headless roda com store em `%APPDATA%\StackConnect\store.sqlite`, **e a GUI SwiftCrossUI/WinUI compila**). O bloqueio de symlinks do git foi resolvido (`core.symlinks false` / Developer Mode / Admin). **Bloqueio atual: RODAR a janela.** O `.exe` builda e inicia, mas o backend WinUI aborta no bootstrap do **Windows App Runtime 1.5** (o swift-winui 0.2.0 fixa o SDK 1.5; app *unpackaged* precisa do **DDLM de 1.5** e a VM só tem DDLM de 2.x). **Correção recomendada: dar identidade de pacote (MSIX) ao app** — ver §8. HEAD `9118da2`.

---

## 1. Repositórios

| Repo | Remote | Branch | HEAD | Estado |
|------|--------|--------|------|--------|
| Principal | `git@github.com:r1b2ns/stack-connect.git` | `experiment/windows` | `9118da2` | limpo, pushado |
| Fork do SDK | `git@github.com:r1b2ns/appstoreconnect-swift-sdk.git` | `windows-support` | `885bacc4` | pushado |

- **Mac:** `/Users/rubensmachion/repos/Open/stack-connect`
- **VM Windows:** `C:\Users\ruben\OneDrive\Desktop\repos\stack-connect` (toolchain Swift 6.3.2 instalado)
- O app Windows (Fase 4) **deve depender do branch `windows-support`** do fork do SDK.

### Commits do port (`experiment/windows`)
| Hash | Fase | Conteúdo |
|------|------|----------|
| `9bdae86` | 0 | `AccountCrypto` extraído p/ package `StackCrypto` |
| `f197f4e` | 1 | Crypto migrado p/ `swift-crypto` (PBKDF2, RS256, AES-GCM) |
| `9ce6d74` | 2 | `SQLitePersistentStorable` + `SwiftData` gateado + `PersistentStorable`→`StackProtocols` |
| `5e6d9a8` | 3 | PoC headless (`WindowsPoC/` + `ASCBuildProbe/`) |
| `7ec90f6` | 3 | `import FoundationNetworking` nos providers |
| `1a34d15` | 3 | Fix `WindowsSecretsProbe` (Win32 `BOOL`→`Bool`) |
| `494c0a4` | 3 | `ASCBuildProbe` aponta p/ branch `windows-support` do fork |
| `2204807` / `f1bc12f` | 3 | `Test-WindowsPort.ps1`: log em arquivo, `-Clean`, captura stderr |
| `e29fc22` | 4·A1 | `KeyStorable` → `StackProtocols` (público, zero churn) |
| `96cdd39` | 4 | Fix infra: `link: false` nas deps de package do test target (destrava `xcodebuild test` no Xcode 26) |
| `bffbac6` | 4 | Testes atualizados (export v3 + fixtures v2; Firebase exige JSON) → suíte 60/60 |
| `5726f96` | 4·A2 | Package `StackSecretsWindows` (`WindowsCredentialStorable`) |
| `bc2dc22` | 4·A2 | Gate de VM `WindowsCredentialStoreProbe` (KeyStorable) |
| `5115e1b` | 4·B1a | Executável headless `StackConnectWindows` (stack não-UI + bootstrap) |
| `f6cae86` | 4·B1a | Build do app via `--scratch-path` curto (MAX_PATH no Windows) |
| `85dcc85` → `9ecb9d1` | 4·B1b | Janela mínima SwiftCrossUI; GUI isolada em package próprio `StackConnectWindowsApp` |
| `9118da2` | 4·B1b | Script seta `git core.symlinks=false` antes do gate GUI |

Fork (`windows-support`): `2990e673` (OpenCombine condicional) → `885bacc4` (**Combine opcional — é o que faz o SDK compilar no Windows**).

---

## 2. O que já funciona no Windows (6 gates do `Test-WindowsPort.ps1`)

Rodar na VM: `.\Test-WindowsPort.ps1 -Pull -Clean` (use `-SkipSDK` p/ pular o build longo do SDK + a bootstrap do app que dependem do fork).

| # | Gate | Resultado na VM | O que prova |
|---|------|-----------------|-------------|
| 1 | Core (`WindowsPoC` → `StackConnectWindowsPoC`) | **PASS** | SQLite CRUD, AES-GCM/PBKDF2, RS256 sign/verify, PEM round-trip |
| 2 | Secrets (`WindowsPoC` → `WindowsSecretsProbe`) | **PASS** | Windows Credential Manager (write/read/delete) via WinSDK |
| 3 | Credential store (`WindowsPoC` → `WindowsCredentialStoreProbe`) | **PASS** | **A2:** `WindowsCredentialStorable` via `KeyStorable` |
| 4 | SDK ASC (`ASCBuildProbe` → `swift build`) | **PASS** (~280 s) | `appstoreconnect-swift-sdk` compila no Windows |
| 5 | App headless (`StackConnectWindows` → `swift run`) | **PASS** | **B1a:** stack não-UI inteira linka num exe + bootstrap abre o store em `%APPDATA%` |
| 6 | GUI (`StackConnectWindowsApp` → `swift build`) | **PASS** (build) | **B1b:** SwiftCrossUI/WinUI compila no Windows (symlinks resolvidos via `core.symlinks=false` / Developer Mode) |
| — | GUI **rodar** a janela (`swift run`) | ❌ **bloqueado** | bootstrap do Windows App Runtime 1.5 falha (DDLM 1.5 ausente) — ver **§8** |

### 4 armadilhas de portabilidade encontradas e resolvidas
1. **`FoundationNetworking`** — `URLRequest`/`URLSession`/`HTTPURLResponse` ficam nesse módulo fora da Apple. Solução: `#if canImport(FoundationNetworking) import FoundationNetworking` (nos dois `APIProvider*`).
2. **Win32 `BOOL` = `Bool` nativo** no WinSDK do Swift (sem `.boolValue`).
3. **Combine é Apple-only e o OpenCombine não tem módulo utilizável no Windows.** No SDK era usado só no `rateLimitPublisher`; no fork, virou opcional via `#if canImport(Combine) || canImport(OpenCombine)`.
4. **MAX_PATH (260) no Windows** — o `StackConnectWindows` puxa o SDK ASC (nomes OpenAPI gigantes) + BoringSSL do swift-crypto; sob `OneDrive\Desktop\repos\...\StackConnectWindows\.build\...` o path estoura 260 (erro `missing inputs: \\?\C:\?\C:\…Paths…Localizations.swift`). Solução: buildar com `--scratch-path <curto>` (o `Test-WindowsPort.ps1` usa `C:\Users\<você>\.scw`). O gate do `ASCBuildProbe` escapa só por ter path mais curto.

---

## 3. Fase 4 — progresso (Bloco A ✅ · B1a ✅ · B1b em andamento)

Ordem seguida: **Bloco A no Mac (mantém iOS verde) → Bloco B na VM.**

### Bloco A — infraestrutura não-UI (Mac)

**A1 · Mover `KeyStorable` → `StackProtocols`** ✅ **FEITO** (não commitado)
- `StackConnect/Storage/KeyStorable.swift` **removido**; criado `Packages/StackProtocols/Sources/StackProtocols/KeyStorable.swift` com protocolo + métodos + extension `object`/`setObject` agora **`public`**.
- **Zero churn confirmado**: nenhum consumidor editado — o umbrella `StackCoreExports.swift` (`@_exported import StackProtocols`) já expõe o protocolo. `KeychainStorable`/`UserDefaultsStorable` (app) e `MockKeyStorable` (testes via `@testable import StackConnect`) seguem compilando sem `import`.
- `KeychainStorable` (`import Security`) ficou no app target como impl iOS.
- `xcodegen generate --spec project.yml` rodado.
- **Validação:** `swift build` do `StackProtocols` → **Build complete**; `xcodebuild build` do app iOS → **BUILD SUCCEEDED**; `xcodebuild test` → **58 testes, 5 falhas pré-existentes** (não introduzi nenhuma; baseline idêntico no HEAD `f1bc12f`).
- 🔧 **Bônus (fix de infra, no `project.yml`):** o `xcodebuild test` estava quebrado de forma pré-existente sob Xcode 26.4.1 — o test target linkava `StackCrypto`/`StackCore`, forçando a variante dinâmica `_PackageProduct.framework` do swift-crypto (que falha ao linkar; o app linka esses packages **estaticamente**). Corrigido marcando as deps de package do test target com `link: false` (o bundle roda no host via `TEST_HOST`/`-bundle_loader`; só precisa dos módulos em compile-time). Rodar `xcodegen generate` após editar.
- ✅ **5 falhas pré-existentes corrigidas e commitadas** (`bffbac6`): testes atualizados ao comportamento atual (export v3 + fixtures v2 legados; Firebase exige Service Account JSON). Suíte completa **60/60 verde**.

**A2 · `WindowsCredentialStorable`** ✅ **FEITO** (não commitado até este ponto → ver commit)
- Novo package **`Packages/StackSecretsWindows`** (depende só de `StackProtocols`, **fora do `project.yml`**, versionado como `StackStorageSQLite`).
- `WindowsCredentialStorable: KeyStorable` — `public final class`. Codificação espelha `KeychainStorable` (String→utf8; Int/Double→bytes via `withUnsafeBytes`, leitura com `loadUnaligned`; Bool→1 byte; Data→raw). `object`/`setObject` vêm da extension default do `StackProtocols`. TargetName = `"<service>:<key>"`, `service` default `"app.stackconnect"`.
- Corpo Win32 (`CredWriteW/CredReadW/CredDeleteW`, `import WinSDK`) sob `#if os(Windows)` — mesmas chamadas já validadas na VM pelo `WindowsSecretsProbe`. Em não-Windows há um **fallback in-memory** (com `NSLock`) só para build/teste no host — nunca entra no app iOS.
- **Validação (Mac):** `swift build` → **Build complete**; `swift test` → **11/11**.
- ✅ **Validado na VM Windows real:** novo probe `WindowsPoC` → `WindowsCredentialStoreProbe` (4º gate do `Test-WindowsPort.ps1`) exercita o `WindowsCredentialStorable` **através do protocolo `KeyStorable`** (string/int/double/bool/data/object/remove). `.\Test-WindowsPort.ps1 -Pull -Clean` → **4/4 gates PASS** (commit `bc2dc22`). Caminho Win32 (`CredWriteW/ReadW/DeleteW`) confirmado no Windows. **A2 100% fechado.**

### Bloco B — app Windows (precisa da VM)
- **B1a** ✅ **FEITO E VALIDADO NA VM** (esqueleto headless, sem UI) — package `StackConnectWindows/` (raiz, fora do `project.yml`) com **todas** as deps não-UI: `StackProtocols`, `StackCrypto`, `StackStorageSQLite`, `StackSecretsWindows`, `APIProviderFirebase`, `APIProviderPlay` e o **SDK ASC via `branch: "windows-support"`**. `main.swift` headless roda o bootstrap (B2) + smoke de storage/secrets/crypto + link-check dos providers e do SDK. **VM:** `Test-WindowsPort.ps1` gate 5 → **PASS**; store abriu em `C:\Users\…\AppData\Roaming\StackConnect\store.sqlite` (`%APPDATA%`). Toda a stack não-UI linka e roda num executável no Windows. (Build na VM via `--scratch-path` curto — ver armadilha 4 do MAX_PATH.)
- **B1b-1** ✅ **FEITO (validar na VM)** — janela mínima SwiftCrossUI, em **package PRÓPRIO** `StackConnectWindowsApp/` (raiz, separado do headless). Dep `moreSwift/swift-cross-ui` `.upToNextMinor(from: "0.7.0")` (`tools-version 5.10`); `SwiftCrossUI` + `DefaultBackend` (auto = WinUI no Windows, AppKit no Mac). `StackConnectApp.swift`: 1 janela + contador. **Mac:** `swift build` → **Build complete**. Gate **6** no `Test-WindowsPort.ps1` (`swift build --scratch-path $env:USERPROFILE\.scwapp`, build-only).
  - ⚠️ **Por que package separado:** o `DefaultBackend` resolve as deps de **todos** os backends (incl. AndroidKit/swift-java) → grafo enorme. Na 1ª tentativa o GUI estava no mesmo package do headless e **regrediu o gate 5** (a resolução do swift-cross-ui contaminava o headless). Isolando, o headless volta verde.
  - 🚫 **Bloqueio na VM:** deps transitivas do SwiftCrossUI (`swift-argument-parser`, `swift-java`, `jpeg`) têm **symlinks**; o git do Windows recusa criá-los (`unable to create symlink … Permission denied`) → a resolução falha **antes de compilar**. **Fix:** `git config --global core.symlinks false` (escreve os symlinks como arquivos comuns; só existem em dirs de plugin/sample/test). O `Test-WindowsPort.ps1` agora **seta isso automaticamente** antes do gate 6 — mas como o `-Pull` atualiza o script durante a run, a automação só vale **a partir da run seguinte**. Para destravar na hora: `git config --global core.symlinks false` manual + `-Clean`. (Provavelmente ainda exigirá o **Windows App SDK runtime** para *rodar* a janela — confirmar após o build passar.)
  - ✅ **Validado na VM: os 6 gates PASS** — gate 6 (GUI) destravou. O bloqueio era de privilégio de symlink do usuário Windows: `core.symlinks=false` faz o git escrever os symlinks como arquivos comuns; alternativa equivalente é **Developer Mode** ou terminal **Admin** (concede `SeCreateSymbolicLinkPrivilege`, aí os symlinks são criados de fato). Se `core.symlinks=false` não pegar, suspeitar de cache global do SwiftPM (`%LOCALAPPDATA%\org.swift.swiftpm`) ou de o setting não ter sido aplicado (confira com `git config --global --get core.symlinks`).
  - 🔎 **Investigação descartada:** trocar `stackotter/swift-java` pelo upstream `swiftlang/swift-java` **não** ajuda — (a) `swift-java` é só dep do `AndroidKit` (backend Android do SwiftCrossUI), **nunca compila no Windows**, só é clonado; (b) o upstream tem os **mesmos symlinks**; (c) o `AndroidKit` exige os produtos `JavaKit*` que **só o fork tem** (o upstream renomeou tudo p/ `SwiftJava*`) → trocar quebraria a resolução. Symlink é transversal (`jpeg`, `swift-argument-parser` também) → o fix é `core.symlinks=false`.
  - Ver a janela: `swift run --scratch-path $env:USERPROFILE\.scwapp StackConnectWindowsApp`.
- **B1b-2** · 1ª tela real (lista de contas) reusando ViewModel Foundation-puro + `Bootstrap`/storage. ⚠️ **SwiftCrossUI é imaturo** — maior risco; isolado de propósito.
- **B2** ✅ feito no B1a (`Bootstrap.makeEnvironment()` + `AppPaths`): no Windows abre `SQLitePersistentStorable(path:)` em `%APPDATA%\StackConnect\store.sqlite` + `WindowsCredentialStorable`. (Ref. iOS: `StackConnectApp.swift:35-37`, widget `WidgetDataLoader.swift:82-83`.)
- **B3** · Portar telas incrementalmente: lista de contas → adicionar conta → detalhe.

---

## 4. Arquitetura (decisões fechadas — não reabrir sem motivo)

- **UI Windows:** SwiftCrossUI. SwiftUI não roda no Windows; só a lógica é compartilhada.
- **Crypto:** 100% `swift-crypto`. `Crypto` (AES-GCM/SHA256/HKDF) + `_CryptoExtras` (`KDF.Insecure.PBKDF2`, `_RSA.Signing`); random via `SystemRandomNumberGenerator`. Formato `.scexport` inalterado (PBKDF2-HMAC-SHA256 é determinístico → arquivos v1/v2/v3 antigos seguem legíveis).
- **Storage:** `PersistentStorable` em `StackProtocols` (Foundation-only). `SwiftDataStorable`/`PersistedItem` gateados `#if canImport(SwiftData)` (no-op no iOS). Windows = `SQLitePersistentStorable` (actor) em `StackStorageSQLite` (SQLite 3.53.1 vendorizada no C target `CSQLite`); tabela `persisted_item(type_name, identifier, payload, created_at, updated_at)`, mesmo modelo JSON-blob do SwiftData.
- **Umbrella:** `StackConnect/Infra/StackCoreExports.swift` faz `@_exported import StackCore` + `@_exported import StackProtocols` → o app vê os protocolos sem `import` por arquivo (por isso mover protocolos não causa churn).
- **Packages Windows fora do `project.yml`:** `StackStorageSQLite` (e futuros `StackSecretsWindows`/`StackConnectWindows`) não entram no projeto iOS. O iOS segue 100% SwiftData/Keychain.

### Layout
```
Packages/
  StackProtocols/      Foundation-only. PersistentStorable + KeyStorable (A1). Cross-platform.
  StackCrypto/         AccountCrypto sobre swift-crypto.
  StackCore/           SwiftDataStorable, PersistedItem (gateados), Log… iOS na prática (os/UIKit).
  StackStorageSQLite/  SQLitePersistentStorable + CSQLite. Fora do project.yml.
  StackSecretsWindows/ WindowsCredentialStorable (KeyStorable via Credential Manager, A2). Win32 sob #if os(Windows) + fallback in-memory no host. Fora do project.yml.
  APIProviderFirebase/ RS256 via _RSA.Signing; FoundationNetworking.
  APIProviderPlay/     idem.
WindowsPoC/            PoC headless: StackConnectWindowsPoC + WindowsSecretsProbe + WindowsCredentialStoreProbe.
ASCBuildProbe/         Gate de compilação do SDK ASC (branch windows-support).
StackConnectWindows/      Executável headless (B1a): stack não-UI + bootstrap. Fora do project.yml. (gate 5)
StackConnectWindowsApp/   Executável GUI (B1b): SwiftCrossUI + DefaultBackend. Package PRÓPRIO (isolado do grafo do SwiftCrossUI). tools 5.10. (gate 6)
Test-WindowsPort.ps1   Roda os 6 gates na VM. (-Pull, -Clean, -SkipSDK; scratch curto p/ MAX_PATH; seta core.symlinks p/ gate 6; logs *.log gitignored)
docs/windows-port-plan.md   Plano completo das fases (gitignored, local).
```

---

## 5. Validações no Mac (host)
- `swift test` `StackStorageSQLite` → **8/8**; `StackSecretsWindows` → **11/11** (fallback in-memory).
- `swift build` `StackCrypto`/`APIProviderFirebase`/`APIProviderPlay`/`StackProtocols` → OK.
- `swift run StackConnectWindowsPoC` (macOS) → **All checks passed**.
- `swift run StackConnectWindows` (macOS) → **Bootstrap OK** (5/5 checks; backend AppKit p/ a parte que precisa).
- `swift build --product StackConnectWindowsApp` (macOS) → **Build complete** (SwiftCrossUI via AppKit backend).
- iOS: `xcodebuild build`/`test` (`StackConnect Development`) → **BUILD SUCCEEDED** + **60/60**.
- `swift build` do fork (`windows-support`, macOS) → **Build complete** (no-op nas plataformas Apple).

## 6. Regras do projeto
- **Nunca** commitar/pushar sem ordem direta (repo principal **e** fork). Sem atribuição "Claude"/"Generated with".
- iOS = **XcodeGen**: `xcodegen generate --spec project.yml` após criar/remover arquivos do app target ou mudar deps. Packages Windows não entram no `project.yml`.
- `docs/`, `HANDOVER.md` e `Test-WindowsPort-*.log` são **gitignored** (ficam locais).

## 7. Retomar
Nova sessão no repo: *"Leia o HANDOVER.md — continuar a Fase 4 do port Windows. Build da GUI SwiftCrossUI já passa (6/6 gates). Falta RODAR a janela: o bootstrap do Windows App Runtime 1.5 falha — aplicar a correção da §8 (identidade de pacote MSIX) e então seguir pro B1b-2 (1ª tela: lista de contas)."*

**Passo imediato na VM** (tentar rodar a janela):
```powershell
cd C:\Users\<você>\OneDrive\Desktop\repos\stack-connect\StackConnectWindowsApp
swift run --scratch-path $env:USERPROFILE\.scwapp StackConnectWindowsApp
```
- Se a janela **abrir** → seguir para **B1b-2** (lista de contas reusando ViewModel Foundation-puro + `Bootstrap`/storage).
- Se abortar com *"Windows App Runtime not found / Failed to initialize WindowsAppRuntimeInitializer: Major.Minor=1.5"* → **aplicar a §8** (é o estado atual).

Arquivo é gitignored; se a sessão for na VM Windows, traga-o via pasta compartilhada do VMware.

---

## 8. Bloqueio atual: rodar a janela WinUI (Windows App Runtime 1.5 / DDLM)

**Sintoma** (ao `swift run StackConnectWindowsApp` na VM — o build passa, o `.exe` inicia e aborta):
```
Windows App Runtime not found on system, and no installer was present to install it
  (expected at 'WindowsAppRuntimeInstaller.exe')
Failed to initialize WindowsAppRuntimeInitializer: Major.Minor=1.5, Tag=, MinVersion=0.0.0.0
WinUI/SwiftApplication.swift:64: Fatal error: fatal
```

**Causa raiz (confirmada):**
- O app é **unpackaged** (sem identidade MSIX) → o swift-winui chama `MddBootstrapInitialize2` pedindo **Windows App SDK 1.5** (`MinVersion 0.0.0.0`). Código: `swift-winui/Sources/WinAppSDK/Initialize.swift` (versão pedida nas linhas ~112-121; mensagens de erro ~128; **early-return se o processo tem identidade** nas linhas **103-105**).
- **swift-winui 0.2.0 é a última versão e fixa o SDK 1.5 hard-coded** (bundla `Microsoft.WindowsAppRuntime.Bootstrap.dll` + header `WINDOWSAPPSDK_RELEASE_MAJORMINOR 0x00010005`). swift-cross-ui 0.7.0 (última) usa essa swift-winui. **Não dá pra "subir de versão" pra fugir do 1.5.**
- App unpackaged + `MddBootstrap` exige o **DDLM (Dynamic Dependency Lifetime Manager)** da versão pedida. A VM tem **DDLM só de 2.x** (`2.1.3.0`, `2.0.0.2`); **nenhum DDLM de 1.x**.
- A VM tem **Framework 1.5 + Main 1.5** (`5001.373.1736.0`, Arm64) presentes, mas **sem DDLM 1.5** → o bootstrapper reporta "no match".

**O que já foi tentado e NÃO resolve (não repetir):**
- Instalar o redistribuível oficial `windowsappruntimeinstall-arm64.exe` (1.5) — inclusive **elevado + `--force`** → sempre `ExitCode 0` mas **nunca cria o DDLM de 1.5** (o framework já está presente como dependência inbox, então o instalador faz no-op no DDLM; o runtime 2.x parece bloquear o provisionamento do DDLM 1.x).
- **Remover o 1.5 pra reinstalar limpo NÃO é possível:** `Remove-AppxPackage` → `0x80073CF3` porque `Microsoft.StartExperiencesApp` (app inbox do Windows) depende do framework 1.5.
- Pôr `WindowsAppRuntimeInstaller.exe` ao lado do `.exe` (plano B do swift-winui) roda o **mesmo** instalador → mesmo no-op. Não adianta.

### ✅ Correção recomendada: dar **identidade de pacote (MSIX)** ao app
Com identidade, `processHasIdentity()` no swift-winui retorna `true` e ele **pula o bootstrapper inteiro** (Initialize.swift:103-105), resolvendo o framework 1.5 (já instalado) **pelo manifesto** — sem precisar de DDLM. É também como o app vai ser distribuído de verdade.

Dois caminhos (preferir o swift-bundler):

1. **swift-bundler** (ferramenta do mesmo autor do SwiftCrossUI, recomendada pra empacotar GUI no Windows). Gera o `.msix`/app com identidade. Investigar/instalar na VM:
   - `swift-bundler` (https://github.com/stackotter/swift-bundler) — criar um `Bundler.toml` pro produto `StackConnectWindowsApp`, declarar a dependência do framework `Microsoft.WindowsAppRuntime.1.5` e empacotar. Validar os comandos exatos na VM (a CLI evolui).

2. **Sparse package manual** (fallback, mais trabalhoso, 100% sob controle): criar um `AppxManifest.xml` com `<Identity .../>` + `<PackageDependency Name="Microsoft.WindowsAppRuntime.1.5" MinVersion="5001.373.1736.0" Publisher="CN=Microsoft Corporation, ..."/>`, empacotar com `MakeAppx.exe`, assinar com um cert de dev (`MakeCert`/`signtool` ou `New-SelfSignedCertificate`) e registrar apontando pro dir do exe:
   ```powershell
   Add-AppxPackage -Path .\StackConnectWindowsApp.msix -ExternalLocation <pasta-do-.exe>
   ```
   Depois rodar o `.exe` registrado (já com identidade → bootstrapper é pulado).

**Antes de partir pra MSIX, teste barato:** o `Main 1.5` foi instalado depois da 1ª falha — então rode `swift run ... StackConnectWindowsApp` **mais uma vez**; se por acaso a janela abrir, o item está resolvido e pula-se a §8. (Improvável sem o DDLM, mas é 1 comando.)

**Verificações úteis na VM:**
```powershell
Get-AppxPackage *DDLM* | Select Name, Version, Architecture          # hoje: só 2.x
Get-AppxPackage *WinAppRuntime*1.5*, *WindowsAppRuntime.1.5* | Select Name, Version, Architecture
```

Quando a janela abrir, atualizar §2 (gate "GUI rodar" → PASS) e seguir para **B1b-2** (1ª tela: lista de contas).
