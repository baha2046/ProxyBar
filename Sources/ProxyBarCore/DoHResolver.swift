import Foundation

public final class DoHResolver: @unchecked Sendable {
    private final class ResponseBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: Result<(Data, URLResponse), Error>?

        var result: Result<(Data, URLResponse), Error>? {
            get {
                lock.lock()
                defer { lock.unlock() }
                return storage
            }
            set {
                lock.lock()
                storage = newValue
                lock.unlock()
            }
        }
    }

    private struct CacheEntry {
        var addresses: [String]
        var expiresAt: Date
    }

    private struct Response: Decodable {
        let Answer: [Answer]?
    }

    private struct Answer: Decodable {
        let type: UInt16
        let data: String
        let TTL: UInt32
    }

    private let servers: [String]
    private let lock = NSLock()
    private var cache: [String: CacheEntry] = [:]

    public init(servers: [String]) {
        self.servers = servers
    }

    public func resolveARecord(_ name: String) -> String? {
        if let cached = cachedAddress(for: name) {
            return cached
        }

        for server in servers {
            guard var components = URLComponents(string: server) else {
                continue
            }
            components.queryItems = [
                URLQueryItem(name: "name", value: name),
                URLQueryItem(name: "type", value: "A")
            ]
            guard let url = components.url else {
                continue
            }

            var request = URLRequest(url: url)
            request.setValue("application/dns-json", forHTTPHeaderField: "Accept")

            let semaphore = DispatchSemaphore(value: 0)
            let box = ResponseBox()
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    box.result = .failure(error)
                } else if let response {
                    box.result = .success((data ?? Data(), response))
                }
                semaphore.signal()
            }.resume()

            guard semaphore.wait(timeout: .now() + 3) == .success,
                  case .success(let payload) = box.result,
                  let http = payload.1 as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let parsed = try? JSONDecoder().decode(Response.self, from: payload.0),
                  let answers = parsed.Answer else {
                continue
            }

            var minTTL: UInt32 = 300
            let addresses = answers.compactMap { answer -> String? in
                guard answer.type == 1 else {
                    return nil
                }
                minTTL = min(minTTL, answer.TTL)
                return answer.data
            }

            if let first = addresses.first {
                cache(addresses: addresses, for: name, ttl: minTTL)
                return first
            }
        }

        return nil
    }

    private func cachedAddress(for name: String) -> String? {
        lock.lock()
        defer { lock.unlock() }

        guard let entry = cache[name], entry.expiresAt > Date() else {
            cache[name] = nil
            return nil
        }
        return entry.addresses.first
    }

    private func cache(addresses: [String], for name: String, ttl: UInt32) {
        let clampedTTL = max(30, min(300, ttl))
        lock.lock()
        cache[name] = CacheEntry(
            addresses: addresses,
            expiresAt: Date().addingTimeInterval(TimeInterval(clampedTTL))
        )
        lock.unlock()
    }
}
