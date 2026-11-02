import Foundation

struct GarmentInfo: Codable {
    var name: String
    var hex: String
    var hsl: String
}

struct OutfitRecord: Codable, Identifiable {
    var id: Int64
    var createdAt: String
    var top: GarmentInfo
    var bottom: GarmentInfo
    var boundary: Double
    var score: Int
    var comment: String
    var topBad: Bool
    var bottomBad: Bool
    var photoUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, top, bottom, boundary, score, comment
        case createdAt = "created_at"
        case topBad = "top_bad"
        case bottomBad = "bottom_bad"
        case photoUrl = "photo_url"
    }

    /// "M月d日 HH:mm"，与网页端一致
    var dateText: String {
        let base = ISO8601DateFormatter()
        base.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = base.date(from: createdAt)
        if date == nil {
            let plain = ISO8601DateFormatter()
            date = plain.date(from: createdAt)
        }
        guard let d = date else { return createdAt }
        let f = DateFormatter()
        f.dateFormat = "M月d日 HH:mm"
        return f.string(from: d)
    }
}

struct SaveRecordPayload: Codable {
    var top: GarmentInfo
    var bottom: GarmentInfo
    var boundary: Double
    var score: Int
    var comment: String
    var topBad: Bool
    var bottomBad: Bool

    enum CodingKeys: String, CodingKey {
        case top, bottom, boundary, score, comment
        case topBad = "top_bad"
        case bottomBad = "bottom_bad"
    }
}

struct SaveRecordBody: Codable {
    var photo: String
    var record: SaveRecordPayload
}

struct UpdateRecordBody: Codable {
    var score: Int
    var comment: String
    var topBad: Bool
    var bottomBad: Bool
    var photo: String?

    enum CodingKeys: String, CodingKey {
        case score, comment, photo
        case topBad = "top_bad"
        case bottomBad = "bottom_bad"
    }
}

struct RecordsResponse: Codable {
    var records: [OutfitRecord]
    var hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case records
        case hasMore = "has_more"
    }
}

struct SaveResponse: Codable {
    var ok: Bool
    var id: Int64
    var createdAt: String?
    var photoUrl: String?

    enum CodingKeys: String, CodingKey {
        case ok, id
        case createdAt = "created_at"
        case photoUrl = "photo_url"
    }
}

struct OkResponse: Codable {
    var ok: Bool
    var error: String?
}

enum APIError: LocalizedError {
    case server(String)

    var errorDescription: String? {
        switch self {
        case .server(let msg): return msg
        }
    }
}

enum APIClient {
    static let base = "https://outfit-worker.keiyokaze.workers.dev"

    static func request<T: Decodable>(_ method: String, _ path: String, body: Data? = nil) async throws -> T {
        guard let url = URL(string: base + path) else { throw APIError.server("URL 无效") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 30
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.server("响应异常") }
        if !(200...299).contains(http.statusCode) {
            let msg = (try? JSONDecoder().decode(OkResponse.self, from: data))?.error
                ?? "请求失败：\(http.statusCode)"
            throw APIError.server(msg)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func list(limit: Int = 30) async throws -> RecordsResponse {
        try await request("GET", "/api/records?limit=\(limit)")
    }

    static func save(photo: String, record: SaveRecordPayload) async throws -> SaveResponse {
        let body = try JSONEncoder().encode(SaveRecordBody(photo: photo, record: record))
        return try await request("POST", "/api/records", body: body)
    }

    static func update(id: Int64, body: UpdateRecordBody) async throws -> OkResponse {
        let data = try JSONEncoder().encode(body)
        return try await request("PUT", "/api/records/\(id)", body: data)
    }

    static func delete(id: Int64) async throws {
        let _: OkResponse = try await request("DELETE", "/api/records/\(id)")
    }
}
