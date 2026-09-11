# Munim — Regras do Projeto

## Identidade e compatibilidade

- Nome do produto, target e esquema: `Munim`.
- Plataforma mínima documentada: macOS 26.5. Não reduzir esse requisito sem testes explícitos na versão pretendida.
- SwiftUI exclusivamente; não introduzir AppKit salvo quando uma API nativa do macOS não estiver disponível em SwiftUI.
- Preferir APIs modernas de Swift e SwiftUI compatíveis com a versão mínima do projeto.

## Interface e acessibilidade

- Preservar a aparência nativa do macOS: usar `Window` Scene para Configurações, em janela independente e não modal.
- Manter o atalho `⌘,` para abrir Configurações via `CommandGroup(after: .appSettings)`.
- Usar SF Symbols para ícones de interface; não adicionar ícones rasterizados customizados como substitutos. Ilustrações e imagens de conteúdo podem usar os assets do catálogo.
- Respeitar Dark Mode e utilizar cores semânticas do catálogo através de `Color.Token`; não repetir strings de assets ou valores de cor nas views quando já houver token.
- A cor de destaque e elementos de marca devem vir de `AppTheme` e dos tokens do tema ativo. Não usar `AccentColor` da Apple como fonte de verdade.
- Em preferências, usar `Form { }.formStyle(.grouped)` e `LabeledContent` para pares rótulo/controle quando aplicável.
- Toda tipografia de produto deve usar `AdaptiveTextStyle`, preservando a hierarquia semântica apropriada a cada texto (`.largeTitle`, `.title`, `.headline`, `.body`, `.caption`, etc.). Usar `.font` diretamente apenas quando houver necessidade tipográfica pontual e justificada, como texto monoespaçado ou prévia de escala.
- Garantir que novos controles tenham rótulos e valores acessíveis; imagens decorativas devem ser ocultadas da acessibilidade.

## Arquitetura e estado

- Usar MVVM e `@Observable` para serviços e view models. Não criar novos `ObservableObject`, `@Published` ou `@StateObject`; ao modificar código legado, preferir migrá-lo quando o escopo permitir.
- View models e serviços que alteram estado de interface devem ser `@MainActor`.
- Injetar dependências de app compartilhadas pelo ambiente SwiftUI quando fizer sentido, como `AuthService` e `AppTheme`.
- Manter a lógica de apresentação nas views e a lógica de negócio, carregamento e mutação nos serviços/view models.
- Views podem conter subviews privadas e componentes pequenos no mesmo arquivo. Criar arquivo próprio para views reutilizáveis ou suficientemente complexas.

## Persistência e segurança

- Segredos, tokens e credenciais pertencem ao Keychain. Nunca gravá-los em `UserDefaults`, código-fonte, logs ou assets.
- Preferências simples pertencem a `@AppStorage`/`UserDefaults`.
- Estado local estruturado pode ser persistido em `UserDefaults` com `JSONEncoder`/`JSONDecoder` e chaves centralizadas.
- Dados de domínio são propriedade do backend; mocks servem apenas para preview, desenvolvimento ou testes, nunca como fallback silencioso na interface de produção.

## Rede, autenticação e backend

- Centralizar requisições HTTP em `APIClient`; não duplicar configuração de URL, headers, codificação, decodificação ou tratamento de erro nas views e serviços.
- `APIClient` é responsável pelos headers `Authorization`, `X-Organization-ID`, `Accept` e `Content-Type` quando aplicável.
- Usar DTOs em `Shared/Models/DTOs/` para contratos do backend. Não acoplar views diretamente a payloads improvisados.
- Tratar `401` pelo fluxo global de autenticação e logout; não implementar redirecionamentos concorrentes em telas individuais.
- Não expor JWTs, informações sensíveis ou corpos completos de respostas em logs de produção.

## Modelos

- Modelos de domínio persistidos ou trocados com a API devem adotar `Codable`; usar `Identifiable` quando forem exibidos em coleções SwiftUI.
- Enums serializados devem usar `String` como `RawValue`; adicionar `CaseIterable` e `Identifiable` quando usados em `Picker` ou listas.
- Para modelos com `id: UUID`, preferir `init(id: UUID = UUID())` explícito quando necessário para manter a síntese correta de `Codable`.
- Não atribuir valores padrão a propriedades armazenadas que precisam ser decodificadas, exceto com inicializador/decodificação explícitos que preservem o contrato.

## Estrutura do código

```
Munim/
├── MunimApp.swift
├── Networking/                 # APIConfig, APIClient e APIError
├── Services/                   # autenticação, organização, dashboard, keychain e logs
├── Screens/
│   ├── Onboarding/
│   ├── Dashboard/
│   ├── Attachments/
│   ├── Settings/
│   └── Debug/
├── Shared/
│   ├── Components/
│   ├── Models/DTOs/
│   ├── Mocks/
│   ├── Theme/
│   └── AdaptiveTextStyle.swift
├── Views/
├── Assets.xcassets/
└── Munim.entitlements
```

- Organizar funcionalidades em `Screens/<Feature>/`, separando `Views`, `Models`, `ViewModels` e `Components` quando a complexidade justificar.
- Manter componentes compartilhados em `Shared/Components/`, tokens e temas em `Shared/Theme/`, e contratos de API em `Shared/Models/DTOs/`.

## Qualidade e entrega

- Não alterar arquivos não relacionados à solicitação do usuário.
- Antes de entregar uma alteração, executar o build e corrigir erros introduzidos pela mudança.
- Executar os testes relevantes quando houver cobertura ou quando a mudança afetar comportamento testável; informar claramente testes não executados e o motivo.
- Comandos usuais, executados na raiz que contém `Munim.xcodeproj`:

```sh
xcodebuild -project Munim.xcodeproj -scheme Munim -configuration Debug build
xcodebuild -project Munim.xcodeproj -scheme Munim -configuration Debug test
open Munim.xcodeproj
```
