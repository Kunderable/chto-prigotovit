import Foundation

struct RecognizedItem: Decodable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let amount: Double?
    let unit: String
    /// Название есть в базе продуктов, значит, совпадёт с ингредиентами рецептов.
    let known: Bool
}

enum RecognizeError: LocalizedError {
    case notConfigured
    case server(String)
    case network

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Распознавание фото не настроено."
        case .server(let message): message
        case .network: "Нет связи с сервером. Проверь интернет и попробуй ещё раз."
        }
    }
}

/// Отправляет фото на свой сервер (папка server/ в репозитории), а тот — модели, которая понимает изображения.
/// Ключ модели хранится только на сервере: из приложения его легко достать.
struct FridgeRecognizer {
    let endpoint: URL
    let token: String

    /// Адрес и токен задаются в ios/Local.xcconfig: RECOGNIZE_HOST и RECOGNIZE_TOKEN.
    static func fromBundle(_ bundle: Bundle = .main) -> FridgeRecognizer? {
        let host = bundle.object(forInfoDictionaryKey: "RecognizeHost") as? String ?? ""
        let token = bundle.object(forInfoDictionaryKey: "RecognizeToken") as? String ?? ""
        return endpoint(host: host).map { FridgeRecognizer(endpoint: $0, token: token) }
    }

    /// Хост без схемы: в xcconfig «//» начинает комментарий, поэтому https:// там не написать.
    static func endpoint(host: String) -> URL? {
        let host = host.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, !host.hasPrefix("$(") else { return nil }
        let scheme = host.hasPrefix("localhost") || host.hasPrefix("127.0.0.1") ? "http" : "https"
        return URL(string: "\(scheme)://\(host)/v1/fridge/recognize")
    }

    static func decode(_ data: Data) throws -> [RecognizedItem] {
        struct Response: Decodable { let items: [RecognizedItem] }
        return try JSONDecoder().decode(Response.self, from: data).items
    }

    func recognize(jpeg: Data) async throws -> [RecognizedItem] {
        var request = URLRequest(url: endpoint, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "X-App-Token")
        request.httpBody = try JSONEncoder().encode(["image": jpeg.base64EncodedString()])

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw RecognizeError.network
        }
        guard let status = (response as? HTTPURLResponse)?.statusCode, status == 200 else {
            struct ErrorBody: Decodable { let error: String }
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
            throw RecognizeError.server(message ?? "Сервер не смог разобрать фото. Попробуй ещё раз.")
        }
        return try Self.decode(data)
    }
}
