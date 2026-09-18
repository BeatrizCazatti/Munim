import Combine
import SwiftUI

// MARK: - Aparência

enum InterfaceAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "settings.interfaceAppearance"
    var id: Self { self }
    var title: String {
        switch self {
        case .system: String(localized: "Automático")
        case .light: String(localized: "Claro")
        case .dark: String(localized: "Escuro")
        }
    }
    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon.stars"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

// MARK: - Sincronização

enum SyncInterval: String, CaseIterable, Identifiable {
    case realtime = "Tempo real (WebSocket)"
    case fiveMinutes = "A cada 5 minutos"
    case fifteenMinutes = "A cada 15 minutos"
    case thirtyMinutes = "A cada 30 minutos"
    case sixtyMinutes = "A cada 60 minutos"
    case manual = "Manual"

    var id: Self { self }

    var title: String {
        switch self {
        case .realtime: String(localized: "Tempo real (WebSocket)")
        case .fiveMinutes: String(localized: "A cada 5 minutos")
        case .fifteenMinutes: String(localized: "A cada 15 minutos")
        case .thirtyMinutes: String(localized: "A cada 30 minutos")
        case .sixtyMinutes: String(localized: "A cada 60 minutos")
        case .manual: String(localized: "Manual")
        }
    }

    /// Valor em minutos para enviar ao backend (nil = manual/realtime).
    var minutes: Int? {
        switch self {
        case .realtime: return nil
        case .fiveMinutes: return 5
        case .fifteenMinutes: return 15
        case .thirtyMinutes: return 30
        case .sixtyMinutes: return 60
        case .manual: return nil
        }
    }

    /// Cria a partir de minutos recebidos do backend.
    static func from(minutes: Int) -> SyncInterval {
        switch minutes {
        case 5: return .fiveMinutes
        case 15: return .fifteenMinutes
        case 30: return .thirtyMinutes
        case 60: return .sixtyMinutes
        default: return .sixtyMinutes
        }
    }

    var icon: String {
        switch self {
        case .realtime: "bolt.horizontal.fill"
        case .fiveMinutes: "5.circle"
        case .fifteenMinutes: "15.circle"
        case .thirtyMinutes: "30.circle"
        case .sixtyMinutes: "60.circle"
        case .manual: "hand.raised"
        }
    }
}

// MARK: - Conexão / Backend

enum ConnectionStatus: Equatable {
    case unknown
    case testing
    case online(pingMs: Int)
    case offline(reason: String)

    var title: String {
        switch self {
        case .unknown: String(localized: "Não verificado")
        case .testing: String(localized: "Verificando…")
        case .online(let ping): String(localized: "Online · \(ping) ms")
        case .offline: String(localized: "Offline")
        }
    }

    var color: Color {
        switch self {
        case .unknown: .secondary
        case .testing: .orange
        case .online: .green
        case .offline: .red
        }
    }

    var icon: String {
        switch self {
        case .unknown: "questionmark.circle"
        case .testing: "arrow.triangle.2.circlepath"
        case .online: "checkmark.circle.fill"
        case .offline: "xmark.circle.fill"
        }
    }

    var isHealthy: Bool {
        if case .online = self { return true }
        return false
    }
}

// MARK: - Google Workspace

enum GoogleScope: String, CaseIterable, Identifiable {
    case calendar = "Google Calendar"
    case gmail = "Gmail"
    case drive = "Google Drive"
    case chat = "Google Chat"
    case meet = "Google Meet"
    case directory = "Directory (Admin)"

    var id: Self { self }
    var icon: String {
        switch self {
        case .calendar: "calendar"
        case .gmail: "envelope"
        case .drive: "externaldrive"
        case .chat: "message"
        case .meet: "video"
        case .directory: "person.badge.key"
        }
    }
}

// MARK: - Integrações de terceiros

enum ThirdPartyIntegration: String, CaseIterable, Identifiable, Codable {
    case slack = "Slack"
    case notion = "Notion"

    var id: Self { self }
    var icon: String {
        switch self {
        case .slack: "number"
        case .notion: "doc.text"
        }
    }
    var accent: Color {
        switch self {
        case .slack: Color(red: 0.40, green: 0.22, blue: 0.91)
        case .notion: Color(red: 0.16, green: 0.16, blue: 0.18)
        }
    }
}

struct IntegrationAccount: Identifiable, Codable, Equatable {
    var id: UUID
    var integration: ThirdPartyIntegration
    var workspace: String
    var isConnected: Bool

    init(
        id: UUID = UUID(),
        integration: ThirdPartyIntegration,
        workspace: String,
        isConnected: Bool
    ) {
        self.id = id
        self.integration = integration
        self.workspace = workspace
        self.isConnected = isConnected
    }
}

// MARK: - Equipe

enum SettingsTeamRole: String, CaseIterable, Identifiable, Codable {
    case admin = "Admin"
    case member = "Membro"
    case observer = "Observador"

    var id: Self { self }

    var icon: String {
        switch self {
        case .admin: "key.fill"
        case .member: "person.fill"
        case .observer: "eye.fill"
        }
    }

    var tint: Color {
        switch self {
        case .admin: .accentColor
        case .member: .secondary
        case .observer: .gray
        }
    }
}

struct SettingsMember: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var email: String
    var team: String
    var role: SettingsTeamRole
    var isActive: Bool = true

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    /// Cria a partir de um PersonDTO real do backend.
    init(from person: PersonDTO, teamName: String) {
        self.id = person.id ?? UUID()
        self.name = person.name
        self.email = person.email ?? ""
        self.team = teamName
        self.role = person.jobTitle.lowercased().contains("gerente") ||
                    person.jobTitle.lowercased().contains("diretor") ||
                    person.jobTitle.lowercased().contains("lead") ? .admin : .member
        self.isActive = person.active
    }

    init(id: UUID = UUID(), name: String, email: String, team: String, role: SettingsTeamRole, isActive: Bool = true) {
        self.id = id
        self.name = name
        self.email = email
        self.team = team
        self.role = role
        self.isActive = isActive
    }
}

struct SettingsTeam: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var channels: [String]
    var memberCount: Int = 0

    init(id: UUID = UUID(), name: String, channels: [String] = [], memberCount: Int = 0) {
        self.id = id
        self.name = name
        self.channels = channels
        self.memberCount = memberCount
    }
}

// MARK: - DTOs de Integração para Settings

struct IntegrationSettingDTO: Codable {
    var id: UUID?
    var provider: String
    var name: String?
    var authType: String
    var scopes: [String]
    var services: [String]
    var isEnabled: Bool
    var oauthConnected: Bool
    var oauthAdminEmail: String?
    var syncIntervalMinutes: Int
    var createdAt: Date?
    var updatedAt: Date?
}

struct GoogleOAuthStatusDTO: Codable {
    var connected: Bool
    var adminEmail: String?
    var connectedAt: Date?
    var serviceAccountConfigured: Bool
}

struct SyncConfigDTO: Codable {
    var syncIntervalMinutes: Int
    var lastRanAt: Date?
}

struct UpdateSyncConfigRequest: Codable {
    let syncIntervalMinutes: Int
}

// MARK: - ViewModel

@MainActor
final class SettingsViewModel: ObservableObject {
    private enum Key {
        static let palette = "appTheme"
        static let appearance = InterfaceAppearance.storageKey
        static let decisions = "settings.notifyDecisions"
        static let tasks = "settings.notifyTasks"
        static let syncDatabase = "settings.syncDatabase"
        static let serverToken = "settings.serverToken"
        static let sensitivity = "settings.sensitivity"
        static let confirmation = "settings.confirmation"
    }

    private let defaults: UserDefaults

    // MARK: - Preferências locais (persistidas em UserDefaults)

    @Published var palette: AppTheme { didSet { defaults.set(palette.rawValue, forKey: Key.palette) } }
    @Published var appearance: InterfaceAppearance { didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) } }
    @Published var notifyDecisions: Bool { didSet { defaults.set(notifyDecisions, forKey: Key.decisions) } }
    @Published var notifyTasks: Bool { didSet { defaults.set(notifyTasks, forKey: Key.tasks) } }
    @Published var syncDatabase: Bool { didSet { defaults.set(syncDatabase, forKey: Key.syncDatabase) } }
    @Published var serverToken: String { didSet { defaults.set(serverToken, forKey: Key.serverToken) } }
    @Published var captureSensitivity: Double { didSet { defaults.set(captureSensitivity, forKey: Key.sensitivity) } }
    @Published var requiresSchedulingConfirmation: Bool { didSet { defaults.set(requiresSchedulingConfirmation, forKey: Key.confirmation) } }

    // MARK: - Dados do Backend (carregados via API)

    @Published var connectionStatus: ConnectionStatus = .unknown
    @Published var isLoadingBackend: Bool = false

    /// URL base real usada pelo APIClient
    var apiURL: String { APIConfig.baseURL.absoluteString }

    // Integração Google
    @Published var googleStatus: GoogleOAuthStatusDTO? = nil
    var googleEmail: String { googleStatus?.adminEmail ?? "" }
    var isGoogleConnected: Bool { googleStatus?.connected ?? false }
    @Published var googleScopes: Set<GoogleScope> = []

    // Sync interval do backend
    @Published var syncInterval: SyncInterval = .sixtyMinutes {
        didSet {
            Task { await pushSyncInterval() }
        }
    }
    private var isSyncIntervalLoading = false

    // Membros e times reais
    @Published var members: [SettingsMember] = []
    @Published var teams: [SettingsTeam] = []

    // Exclusão de conta (App Store 5.1.1(v))
    @Published var isDeletingAccount: Bool = false
    @Published var deleteAccountError: String? = nil

    // Terceiros (somente UI local por enquanto)
    @Published var integrations: [IntegrationAccount] = [
        IntegrationAccount(integration: .slack, workspace: "", isConnected: false),
        IntegrationAccount(integration: .notion, workspace: "", isConnected: false)
    ]

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        palette = AppTheme(storedValue: defaults.string(forKey: Key.palette) ?? AppTheme.defaultTheme.rawValue)
        appearance = InterfaceAppearance(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        notifyDecisions = Self.bool(defaults, Key.decisions, true)
        notifyTasks = Self.bool(defaults, Key.tasks, true)
        syncDatabase = Self.bool(defaults, Key.syncDatabase, true)
        serverToken = defaults.string(forKey: Key.serverToken) ?? ""
        captureSensitivity = Self.double(defaults, Key.sensitivity, 0.6)
        requiresSchedulingConfirmation = Self.bool(defaults, Key.confirmation, true)

        Task { await loadFromBackend() }
    }

    // MARK: - Carregamento do Backend

    func loadFromBackend() async {
        isLoadingBackend = true
        defer { isLoadingBackend = false }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadGoogleStatus() }
            group.addTask { await self.loadSyncConfig() }
            group.addTask { await self.loadTeamAndMembers() }
            group.addTask { await self.testConnection() }
        }
    }

    private func loadGoogleStatus() async {
        do {
            let status: GoogleOAuthStatusDTO = try await APIClient.shared.request(
                "/api/integrations/google/status"
            )
            googleStatus = status

            var activeScopes: Set<GoogleScope> = []

            if status.connected {
                // Directory e Chat só precisam de OAuth (sem service account)
                activeScopes.insert(.directory)
                activeScopes.insert(.chat)
            }

            if status.serviceAccountConfigured {
                // Gmail, Calendar e Drive exigem service account configurada
                activeScopes.insert(.gmail)
                activeScopes.insert(.calendar)
                activeScopes.insert(.drive)
            }

            googleScopes = activeScopes
        } catch {
            googleStatus = GoogleOAuthStatusDTO(
                connected: false, adminEmail: nil, connectedAt: nil, serviceAccountConfigured: false
            )
            googleScopes = []
        }
    }

    private func loadSyncConfig() async {
        do {
            let config: SyncConfigDTO = try await APIClient.shared.request(
                "/api/integrations/sync-config"
            )
            isSyncIntervalLoading = true
            syncInterval = SyncInterval.from(minutes: config.syncIntervalMinutes)
            isSyncIntervalLoading = false
        } catch {
            // Mantém o valor padrão
        }
    }

    private func loadTeamAndMembers() async {
        do {
            async let fetchedTeams: [TeamDTO] = APIClient.shared.request("/api/teams")
            async let fetchedPeople: [PersonDTO] = APIClient.shared.request("/api/people")

            let (teamsResult, peopleResult) = try await (fetchedTeams, fetchedPeople)

            let teamLookup = Dictionary(uniqueKeysWithValues: teamsResult.compactMap { t in t.id.map { ($0, t.name) } })

            members = peopleResult.map { person in
                let teamName: String
                if let teamID = person.teamID, let name = teamLookup[teamID] {
                    teamName = name
                } else {
                    teamName = "Sem time"
                }
                return SettingsMember(from: person, teamName: teamName)
            }

            teams = teamsResult.map { team in
                let count = peopleResult.filter { $0.teamID == team.id }.count
                return SettingsTeam(
                    id: team.id ?? UUID(),
                    name: team.name,
                    channels: [],
                    memberCount: count
                )
            }
        } catch {
            print("[SettingsViewModel] ❌ Erro ao carregar equipe: \(error)")
        }
    }

    private func pushSyncInterval() async {
        guard !isSyncIntervalLoading, let minutes = syncInterval.minutes else { return }
        let body = UpdateSyncConfigRequest(syncIntervalMinutes: minutes)
        let _: SyncConfigDTO? = try? await APIClient.shared.request(
            "/api/integrations/sync-config",
            method: "PUT",
            body: body
        )
    }

    // MARK: - Ações

    func testConnection() async {
        connectionStatus = .testing
        let start = Date()
        do {
            let _: [OrganizationDTO] = try await APIClient.shared.request("/api/organizations")
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            connectionStatus = .online(pingMs: ms)
        } catch {
            connectionStatus = .offline(reason: error.localizedDescription)
        }
    }

    func connectGoogle() async {
        do {
            let dto: GoogleAuthURLDTO = try await APIClient.shared.request(
                "/api/integrations/google/auth-url?redirect=munim://auth/callback"
            )
            if let url = URL(string: dto.authorizeURL) {
                await NSWorkspace.shared.open(url)
            }
        } catch {
            print("[SettingsViewModel] ❌ Erro ao obter URL de autenticação Google: \(error)")
        }
    }

    func disconnectGoogle() {
        googleStatus = GoogleOAuthStatusDTO(
            connected: false, adminEmail: nil, connectedAt: nil, serviceAccountConfigured: false
        )
        googleScopes = []
    }
    // MARK: - Exclusão de Conta (Guideline 5.1.1(v))

    func deleteAccount() async {
        do {
            try await APIClient.shared.requestVoid("/api/account")
            serverToken = ""
            disconnectGoogle()
        } catch {
            // Imprime o erro exato retornado pelo servidor Vapor ou pelo URLSession
            print("[SettingsViewModel] ❌ Falha ao excluir conta detalhada: \(error)")
        }
    }

    // MARK: - Excluir Conta e Dados (App Store Guideline 5.1.1(v))

    func deleteAccount(authService: AuthService) async -> Bool {
        await MainActor.run {
            isDeletingAccount = true
            deleteAccountError = nil
        }

        do {
            try await authService.deleteAccount()
            await MainActor.run {
                isDeletingAccount = false
            }
            return true
        } catch {
            await MainActor.run {
                deleteAccountError = error.localizedDescription
                isDeletingAccount = false
            }
            return false
        }
    }

    func toggleIntegration(_ integration: ThirdPartyIntegration) async {
        guard let index = integrations.firstIndex(where: { $0.integration == integration }) else { return }
        if integrations[index].isConnected {
            integrations[index].isConnected = false
            integrations[index].workspace = ""
        } else {
            try? await Task.sleep(for: .milliseconds(450))
            integrations[index].isConnected = true
            integrations[index].workspace = "\(integration.rawValue) · Workspace"
        }
    }

    func addMember(_ member: SettingsMember) {
        members.append(member)
    }

    func removeMember(_ member: SettingsMember) {
        members.removeAll { $0.id == member.id }
    }

    func updateRole(_ role: SettingsTeamRole, for member: SettingsMember) {
        guard let index = members.firstIndex(where: { $0.id == member.id }) else { return }
        members[index].role = role
    }

    func addChannel(_ channel: String, to team: SettingsTeam) {
        let value = channel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              let index = teams.firstIndex(where: { $0.id == team.id }),
              !teams[index].channels.contains(value) else { return }
        teams[index].channels.append(value)
    }

    func removeChannel(_ channel: String, from team: SettingsTeam) {
        guard let index = teams.firstIndex(where: { $0.id == team.id }) else { return }
        teams[index].channels.removeAll { $0 == channel }
    }

    // MARK: - Persistência local

    private func save<Value: Encodable>(_ value: Value, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func load<Value: Decodable>(_ type: Value.Type, _ defaults: UserDefaults, _ key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func bool(_ defaults: UserDefaults, _ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    private static func int(_ defaults: UserDefaults, _ key: String, _ fallback: Int) -> Int {
        defaults.object(forKey: key) as? Int ?? fallback
    }

    private static func double(_ defaults: UserDefaults, _ key: String, _ fallback: Double) -> Double {
        defaults.object(forKey: key) as? Double ?? fallback
    }
}

