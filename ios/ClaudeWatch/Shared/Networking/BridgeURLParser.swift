import Foundation

/// Normalizes user-entered bridge addresses for LAN, Tailscale, and tunnel URLs.
enum BridgeURLParser {

    struct ParsedBridge {
        let baseURL: URL
        let displayHost: String
        let port: UInt16
        let usesTLS: Bool
    }

    /// Accepts: `192.168.1.4`, `192.168.1.4:7860`, `http://host:7860`,
    /// `https://mac.tail123.ts.net`, `mac.tail123.ts.net`
    static func parse(_ raw: String, defaultPort: UInt16 = 7860) -> ParsedBridge? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var candidate = trimmed
        if !candidate.contains("://") {
            // Bare hostname or IP — prefer https for tailnet-style hostnames
            let looksRemote = trimmed.contains(".ts.net")
                || trimmed.contains(".trycloudflare.com")
                || trimmed.contains(".")
                && !trimmed.first!.isNumber
            candidate = (looksRemote ? "https://" : "http://") + trimmed
        }

        guard var components = URLComponents(string: candidate),
              let host = components.host, !host.isEmpty else { return nil }

        let scheme = (components.scheme ?? "http").lowercased()
        let usesTLS = scheme == "https"
        let port = UInt16(components.port ?? (usesTLS ? 443 : defaultPort))

        components.scheme = scheme
        components.port = Int(port)
        components.path = ""
        components.query = nil
        components.fragment = nil

        guard let baseURL = components.url else { return nil }

        return ParsedBridge(
            baseURL: baseURL,
            displayHost: host,
            port: port,
            usesTLS: usesTLS
        )
    }

    static func statusURL(for baseURL: URL) -> URL {
        baseURL.appendingPathComponent("status")
    }
}