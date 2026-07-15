import Foundation

struct ServerProfile: Codable, Identifiable, Hashable {
    let id: String
    var label: String
    var baseURL: String
    var updatedAt: Date
    var enabled: Bool
}

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var profiles: [ServerProfile] = []
    @Published private(set) var activeProfileID = ""
    @Published private(set) var baseURL = ""
    @Published private(set) var adminAPIKey = ""
    @Published private(set) var isHydrated = false

    private let defaults = UserDefaults.standard
    private let profilesKey = "sub2api.native.profiles"
    private let activeProfileKey = "sub2api.native.activeProfile"
    private let keychainService = "dev.pwbc.sub2api.mobile"

    var isAuthenticated: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !adminAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var apiClient: APIClient {
        APIClient(baseURL: baseURL, adminAPIKey: adminAPIKey)
    }

    func hydrate() async {
        defer { isHydrated = true }
        guard let data = defaults.data(forKey: profilesKey) else {
            return
        }

        do {
            let decoded = try JSONDecoder().decode([ServerProfile].self, from: data)
            profiles = decoded.sorted { $0.updatedAt > $1.updatedAt }
            if let storedActiveID = defaults.string(forKey: activeProfileKey),
               profiles.contains(where: { $0.id == storedActiveID }) {
                activeProfileID = storedActiveID
                activateProfile(id: activeProfileID, persist: false)
            } else {
                activeProfileID = ""
                baseURL = ""
                adminAPIKey = ""
            }
        } catch {
            profiles = []
            activeProfileID = ""
        }
    }

    func saveServer(baseURL rawBaseURL: String, adminAPIKey rawKey: String) {
        let normalizedBaseURL = normalizeBaseURL(rawBaseURL)
        let trimmedKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBaseURL.isEmpty, !trimmedKey.isEmpty else { return }

        let profileID = profiles.first(where: { $0.baseURL == normalizedBaseURL })?.id ?? UUID().uuidString
        let profile = ServerProfile(
            id: profileID,
            label: label(for: normalizedBaseURL),
            baseURL: normalizedBaseURL,
            updatedAt: Date(),
            enabled: true
        )

        profiles.removeAll { $0.id == profileID }
        profiles.insert(profile, at: 0)
        KeychainStore.save(trimmedKey, service: keychainService, account: profileID)
        activeProfileID = profileID
        baseURL = normalizedBaseURL
        adminAPIKey = trimmedKey
        persistProfiles()
    }

    func switchProfile(_ profile: ServerProfile) {
        guard profile.enabled else { return }
        activateProfile(id: profile.id, persist: true)
    }

    func removeProfile(_ profile: ServerProfile) {
        profiles.removeAll { $0.id == profile.id }
        KeychainStore.delete(service: keychainService, account: profile.id)
        if activeProfileID == profile.id {
            activeProfileID = profiles.first?.id ?? ""
            activateProfile(id: activeProfileID, persist: true)
        }
        persistProfiles()
    }

    func logout() {
        activeProfileID = ""
        baseURL = ""
        adminAPIKey = ""
        defaults.removeObject(forKey: activeProfileKey)
    }

    func exitCurrentServerAndActivateFallback(timeoutSeconds: TimeInterval = 15) async {
        guard !activeProfileID.isEmpty else {
            logout()
            return
        }

        let exitingProfileID = activeProfileID
        profiles.removeAll { $0.id == exitingProfileID }
        KeychainStore.delete(service: keychainService, account: exitingProfileID)
        activeProfileID = ""
        defaults.removeObject(forKey: activeProfileKey)
        persistProfiles()

        while let candidate = profiles.first {
            guard let key = KeychainStore.read(service: keychainService, account: candidate.id), !key.isEmpty else {
                removeInvalidProfile(candidate)
                continue
            }

            do {
                try await APIClient(baseURL: candidate.baseURL, adminAPIKey: key).verifyConnection(timeoutSeconds: timeoutSeconds)
                activateProfile(id: candidate.id, persist: true)
                persistProfiles()
                return
            } catch {
                removeInvalidProfile(candidate)
            }
        }

        logout()
        persistProfiles()
    }

    private func activateProfile(id: String, persist: Bool) {
        guard let profile = profiles.first(where: { $0.id == id }) else {
            activeProfileID = ""
            baseURL = ""
            adminAPIKey = ""
            return
        }

        activeProfileID = profile.id
        baseURL = profile.baseURL
        adminAPIKey = KeychainStore.read(service: keychainService, account: profile.id) ?? ""

        if persist {
            defaults.set(profile.id, forKey: activeProfileKey)
        }
    }

    private func persistProfiles() {
        profiles.sort { $0.updatedAt > $1.updatedAt }
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: profilesKey)
        }
        if activeProfileID.isEmpty {
            defaults.removeObject(forKey: activeProfileKey)
        } else {
            defaults.set(activeProfileID, forKey: activeProfileKey)
        }
    }

    private func removeInvalidProfile(_ profile: ServerProfile) {
        profiles.removeAll { $0.id == profile.id }
        KeychainStore.delete(service: keychainService, account: profile.id)
        if activeProfileID == profile.id {
            activeProfileID = ""
            baseURL = ""
            adminAPIKey = ""
        }
        persistProfiles()
    }

    private func normalizeBaseURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }

    private func label(for baseURL: String) -> String {
        URL(string: baseURL)?.host ?? baseURL
    }
}
