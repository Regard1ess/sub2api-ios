import Foundation

struct APIEnvelope<T: Decodable>: Decodable {
    let code: Int
    let message: String?
    let reason: String?
    let data: T?
}

struct EmptyResponse: Codable {
    init() {}
    init(from decoder: Decoder) throws {}
    func encode(to encoder: Encoder) throws {}
}

struct PaginatedData<T: Decodable>: Decodable {
    let items: [T]
    let total: Int
    let page: Int
    let pageSize: Int
    let pages: Int
}

struct DashboardStats: Decodable {
    let totalUsers: Int
    let todayNewUsers: Int
    let activeUsers: Int
    let totalApiKeys: Int
    let activeApiKeys: Int
    let totalAccounts: Int
    let normalAccounts: Int
    let errorAccounts: Int
    let totalRequests: Int
    let totalCost: Double
    let totalTokens: Int
    let todayRequests: Int
    let todayCost: Double
    let todayTokens: Int
    let todayInputTokens: Int?
    let todayOutputTokens: Int?
    let todayCacheReadTokens: Int?
    let rpm: Int
    let tpm: Int
}

struct TrendPoint: Decodable, Identifiable {
    var id: String { date }
    let date: String
    let requests: Int
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let totalTokens: Int
    let cost: Double
    let actualCost: Double
}

struct DashboardTrend: Decodable {
    let startDate: String
    let endDate: String
    let granularity: String
    let trend: [TrendPoint]
}

struct ModelStat: Decodable, Identifiable {
    var id: String { model }
    let model: String
    let requests: Int
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let totalTokens: Int
    let cost: Double
    let actualCost: Double
}

struct DashboardModelStats: Decodable {
    let startDate: String
    let endDate: String
    let models: [ModelStat]
}

struct UsageStats: Decodable {
    let totalRequests: Int?
    let totalTokens: Int?
    let totalInputTokens: Int?
    let totalOutputTokens: Int?
    let totalCost: Double?
    let totalActualCost: Double?
    let totalAccountCost: Double?
    let averageDurationMs: Double?
}

struct DashboardSnapshot: Decodable {
    let trend: [TrendPoint]?
    let models: [ModelStat]?
}

struct AdminSettings: Decodable {
    let siteName: String?
}

struct AdminUser: Decodable, Identifiable, Hashable {
    let id: Int
    let email: String
    let username: String?
    let balance: Double?
    let concurrency: Int?
    let status: String?
    let role: String?
    let currentConcurrency: Int?
    let notes: String?
    let lastUsedAt: String?
    let createdAt: String?
    let updatedAt: String?
}

struct AdminAPIKey: Decodable, Identifiable, Hashable {
    let id: Int
    let userId: Int
    let key: String
    let name: String
    let groupId: Int?
    let status: String
    let quota: Double
    let quotaUsed: Double
    let lastUsedAt: String?
    let expiresAt: String?
    let createdAt: String?
    let updatedAt: String?
    let group: AdminGroup?
}

struct AdminGroup: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let description: String?
    let platform: String
    let rateMultiplier: Double?
    let isExclusive: Bool?
    let status: String?
    let subscriptionType: String?
    let dailyLimitUsd: Double?
    let weeklyLimitUsd: Double?
    let monthlyLimitUsd: Double?
    let accountCount: Int?
    let sortOrder: Int?
    let createdAt: String?
    let updatedAt: String?
}

struct AccountTodayStats: Decodable {
    let requests: Int
    let tokens: Int
    let cost: Double
    let standardCost: Double?
    let userCost: Double?
}

struct AdminAccount: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let platform: String
    let type: String
    let status: String?
    let schedulable: Bool?
    let priority: Int?
    let concurrency: Int?
    let currentConcurrency: Int?
    let rateMultiplier: Double?
    let notes: String?
    let proxyId: Int?
    let errorMessage: String?
    let createdAt: String?
    let updatedAt: String?
    let lastUsedAt: String?
    let groupIds: [Int]?
    let groups: [AdminGroup]?
    let extra: [String: JSONValue]?
}

enum JSONValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

struct CreateUserPayload: Encodable {
    let email: String
    let password: String
    let username: String?
    let notes: String?
    let role: String
    let status: String
    let balance: Double?
    let concurrency: Int?
}

struct UpdateBalancePayload: Encodable {
    let balance: Double
    let operation: String
    let notes: String?
}

struct UpdateStatusPayload: Encodable {
    let status: String
}

struct CreateAccountPayload: Encodable {
    let name: String
    let platform: String
    let type: String
    let credentials: [String: JSONValue]
    let extra: [String: JSONValue]?
    let notes: String?
    let proxyId: Int?
    let concurrency: Int?
    let priority: Int?
    let rateMultiplier: Double?
    let groupIds: [Int]?
}

struct UpdateAccountPayload: Encodable {
    let name: String?
    let platform: String?
    let type: String?
    let credentials: [String: JSONValue]?
    let extra: [String: JSONValue]?
    let notes: String?
    let proxyId: Int?
    let concurrency: Int?
    let priority: Int?
    let rateMultiplier: Double?
    let groupIds: [Int]?
}

struct SetSchedulablePayload: Encodable {
    let schedulable: Bool
}
