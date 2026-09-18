import Foundation

// MARK: - DashboardService
// Busca dados reais do backend para alimentar o Dashboard.
// Agrupa todas as entidades por equipes/times identificados.

@Observable
@MainActor
final class DashboardService {

    // MARK: - Estado
    var isLoading: Bool = false
    var isRefreshing: Bool = false
    var lastUpdated: Date?
    var boardColumns: [BoardColumn] = []
    var people: [PersonDTO] = []
    var teams: [TeamDTO] = []
    var tasks: [TaskDTO] = []
    var meetings: [MeetingDTO] = []
    var decisions: [DecisionDTO] = []
    var changes: [ChangeDTO] = []
    var error: String?

    // MARK: - Polling automático em background
    private var pollingTask: Task<Void, Never>?

    func startPolling(intervalSeconds: TimeInterval = 30) {
        stopPolling()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(intervalSeconds * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await self?.loadDashboard(silent: true)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Carregamento do Dashboard
    func loadDashboard(silent: Bool = false) async {
        guard !isLoading else { return }
        if !silent {
            isLoading = true
        }
        error = nil
        defer {
            if !silent {
                isLoading = false
            }
        }

        print("[DashboardService] 🚀 Iniciando carregamento do Dashboard (silent: \(silent))...")

        do {
            async let fetchedPeople: [PersonDTO] = APIClient.shared.request("/api/people")
            async let fetchedTeams: [TeamDTO] = APIClient.shared.request("/api/teams")
            async let fetchedTasks: [TaskDTO] = APIClient.shared.request("/api/tasks")
            async let fetchedMeetings: [MeetingDTO] = APIClient.shared.request("/api/meetings")
            async let fetchedDecisions: [DecisionDTO] = APIClient.shared.request("/api/decisions")

            let (p, t, tsk, m, d) = try await (
                fetchedPeople, fetchedTeams, fetchedTasks, fetchedMeetings, fetchedDecisions
            )
            people = p
            teams = t
            tasks = tsk
            meetings = m
            decisions = d

            let ch: [ChangeDTO] = (try? await APIClient.shared.request("/api/changes")) ?? []
            changes = ch

            print("[DashboardService] 📦 Dados recebidos: \(people.count) pessoas, \(teams.count) times, \(tasks.count) tarefas, \(meetings.count) reuniões, \(decisions.count) decisões, \(changes.count) mudanças.")

            // Montar as colunas divididas por EQUIPE/TIME (sem dados mockados)
            let teamColumns = TeamBoardBuilder.buildColumns(
                teams: teams,
                people: people,
                tasks: tasks,
                meetings: meetings,
                decisions: decisions,
                changes: changes
            )

            boardColumns = teamColumns
            lastUpdated = Date()
            print("[DashboardService] ✅ Dashboard pronto com \(boardColumns.count) colunas reais.")

        } catch let apiError as APIError {
            let msg: String
            switch apiError {
            case .unauthorized:
                return  // Tratado pelo middleware global (redirect para login)
            case .serverError(let reason) where reason.lowercased().contains("bad gateway")
                                           || reason.lowercased().contains("gateway"):
                msg = "Backend indisponível (502 Bad Gateway). Verifique se o serviço está rodando na VPS."
                DebugLogger.shared.log(msg, level: .error, category: "HTTP")
            case .serverError(let reason):
                msg = "Erro no servidor: \(reason)"
            case .networkError:
                msg = "Sem conexão com o servidor. Verifique a internet ou a VPS."
            default:
                msg = apiError.localizedDescription
            }
            print("[DashboardService] ❌ \(msg)")
            // Se já temos dados em cache, mantemos — não limpamos boardColumns
            if boardColumns.isEmpty {
                self.error = msg
            }
        } catch {
            print("[DashboardService] ❌ Erro inesperado ao carregar dashboard: \(error)")
            if boardColumns.isEmpty {
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: - Atualização completa (Sync → IA Interpret → IA Analyze → Recarregamento)
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // ── 1. Sincronização das integrações em background ─────────────────
        print("[DashboardService] 🔄 1. Sincronizando dados do Google Workspace em background...")
        DebugLogger.shared.log("Iniciando sincronização do Google Workspace (Directory e Chat)...", level: .info, category: "Sync")

        async let syncDir: Void = {
            let res: DirectorySyncResultDTO? = try? await APIClient.shared.request(
                "/api/integrations/directory/sync",
                method: "POST"
            )
            if let res {
                await DebugLogger.shared.log("Directory sincronizado: \(res.usersSynced) usuários, \(res.groupsSynced) grupos", level: .success, category: "Sync")
            }
        }()
        async let syncChat: Void = {
            let res: GoogleChatSyncResultDTO? = try? await APIClient.shared.request(
                "/api/integrations/google-chat/sync",
                method: "POST"
            )
            if let res {
                await DebugLogger.shared.log("Chat sincronizado: \(res.spacesSynced) espaços, \(res.messagesSynced) mensagens", level: .success, category: "Sync")
            }
        }()
        _ = await (syncDir, syncChat)

        // ── 2. Interpretação da IA (converte mensagens em tarefas, reuniões, decisões, mudanças) ─
        print("[DashboardService] 🧠 2. Executando interpretação de comunicações pela IA (/api/ai/interpret)...")
        DebugLogger.shared.log("Interpretando comunicações brutas para criar tarefas, reuniões e decisões (/api/ai/interpret)...", level: .info, category: "AI")
        do {
            let interpretResult: AIInterpretationResultDTO = try await APIClient.shared.request(
                "/api/ai/interpret",
                method: "POST"
            )
            DebugLogger.shared.log(
                "Interpretação concluída: \(interpretResult.tasksCreated) tarefas, \(interpretResult.meetingsCreated) reuniões, \(interpretResult.decisionsCreated) decisões, \(interpretResult.changesCreated) mudanças criadas.",
                level: .success,
                category: "AI"
            )
        } catch {
            print("[DashboardService] ⚠️ Interpretação da IA: \(error)")
            DebugLogger.shared.log(
                "Interpretação da IA: \(error.localizedDescription)",
                level: .warning,
                category: "AI"
            )
        }

        // ── 3. Executar análise geral da IA (/api/ai/analyze) ──────────────
        print("[DashboardService] 🤖 3. Executando análise geral da IA (/api/ai/analyze)...")
        do {
            let body = AnalyzeRequest(question: nil)
            let analysis: AIAnalysisDTO = try await APIClient.shared.request(
                "/api/ai/analyze",
                method: "POST",
                body: body
            )
            DebugLogger.shared.log(
                "Análise geral da IA concluída (\(analysis.type))",
                level: .success,
                category: "AI",
                details: analysis.content
            )
        } catch {
            print("[DashboardService] ⚠️ Análise geral da IA: \(error)")
        }

        // ── 4. Recarregar todos os dados reais do Dashboard ─────────────────
        print("[DashboardService] 📥 4. Recarregando dados do Dashboard...")
        await loadDashboard()
    }

    // MARK: - Atualizar status de uma tarefa
    func updateTaskStatus(taskID: UUID, newStatus: TaskStatus) async throws {
        let body = TaskStatusUpdateRequest(status: newStatus.rawValue)
        let _: TaskDTO = try await APIClient.shared.request(
            "/api/tasks/\(taskID.uuidString)/status",
            method: "PATCH",
            body: body
        )
        await loadDashboard()
    }

    // MARK: - Busca global
    func search(query: String) async throws -> SearchResultDTO {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw APIError.serverError("Query de busca não pode ser vazia.")
        }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return try await APIClient.shared.request("/api/search?q=\(encoded)")
    }

    // MARK: - CRUD Sincronizado com o Backend

    func createItem(draft: BoardItemDraft, teamName: String, category: DashboardItemCategory) async {
        let teamID = teams.first(where: { $0.name.lowercased() == teamName.lowercased() })?.id

        do {
            switch category {
            case .task:
                let newTask = TaskDTO(
                    id: nil,
                    title: draft.title,
                    description: draft.description,
                    owner: draft.assigneeID,
                    deadline: draft.scheduledAt,
                    priority: draft.priority.rawValue.capitalized,
                    status: "Todo",
                    relatedProject: nil,
                    team: teamID,
                    modality: draft.location.isEmpty ? nil : draft.location,
                    origin: "manual",
                    confidence: 1.0
                )
                let saved: TaskDTO = try await APIClient.shared.request("/api/tasks", method: "POST", body: newTask)
                tasks.append(saved)

            case .meeting:
                let newMeeting = MeetingDTO(
                    id: nil,
                    title: draft.title,
                    date: draft.scheduledAt,
                    time: draft.scheduledAt.formatted(date: .omitted, time: .shortened),
                    location: draft.location.isEmpty ? nil : draft.location,
                    meetingLink: nil,
                    meetingType: "Geral",
                    participants: draft.assigneeID.map { [$0] } ?? [],
                    agenda: draft.description.isEmpty ? nil : draft.description,
                    confidence: 1.0
                )
                let saved: MeetingDTO = try await APIClient.shared.request("/api/meetings", method: "POST", body: newMeeting)
                meetings.append(saved)

            case .decision:
                let newDecision = DecisionDTO(
                    id: nil,
                    summary: draft.title,
                    rationale: draft.description,
                    date: draft.scheduledAt,
                    people: draft.assigneeID.map { [$0] } ?? [],
                    relatedProject: nil,
                    attachments: [],
                    confidence: 1.0
                )
                let saved: DecisionDTO = try await APIClient.shared.request("/api/decisions", method: "POST", body: newDecision)
                decisions.append(saved)

            case .change:
                let newChange = ChangeDTO(
                    id: nil,
                    description: draft.title,
                    changeType: draft.location.isEmpty ? "Atualização" : draft.location,
                    date: draft.scheduledAt,
                    relatedProject: nil,
                    confidence: 1.0
                )
                let saved: ChangeDTO = try await APIClient.shared.request("/api/changes", method: "POST", body: newChange)
                changes.append(saved)
            }

            // Reconstruir colunas do board
            boardColumns = TeamBoardBuilder.buildColumns(
                teams: teams,
                people: people,
                tasks: tasks,
                meetings: meetings,
                decisions: decisions,
                changes: changes
            )
        } catch {
            print("[DashboardService] ❌ Erro ao criar item: \(error)")
        }
    }

    func updateItem(itemID: BoardItem.ID, draft: BoardItemDraft) async throws {
        // A UI já foi atualizada de forma otimista em DashboardView.
        // Aqui apenas persistimos no backend e atualizamos o array interno de DTOs,
        // SEM reconstruir boardColumns para não sobrescrever o estado local da UI.
        if let taskIndex = tasks.firstIndex(where: { $0.id == itemID }) {
            var task = tasks[taskIndex]
            task.title = draft.title
            task.description = draft.description
            task.owner = draft.assigneeID
            task.deadline = draft.scheduledAt
            task.priority = draft.priority.rawValue.capitalized
            task.modality = draft.location.isEmpty ? nil : draft.location
            let saved: TaskDTO = try await APIClient.shared.request("/api/tasks/\(itemID)", method: "PUT", body: task)
            tasks[taskIndex] = saved
        } else if let meetingIndex = meetings.firstIndex(where: { $0.id == itemID }) {
            var meeting = meetings[meetingIndex]
            meeting.title = draft.title
            meeting.date = draft.scheduledAt
            meeting.time = draft.scheduledAt.formatted(date: .omitted, time: .shortened)
            meeting.participants = draft.assigneeID.map { [$0] } ?? []
            meeting.agenda = draft.description.isEmpty ? nil : draft.description
            meeting.location = draft.location.isEmpty ? nil : draft.location
            let saved: MeetingDTO = try await APIClient.shared.request("/api/meetings/\(itemID)", method: "PUT", body: meeting)
            meetings[meetingIndex] = saved
        } else if let decisionIndex = decisions.firstIndex(where: { $0.id == itemID }) {
            var decision = decisions[decisionIndex]
            decision.summary = draft.title
            decision.rationale = draft.description
            decision.date = draft.scheduledAt
            decision.people = draft.assigneeID.map { [$0] } ?? []
            let saved: DecisionDTO = try await APIClient.shared.request("/api/decisions/\(itemID)", method: "PUT", body: decision)
            decisions[decisionIndex] = saved
        } else if let changeIndex = changes.firstIndex(where: { $0.id == itemID }) {
            var change = changes[changeIndex]
            change.description = draft.title
            change.date = draft.scheduledAt
            if !draft.location.isEmpty {
                change.changeType = draft.location
            }
            let saved: ChangeDTO = try await APIClient.shared.request("/api/changes/\(itemID)", method: "PUT", body: change)
            changes[changeIndex] = saved
        } else {
            throw APIError.notFound
        }
        // Não reconstruir boardColumns aqui: a UI otimista já representa o estado salvo.
    }

    func deleteItem(itemID: BoardItem.ID) async {
        // A remoção visual já foi feita em DashboardView (optimistic delete).
        // Aqui apenas persistimos no backend e removemos do array de DTOs.
        if let taskIdx = tasks.firstIndex(where: { $0.id == itemID }) {
            let _: EmptyResponseDTO? = try? await APIClient.shared.request("/api/tasks/\(itemID)", method: "DELETE")
            tasks.remove(at: taskIdx)
        } else if let meetingIdx = meetings.firstIndex(where: { $0.id == itemID }) {
            let _: EmptyResponseDTO? = try? await APIClient.shared.request("/api/meetings/\(itemID)", method: "DELETE")
            meetings.remove(at: meetingIdx)
        } else if let decisionIdx = decisions.firstIndex(where: { $0.id == itemID }) {
            let _: EmptyResponseDTO? = try? await APIClient.shared.request("/api/decisions/\(itemID)", method: "DELETE")
            decisions.remove(at: decisionIdx)
        } else if let changeIdx = changes.firstIndex(where: { $0.id == itemID }) {
            let _: EmptyResponseDTO? = try? await APIClient.shared.request("/api/changes/\(itemID)", method: "DELETE")
            changes.remove(at: changeIdx)
        }
        // ✅ NÃO rebuildar boardColumns aqui — o item já foi removido da UI localmente.
    }
}

struct EmptyResponseDTO: Decodable {}

// MARK: - DTOs de Interpretação e Análise da IA

struct AIInterpretationResultDTO: Decodable {
    var communicationsProcessed: Int
    var entitiesFound: Int
    var tasksCreated: Int
    var meetingsCreated: Int
    var decisionsCreated: Int
    var changesCreated: Int
    var evidencesLinked: Int
    var responseContent: String?
}

// MARK: - SearchResultDTO
struct SearchResultDTO: Decodable {
    let query: String
    let tasks: [TaskDTO]
    let projects: [ProjectDTO]
    let people: [PersonDTO]
    let teams: [TeamDTO]
    let meetings: [MeetingDTO]
    let decisions: [DecisionDTO]
    let changes: [ChangeDTO]
    let communications: [CommunicationDTO]
}

// MARK: - DTOs adicionais referenciados pelo SearchResultDTO

struct ProjectDTO: Identifiable, Codable {
    var id: UUID?
    var name: String
    var description: String
    var status: String
    var startDate: Date
    var endDate: Date?
    var people: [UUID]
    var confidence: Double
}

struct ChangeDTO: Identifiable, Codable {
    var id: UUID?
    var description: String
    var changeType: String
    var date: Date
    var relatedProject: UUID?
    var confidence: Double
}

struct CommunicationDTO: Identifiable, Codable {
    var id: UUID?
    var channel: String
    var source: String
    var subject: String?
    var content: String
    var receivedAt: Date
    var summary: String?
    var confidence: Double
}
