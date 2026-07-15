import Foundation

enum APIError: LocalizedError, Sendable {
    case baseURLRequired
    case adminKeyRequired
    case invalidURL
    case invalidServerResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .baseURLRequired:
            return "请先填写服务器地址。"
        case .adminKeyRequired:
            return "请先填写 Admin Key。"
        case .invalidURL:
            return "服务器地址不正确。"
        case .invalidServerResponse:
            return "服务返回格式异常，请确认它是可用的 Sub2API 管理接口。"
        case .requestFailed(let message):
            return message
        }
    }
}

struct APIClient: Sendable {
    var baseURL: String
    var adminAPIKey: String

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }

    func getDashboardStats() async throws -> DashboardStats {
        try await request("/api/v1/admin/dashboard/stats")
    }

    func getAdminSettings() async throws -> AdminSettings {
        try await request("/api/v1/admin/settings")
    }

    func verifyConnection(timeoutSeconds: TimeInterval = 15) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                async let settings = getAdminSettings()
                async let stats = getDashboardStats()
                _ = try await (settings, stats)
            }

            group.addTask {
                let nanoseconds = UInt64(max(timeoutSeconds, 0.1) * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
                throw APIError.requestFailed("服务器 15 秒内未响应。")
            }

            do {
                _ = try await group.next()
                group.cancelAll()
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    func getDashboardTrend(range: DateRange, userId: Int? = nil, accountId: Int? = nil, groupId: Int? = nil) async throws -> DashboardTrend {
        try await request(
            "/api/v1/admin/dashboard/trend",
            query: [
                "start_date": range.startDate,
                "end_date": range.endDate,
                "granularity": range.granularity,
                "user_id": userId.map(String.init),
                "account_id": accountId.map(String.init),
                "group_id": groupId.map(String.init),
            ]
        )
    }

    func getDashboardModels(range: DateRange) async throws -> DashboardModelStats {
        try await request(
            "/api/v1/admin/dashboard/models",
            query: [
                "start_date": range.startDate,
                "end_date": range.endDate,
            ]
        )
    }

    func getDashboardSnapshot(range: DateRange, userId: Int) async throws -> DashboardSnapshot {
        try await request(
            "/api/v1/admin/dashboard/snapshot-v2",
            query: [
                "start_date": range.startDate,
                "end_date": range.endDate,
                "granularity": range.granularity,
                "user_id": String(userId),
                "include_stats": "false",
                "include_trend": "true",
                "include_model_stats": "false",
                "include_group_stats": "false",
                "include_users_trend": "false",
            ]
        )
    }

    func getUsageStats(range: DateRange, userId: Int? = nil, accountId: Int? = nil, groupId: Int? = nil) async throws -> UsageStats {
        try await request(
            "/api/v1/admin/usage/stats",
            query: [
                "start_date": range.startDate,
                "end_date": range.endDate,
                "user_id": userId.map(String.init),
                "account_id": accountId.map(String.init),
                "group_id": groupId.map(String.init),
            ]
        )
    }

    func listUsers(search: String = "") async throws -> PaginatedData<AdminUser> {
        try await request("/api/v1/admin/users", query: ["page": "1", "page_size": "40", "search": search])
    }

    func getUser(_ id: Int) async throws -> AdminUser {
        try await request("/api/v1/admin/users/\(id)")
    }

    func createUser(_ payload: CreateUserPayload) async throws -> AdminUser {
        try await request("/api/v1/admin/users", method: "POST", body: payload)
    }

    func listUserAPIKeys(userId: Int) async throws -> PaginatedData<AdminAPIKey> {
        try await request("/api/v1/admin/users/\(userId)/api-keys", query: ["page": "1", "page_size": "100"])
    }

    func updateUserStatus(userId: Int, status: String) async throws -> AdminUser {
        try await request("/api/v1/admin/users/\(userId)", method: "PUT", body: UpdateStatusPayload(status: status))
    }

    func updateUserBalance(userId: Int, amount: Double, operation: String, notes: String?) async throws -> AdminUser {
        try await request(
            "/api/v1/admin/users/\(userId)/balance",
            method: "POST",
            body: UpdateBalancePayload(balance: amount, operation: operation, notes: notes),
            idempotencyKey: "native-user-balance-\(userId)-\(Date().timeIntervalSince1970)"
        )
    }

    func listGroups(search: String = "") async throws -> PaginatedData<AdminGroup> {
        try await request("/api/v1/admin/groups", query: ["page": "1", "page_size": "40", "search": search])
    }

    func listAccounts(search: String = "") async throws -> PaginatedData<AdminAccount> {
        try await request("/api/v1/admin/accounts", query: ["page": "1", "page_size": "40", "search": search])
    }

    func getAccount(_ id: Int) async throws -> AdminAccount {
        try await request("/api/v1/admin/accounts/\(id)")
    }

    func createAccount(_ payload: CreateAccountPayload) async throws -> AdminAccount {
        try await request("/api/v1/admin/accounts", method: "POST", body: payload)
    }

    func updateAccount(_ id: Int, payload: UpdateAccountPayload) async throws -> AdminAccount {
        try await request("/api/v1/admin/accounts/\(id)", method: "PUT", body: payload)
    }

    func deleteAccount(_ id: Int) async throws {
        let request = try makeRequest(path: "/api/v1/admin/accounts/\(id)", method: "DELETE", query: [:], idempotencyKey: nil)
        try await sendCommand(request)
    }

    func getAccountTodayStats(accountId: Int) async throws -> AccountTodayStats {
        try await request("/api/v1/admin/accounts/\(accountId)/today-stats")
    }

    func testAccount(accountId: Int) async throws {
        let request = try makeRequest(path: "/api/v1/admin/accounts/\(accountId)/test", method: "POST", query: [:], idempotencyKey: nil)
        try await sendCommand(request)
    }

    func refreshAccount(accountId: Int) async throws {
        let request = try makeRequest(path: "/api/v1/admin/accounts/\(accountId)/refresh", method: "POST", query: [:], idempotencyKey: nil)
        try await sendCommand(request)
    }

    func setAccountSchedulable(accountId: Int, schedulable: Bool) async throws -> AdminAccount {
        try await request("/api/v1/admin/accounts/\(accountId)/schedulable", method: "POST", body: SetSchedulablePayload(schedulable: schedulable))
    }

    private func request<T: Decodable, Body: Encodable>(
        _ path: String,
        method: String = "GET",
        query: [String: String?] = [:],
        body: Body,
        idempotencyKey: String? = nil
    ) async throws -> T {
        var request = try makeRequest(path: path, method: method, query: query, idempotencyKey: idempotencyKey)
        request.httpBody = try encoder.encode(body)
        return try await send(request)
    }

    private func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        query: [String: String?] = [:],
        idempotencyKey: String? = nil
    ) async throws -> T {
        let request = try makeRequest(path: path, method: method, query: query, idempotencyKey: idempotencyKey)
        return try await send(request)
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidServerResponse
        }

        if data.isEmpty, T.self == EmptyResponse.self, (200..<300).contains(httpResponse.statusCode) {
            return EmptyResponse() as! T
        }

        let envelope: APIEnvelope<T>
        do {
            envelope = try decoder.decode(APIEnvelope<T>.self, from: data)
        } catch {
            throw APIError.invalidServerResponse
        }

        if !(200..<300).contains(httpResponse.statusCode) || envelope.code != 0 {
            throw APIError.requestFailed(envelope.reason ?? envelope.message ?? "请求失败。")
        }

        if let payload = envelope.data {
            return payload
        }

        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }

        throw APIError.invalidServerResponse
    }

    private func sendCommand(_ request: URLRequest) async throws {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidServerResponse
        }

        if data.isEmpty {
            if (200..<300).contains(httpResponse.statusCode) { return }
            throw APIError.requestFailed("请求失败（HTTP \(httpResponse.statusCode)）。")
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if (200..<300).contains(httpResponse.statusCode) { return }
            let rawMessage = String(data: data, encoding: .utf8)?.nilIfBlank
            throw APIError.requestFailed(rawMessage ?? "请求失败（HTTP \(httpResponse.statusCode)）。")
        }

        if let code = responseCode(from: object) {
            if (200..<300).contains(httpResponse.statusCode), code == 0 {
                return
            }
            throw APIError.requestFailed(responseMessage(from: object, statusCode: httpResponse.statusCode, code: code))
        }

        if (200..<300).contains(httpResponse.statusCode) {
            return
        }

        throw APIError.requestFailed(responseMessage(from: object, statusCode: httpResponse.statusCode, code: nil))
    }

    private func responseCode(from object: [String: Any]) -> Int? {
        if let value = object["code"] as? Int { return value }
        if let value = object["code"] as? NSNumber { return value.intValue }
        if let value = object["code"] as? String { return Int(value) }
        return nil
    }

    private func responseMessage(from object: [String: Any], statusCode: Int, code: Int?) -> String {
        for key in ["reason", "message", "error", "detail"] {
            if let message = object[key] as? String, let value = message.nilIfBlank {
                return value
            }
        }

        if let code {
            return "请求失败（code \(code)）。"
        }

        return "请求失败（HTTP \(statusCode)）。"
    }

    private func makeRequest(path: String, method: String, query: [String: String?], idempotencyKey: String?) throws -> URLRequest {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingSuffix("/")
        let trimmedKey = adminAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBase.isEmpty else { throw APIError.baseURLRequired }
        guard !trimmedKey.isEmpty else { throw APIError.adminKeyRequired }

        let fullURL = buildRequestURL(baseURL: trimmedBase, path: path)
        guard var components = URLComponents(string: fullURL) else { throw APIError.invalidURL }
        components.queryItems = query.compactMap { key, value in
            guard let value, !value.isEmpty else { return nil }
            return URLQueryItem(name: key, value: value)
        }
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(trimmedKey, forHTTPHeaderField: "x-api-key")
        if let idempotencyKey {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        return request
    }

    private func buildRequestURL(baseURL: String, path: String) -> String {
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        for prefix in ["/api/v1", "/api"] {
            if baseURL.hasSuffix(prefix), normalizedPath.hasPrefix("\(prefix)/") {
                return String(baseURL.dropLast(prefix.count)) + normalizedPath
            }
        }
        return baseURL + normalizedPath
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
