import Foundation
import SwiftUI

// MARK: - AuthService
// Gerencia o estado de autenticação do app:
//   • Persistência do JWT no Keychain
//   • Person atual e organizationID no UserDefaults
//   • Disparo do fluxo Google OAuth (abre browser)
//   • Captura do token via deep-link munim://auth/callback?token=...

@Observable
@MainActor
final class AuthService {

    // MARK: - Chaves de persistência
    private enum Keys {
        static let jwtToken     = "munim.jwt.token"
        static let person       = "munim.current.person"
        static let orgID        = "munim.current.orgID"
    }

    // MARK: - Estado publicado
    var isAuthenticated: Bool = false
    var currentPerson: PersonDTO?
    var currentOrganizationID: String?
    var authError: String?

    // MARK: - Deep-link redirect para o app
    // O backend usará este valor como parâmetro ?redirect= no auth-url.
    // Ao retornar, o sistema abre munim://auth/callback?token=...
    private let callbackURL = "munim://auth/callback"

    // MARK: - Init: restaura sessão salva
    init() {
        restoreSession()
    }

    // MARK: - Restaurar sessão existente
    func restoreSession() {
        guard let token = KeychainHelper.read(forKey: Keys.jwtToken),
              !token.isEmpty else {
            isAuthenticated = false
            return
        }

        // Restaurar person
        if let data = UserDefaults.standard.data(forKey: Keys.person),
           let person = try? JSONDecoder().decode(PersonDTO.self, from: data) {
            currentPerson = person
        }

        // Restaurar orgID
        currentOrganizationID = UserDefaults.standard.string(forKey: Keys.orgID)

        // Injetar no APIClient
        APIClient.shared.bearerToken = token
        APIClient.shared.organizationID = currentOrganizationID

        isAuthenticated = true
    }

    // MARK: - Obter URL de autenticação Google
    // Retorna a authorizeURL para abrir no browser padrão.
    func fetchGoogleAuthURL() async throws -> URL {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encodedCallback = callbackURL.addingPercentEncoding(withAllowedCharacters: allowed) ?? callbackURL

        let dto: GoogleAuthURLDTO = try await APIClient.shared.request(
            "/api/auth/google/auth-url?redirect=\(encodedCallback)"
        )

        guard let url = URL(string: dto.authorizeURL) else {
            throw APIError.serverError("URL de autorização inválida recebida do servidor.")
        }
        return url
    }

    // MARK: - Processar callback com token (chamado pelo MunimApp via onOpenURL)
    func handleCallback(token: String, person: PersonDTO) {
        // Persistir token no Keychain
        KeychainHelper.save(token, forKey: Keys.jwtToken)

        // Persistir person no UserDefaults
        if let data = try? JSONEncoder().encode(person) {
            UserDefaults.standard.set(data, forKey: Keys.person)
        }

        // Injetar no APIClient (orgID será definido depois pelo OrganizationService)
        APIClient.shared.bearerToken = token

        currentPerson = person
        isAuthenticated = true
    }

    // MARK: - Definir organização ativa
    func setOrganization(id: String) {
        currentOrganizationID = id
        APIClient.shared.organizationID = id
        UserDefaults.standard.set(id, forKey: Keys.orgID)
    }

    // MARK: - Logout
    func logout() {
        KeychainHelper.delete(forKey: Keys.jwtToken)
        UserDefaults.standard.removeObject(forKey: Keys.person)
        UserDefaults.standard.removeObject(forKey: Keys.orgID)

        APIClient.shared.bearerToken = nil
        APIClient.shared.organizationID = nil

        currentPerson = nil
        currentOrganizationID = nil
        isAuthenticated = false
    }

    // MARK: - Excluir Conta e Dados (App Store 5.1.1(v))
    func deleteAccount() async throws {
        try await APIClient.shared.requestVoid("/api/auth/account", method: "DELETE")
        logout()
    }

    // MARK: - Parsear deep-link munim://auth/callback?token=... ou ?error=...
    // Retorna o token extraído da URL de callback, se válido.
    static func extractToken(from url: URL) -> String? {
        guard url.scheme == "munim",
              url.host == "auth",
              url.path == "/callback" else { return nil }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first(where: { $0.name == "token" })?.value
    }

    // Retorna o erro extraído da URL de callback, se presente.
    static func extractError(from url: URL) -> String? {
        guard url.scheme == "munim",
              url.host == "auth",
              url.path == "/callback" else { return nil }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first(where: { $0.name == "error" })?.value
    }

    /// Lê apenas os identificadores públicos do payload do JWT para associar o
    /// perfil retornado por `/api/people` à conta que acabou de autenticar.
    /// A validação e a autorização continuam sendo responsabilidade do backend.
    static func identity(from token: String) -> (personID: UUID?, email: String?) {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return (nil, nil) }

        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)

        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil)
        }

        let rawID = ["personID", "personId", "person_id", "userID", "userId", "sub"]
            .compactMap { claims[$0] as? String }
            .first
        let personID = rawID.flatMap(UUID.init(uuidString:))
        let email = ["email", "userEmail", "user_email"]
            .compactMap { claims[$0] as? String }
            .first

        return (personID, email)
    }
}
