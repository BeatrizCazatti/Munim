# Regras de Negócio — Ingestão do Google Chat

## Objetivo

Transformar mensagens relevantes do Google Chat em informações úteis para o Munim sem criar tarefas, reuniões, decisões ou mudanças de forma silenciosa. Toda sugestão gerada por inteligência artificial deve ser revisável, explicável e controlável pelo usuário.

## Princípio de produto

O Munim pode sincronizar comunicações para analisá-las, mas não deve transformar uma comunicação em um card do Dashboard sem uma decisão explícita do usuário. A criação automática de cards fica desativada por padrão.

## Fluxo principal

```text
Google Chat
    ↓
Sincronização de comunicações brutas
    ↓
Filtro de elegibilidade e deduplicação
    ↓
IA produz sugestões estruturadas
    ↓
Caixa de entrada “Para revisar” + notificação
    ↓
Usuário aprova, edita, ignora ou bloqueia a regra
    ↓
Card criado no Dashboard somente após aprovação
```

## Limite de privacidade

Há dois modos possíveis de ingestão, que devem ser configurados por organização:

1. **Revisão antes de criar card** — modo padrão. As mensagens são sincronizadas e armazenadas como comunicações brutas; a aprovação humana é exigida antes de gerar um card no Dashboard.
2. **Revisão antes de armazenar** — modo de privacidade elevada. As mensagens permanecem em área temporária de processamento e só são persistidas após aprovação. Este modo exige suporte específico do backend e pode limitar a análise em lote.

Enquanto o modo de privacidade elevada não existir no backend, “Ignorar” significa não criar um card nem reutilizar aquela comunicação em novas sugestões; não significa apagar uma comunicação já sincronizada.

## Critérios de elegibilidade da mensagem

Uma mensagem só pode seguir para análise quando todos os critérios abaixo forem atendidos:

- Pertence a uma organização autenticada e ativa.
- Veio de um espaço ou canal permitido pela organização.
- Não é mensagem de sistema, reação, evento automático ou conteúdo enviado por bot, salvo regra explícita de inclusão.
- Não pertence a canal privado ou conversa direta sem consentimento configurado.
- Possui identificador externo estável, autor e data/hora.
- Ainda não foi ignorada, aprovada ou processada pela mesma versão das regras de interpretação.
- Está dentro da janela de retenção definida pela organização.

## Deduplicação

- A chave de deduplicação deve conter, no mínimo, o provedor, o ID externo da mensagem e o ID da organização.
- Uma comunicação não pode gerar a mesma sugestão mais de uma vez para a mesma versão do classificador.
- Editar ou aprovar uma sugestão não pode recriá-la no próximo ciclo de sincronização.
- Quando uma mensagem for ignorada, o motivo e a regra de supressão devem ser persistidos para impedir novo alerta idêntico.

## Tipos de informação reconhecidos

| Tipo | Critério mínimo para sugerir |
|---|---|
| Tarefa | Ação concreta identificável, com verbo de ação e contexto suficiente. Responsável e prazo são desejáveis, mas não obrigatórios. |
| Reunião | Convite, compromisso ou combinação com data e horário claros. |
| Decisão | Escolha, aprovação, rejeição ou direcionamento inequívoco sobre uma alternativa. |
| Mudança | Alteração relevante de escopo, prazo, prioridade, processo, política ou estado de projeto. |

Mensagens vagas, conversas sociais, hipóteses sem encaminhamento, reações e conteúdo sem contexto suficiente não devem gerar sugestão.

## Confiança e encaminhamento

| Faixa de confiança | Comportamento |
|---|---|
| 85% a 100% | Criar sugestão com prioridade normal e mostrar na caixa de entrada. |
| 60% a 84% | Criar sugestão marcada como “Revisar com atenção”, exibindo a justificativa da IA. |
| Abaixo de 60% | Não exibir sugestão nem criar card. Manter apenas telemetria agregada, quando permitida. |

O limiar é configurável por organização. Mesmo na faixa alta, a IA não cria cards automaticamente no modo padrão.

## Estados da sugestão

```text
detectada → pendente_de_revisao → aprovada → criada
                         ├──────→ ignorada
                         ├──────→ rejeitada
                         └──────→ expirada
```

- **detectada**: comunicação elegível identificada pela sincronização.
- **pendente_de_revisao**: sugestão pronta para avaliação humana.
- **aprovada**: usuário confirmou a intenção; a criação do registro está autorizada.
- **criada**: card ou entidade de domínio foi persistido com sucesso.
- **ignorada**: usuário optou por não registrar a sugestão; pode incluir uma regra de não reapresentação.
- **rejeitada**: a classificação estava incorreta; deve alimentar melhoria do classificador, sem reutilizar conteúdo fora das regras de privacidade.
- **expirada**: não foi revisada dentro do prazo de retenção definido, sugerido em 30 dias.

## Ações disponíveis ao usuário

- **Aprovar**: cria o card com os dados sugeridos.
- **Editar e aprovar**: permite ajustar título, tipo, responsável, data, horário, local e prioridade antes de criar o card.
- **Ignorar**: não cria card e não reapresenta a mesma sugestão.
- **Nunca sugerir semelhantes**: cria regra de supressão por canal, autor, tipo ou padrão de conteúdo; a regra deve ser sempre reversível em Ajustes.
- **Ver origem**: mostra mensagem, autor, canal, data/hora e justificativa da classificação.

## Notificações

- Quando o Munim estiver em primeiro plano, usar banner interno com acesso à caixa de entrada.
- Quando estiver em segundo plano e houver sugestões pendentes novas, usar notificação nativa do macOS.
- A notificação deve informar quantidade e tipo de sugestões, sem expor conteúdo sensível na tela bloqueada.
- A ação principal abre a caixa de entrada; não aprova nem cria cards diretamente pela notificação.
- O usuário pode desativar notificações por tipo de sugestão, canal ou organização.

## Dados exigidos para auditoria

Cada sugestão deve registrar:

- organização, provedor e ID externo da mensagem;
- espaço/canal, autor e horário de origem;
- tipo sugerido, conteúdo estruturado e nível de confiança;
- justificativa curta da classificação;
- versão do modelo, prompt e regras aplicadas;
- estado atual, usuário que decidiu e data/hora da decisão;
- entidade criada após aprovação, quando existir.

Os dados de auditoria devem respeitar a política de retenção e exclusão da organização.

## Configurações por organização

- Modo de privacidade: revisão antes de criar ou revisão antes de armazenar.
- Canais e conversas permitidos.
- Inclusão ou exclusão de conversas diretas.
- Limiar de confiança.
- Tipos de card habilitados.
- Prazo de expiração das sugestões.
- Preferências de notificação.
- Regras de supressão por canal, autor, tipo ou padrão.

## Contrato mínimo esperado do backend

Para implementar o fluxo de revisão, o backend deve disponibilizar uma entidade de sugestão de ingestão e operações equivalentes a:

```text
GET    /api/ingestion-candidates
GET    /api/ingestion-candidates/:id
PATCH  /api/ingestion-candidates/:id       # editar dados sugeridos ou estado
POST   /api/ingestion-candidates/:id/approve
POST   /api/ingestion-candidates/:id/ignore
GET    /api/ingestion-settings
PUT    /api/ingestion-settings
```

`POST /api/ai/interpret` deve deixar de criar cards diretamente. Sua responsabilidade passa a ser criar ou atualizar sugestões pendentes, aplicando os critérios desta especificação.

## Critérios de aceite

- Nenhuma mensagem elegível gera card no Dashboard sem aprovação humana no modo padrão.
- Uma sugestão ignorada não retorna em sincronizações posteriores.
- O usuário consegue ver a origem e a justificativa de qualquer sugestão.
- Aprovada uma sugestão, o card correspondente é criado uma única vez.
- Falhas na criação não perdem a sugestão: ela retorna ao estado pendente ou aprovado com erro visível.
- As notificações não expõem conteúdo sensível fora do contexto do aplicativo.
