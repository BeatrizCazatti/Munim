import SwiftUI

// MARK: - DebugInspectorView
// Painel visual para testes rápidos, inspeção de rotas da API e logs em tempo real.

struct DebugInspectorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var authService

    @State private var debugLogger = DebugLogger.shared
    @State private var selectedTab: DebugTab = .logs
    @State private var selectedLog: DebugLogger.LogEntry?
    @State private var filterLevel: DebugLogger.LogLevel?
    @State private var searchText: String = ""
    @State private var testResultText: String = String(localized: "Clique em um endpoint para testar a resposta.")
    @State private var isTesting: Bool = false

    enum DebugTab: String, CaseIterable {
        case logs = "Logs ao Vivo"
        case endpoints = "Testar Endpoints"
        case session = "Sessão & Headers"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top Bar
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "ladybug.fill")
                        .foregroundColor(.purple)
                    Text("Painel de Diagnóstico & Integração")
                        .font(.headline)
                }

                Spacer()

                Picker("", selection: $selectedTab) {
                    ForEach(DebugTab.allCases, id: \.self) { tab in
                        Text(LocalizedStringKey(tab.rawValue)).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 360)

                Spacer()

                Button("Fechar") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Tab Content
            switch selectedTab {
            case .logs:
                logsTab
            case .endpoints:
                endpointsTab
            case .session:
                sessionTab
            }
        }
        .frame(minWidth: 850, minHeight: 550)
    }

    // MARK: - Logs Tab

    private var logsTab: some View {
        HSplitView {
            // Lista de logs
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    TextField("Filtrar logs...", text: $searchText)
                        .textFieldStyle(.roundedBorder)

                    Picker("Nível", selection: $filterLevel) {
                        Text("Todos").tag(nil as DebugLogger.LogLevel?)
                        ForEach(DebugLogger.LogLevel.allCases, id: \.self) { level in
                            Text(level.rawValue).tag(level as DebugLogger.LogLevel?)
                        }
                    }
                    .frame(width: 110)

                    Button("Limpar") {
                        debugLogger.clear()
                        selectedLog = nil
                    }

                    Button {
                        let fullText = debugLogger.logs.map { "[\($0.formattedTime)][\($0.category)][\($0.level.rawValue)] \($0.message)\n\($0.details ?? "")" }.joined(separator: "\n---\n")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(fullText, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .help("Copiar todos os logs")
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                List(selection: $selectedLog) {
                    ForEach(filteredLogs) { log in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: log.level.icon)
                                .foregroundColor(log.level.color)
                                .font(.system(size: 12))
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(log.category)
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(log.level.color.opacity(0.15))
                                        .cornerRadius(4)

                                    Text(log.formattedTime)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)

                                    Spacer()
                                }

                                Text(log.message)
                                    .font(.system(size: 12, design: .monospaced))
                                    .lineLimit(2)
                            }
                        }
                        .tag(log)
                        .padding(.vertical, 2)
                    }
                }
            }
            .frame(minWidth: 380)

            // Detalhe do log selecionado
            VStack(alignment: .leading, spacing: 8) {
                if let log = selectedLog {
                    HStack {
                        Image(systemName: log.level.icon)
                            .foregroundColor(log.level.color)
                        Text(log.message)
                            .font(.headline)
                        Spacer()
                    }
                    .padding([.top, .horizontal], 12)

                    Divider()

                    ScrollView {
                        Text(log.details ?? "Nenhum detalhe adicional disponível.")
                            .font(.system(size: 11, design: .monospaced))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                } else {
                    ContentUnavailableView(
                        "Selecione um log",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Clique em uma entrada à esquerda para inspecionar os detalhes brutos da resposta HTTP.")
                    )
                }
            }
            .frame(minWidth: 320)
            .background(Color(NSColor.textBackgroundColor))
        }
    }

    private var filteredLogs: [DebugLogger.LogEntry] {
        debugLogger.logs.filter { log in
            if let level = filterLevel, log.level != level {
                return false
            }
            if !searchText.isEmpty {
                let matchMsg = log.message.localizedCaseInsensitiveContains(searchText)
                let matchDet = log.details?.localizedCaseInsensitiveContains(searchText) ?? false
                let matchCat = log.category.localizedCaseInsensitiveContains(searchText)
                return matchMsg || matchDet || matchCat
            }
            return true
        }
    }

    // MARK: - Endpoints Tab

    private var endpointsTab: some View {
        HSplitView {
            // Lista de ações
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                        Text("Diagnóstico & Rotas Públicas")
                            .font(.subheadline.bold())
                            .foregroundColor(.secondary)

                        testButton(title: "GET /health", desc: "Checa se a API está online") {
                            await runRawTest(path: "/health")
                        }
                    }

                    Divider()

                    Group {
                        Text("Entidades da Organização")
                            .font(.subheadline.bold())
                            .foregroundColor(.secondary)

                        testButton(title: "GET /api/organizations", desc: "Lista todas as organizações") {
                            await runJSONTest(path: "/api/organizations")
                        }

                        testButton(title: "GET /api/teams", desc: "Lista todos os times identificados") {
                            await runJSONTest(path: "/api/teams")
                        }

                        testButton(title: "GET /api/people", desc: "Lista as pessoas da equipe") {
                            await runJSONTest(path: "/api/people")
                        }

                        testButton(title: "GET /api/tasks", desc: "Lista as tarefas") {
                            await runJSONTest(path: "/api/tasks")
                        }

                        testButton(title: "GET /api/meetings", desc: "Lista as reuniões") {
                            await runJSONTest(path: "/api/meetings")
                        }

                        testButton(title: "GET /api/decisions", desc: "Lista as decisões") {
                            await runJSONTest(path: "/api/decisions")
                        }

                        testButton(title: "GET /api/changes", desc: "Lista as mudanças") {
                            await runJSONTest(path: "/api/changes")
                        }
                    }

                    Divider()

                    Group {
                        Text("Sincronização & Seed")
                            .font(.subheadline.bold())
                            .foregroundColor(.secondary)

                        testButton(title: "POST /api/integrations/directory/sync", desc: "Importa usuários e grupos do Workspace") {
                            await runJSONTest(path: "/api/integrations/directory/sync", method: "POST")
                        }

                        testButton(title: "POST /api/integrations/google-chat/sync", desc: "Importa canais do Google Chat") {
                            await runJSONTest(path: "/api/integrations/google-chat/sync", method: "POST")
                        }

                        testButton(title: "POST /seed/demo-company", desc: "Popula o banco com dados de demonstração") {
                            await runJSONTest(path: "/seed/demo-company", method: "POST")
                        }
                    }
                }
                .padding(16)
            }
            .frame(minWidth: 320, maxWidth: 380)

            // Painel de resposta do teste
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Resultado da Requisição")
                        .font(.headline)
                    Spacer()
                    if isTesting {
                        ProgressView().controlSize(.small)
                    }
                    Button("Copiar JSON") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(testResultText, forType: .string)
                    }
                    .disabled(testResultText.isEmpty)
                }
                .padding([.top, .horizontal], 12)

                Divider()

                ScrollView {
                    Text(testResultText)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .frame(minWidth: 400)
            .background(Color(NSColor.textBackgroundColor))
        }
    }

    private func testButton(title: String, desc: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task {
                isTesting = true
                await action()
                isTesting = false
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                Text(desc)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
        .buttonStyle(.bordered)
    }

    private func runRawTest(path: String) async {
        do {
            let url = URL(string: path, relativeTo: APIConfig.baseURL)!
            let (data, _) = try await URLSession.shared.data(from: url)
            testResultText = String(data: data, encoding: .utf8) ?? "<vazio>"
        } catch {
            testResultText = "Erro: \(error)"
        }
    }

    private func runJSONTest(path: String, method: String = "GET") async {
        do {
            guard let url = URL(string: path, relativeTo: APIConfig.baseURL) else { return }
            var req = URLRequest(url: url)
            req.httpMethod = method
            if let token = APIClient.shared.bearerToken {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            if let orgID = APIClient.shared.organizationID {
                req.setValue(orgID, forHTTPHeaderField: "X-Organization-ID")
            }
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0

            if let json = try? JSONSerialization.jsonObject(with: data),
               let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                testResultText = "HTTP \(status)\n\n" + prettyString
            } else {
                testResultText = "HTTP \(status)\n\n" + (String(data: data, encoding: .utf8) ?? "<não decodificável>")
            }
        } catch {
            testResultText = "Erro: \(error)"
        }
    }

    // MARK: - Session Tab

    private var sessionTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                infoCard(title: "Configuração do Servidor", rows: [
                    ("Base URL", APIConfig.baseURL.absoluteString),
                    ("Status de Auth", authService.isAuthenticated ? "✅ Autenticado" : "❌ Desconectado"),
                    ("Organização ID Ativa", APIClient.shared.organizationID ?? "Nenhuma selecionada")
                ])

                if let person = authService.currentPerson {
                    infoCard(title: "Usuário Logado", rows: [
                        ("Nome", person.name),
                        ("Cargo", person.jobTitle),
                        ("E-mail", person.email ?? "Não informado"),
                        ("Ativo", person.active ? "Sim" : "Não"),
                        ("ID", person.id?.uuidString ?? "-")
                    ])
                }

                infoCard(title: "Segurança & Token", rows: [
                    ("Bearer Token", APIClient.shared.bearerToken.map { "\($0.prefix(20))... (\($0.count) chars)" } ?? "Nenhum token em memória")
                ])
            }
            .padding(20)
        }
    }

    private func infoCard(title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(rows, id: \.0) { row in
                    HStack(alignment: .top) {
                        Text(row.0)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 140, alignment: .leading)

                        Text(row.1)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
}

#Preview {
    DebugInspectorView()
        .environment(AuthService())
}
