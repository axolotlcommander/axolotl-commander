public import Foundation

/// A folder or file on a server: the connection plus an absolute path.
public struct RemoteLocation: Hashable, Sendable {
    public var endpoint: RemoteEndpoint
    /// Absolute and normalized; "" until the login directory is known.
    public var path: String

    public init(endpoint: RemoteEndpoint, path: String) {
        self.endpoint = endpoint
        self.path = path.isEmpty ? "" : RemotePath.normalize(path)
    }

    public var url: URL { RemoteURL.make(endpoint, path: path) }
}

/// Panel locations on servers are URLs like `sftp://user@host:2222/home/user`;
/// passwords never appear in them.
public enum RemoteURL {
    public static func isRemote(_ url: URL) -> Bool {
        url.scheme.flatMap { RemoteProtocol(rawValue: $0.lowercased()) } != nil
    }

    /// The location of a panel URL; any password in it is ignored.
    public static func parse(_ url: URL) -> RemoteLocation? {
        guard let scheme = url.scheme, let proto = RemoteProtocol(rawValue: scheme.lowercased()),
              let host = url.host(percentEncoded: false), !host.isEmpty
        else { return nil }
        let endpoint = RemoteEndpoint(proto: proto, host: host, port: url.port, user: url.user(percentEncoded: false))
        let path = url.path(percentEncoded: false)
        return RemoteLocation(endpoint: endpoint, path: path)
    }

    public static func make(_ endpoint: RemoteEndpoint, path: String) -> URL {
        var c = URLComponents()
        c.scheme = endpoint.proto.rawValue
        c.user = endpoint.user
        if endpoint.host.contains(":") {
            c.percentEncodedHost = "[\(endpoint.host)]"
        } else {
            c.host = endpoint.host
        }
        c.port = endpoint.port
        c.path = path
        return c.url ?? URL(string: "\(endpoint.proto.rawValue)://invalid")!
    }

    /// Parses an address as typed: `sftp://user:password@host:port/path`. The password may
    /// contain "@" and ":" (the host starts after the last "@" before the path); user and
    /// password may also be percent-encoded. Returns nil for text that is not a remote address.
    public static func parse(typed text: String) -> (location: RemoteLocation, password: String?)? {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard let sep = text.range(of: "://"),
              let proto = RemoteProtocol(rawValue: text[..<sep.lowerBound].lowercased())
        else { return nil }
        let rest = text[sep.upperBound...]
        let slash = rest.firstIndex(of: "/") ?? rest.endIndex
        let authority = rest[..<slash]
        let path = String(rest[slash...])

        var user: String?
        var password: String?
        var hostPort = authority
        if let at = authority.lastIndex(of: "@") {
            let info = authority[..<at]
            hostPort = authority[authority.index(after: at)...]
            if let colon = info.firstIndex(of: ":") {
                user = decode(info[..<colon])
                password = decode(info[info.index(after: colon)...])
            } else {
                user = decode(info)
            }
        }

        var host = String(hostPort)
        var port: Int?
        if hostPort.hasPrefix("[") {
            guard let close = hostPort.firstIndex(of: "]") else { return nil }
            host = String(hostPort[hostPort.index(after: hostPort.startIndex)..<close])
            let after = hostPort[hostPort.index(after: close)...]
            if after.hasPrefix(":") {
                guard let p = Int(after.dropFirst()) else { return nil }
                port = p
            } else if !after.isEmpty {
                return nil
            }
        } else if let colon = hostPort.lastIndex(of: ":") {
            host = String(hostPort[..<colon])
            guard let p = Int(hostPort[hostPort.index(after: colon)...]) else { return nil }
            port = p
        }
        guard !host.isEmpty, port.map({ (1...65535).contains($0) }) ?? true else { return nil }
        let endpoint = RemoteEndpoint(proto: proto, host: host, port: port, user: user)
        return (RemoteLocation(endpoint: endpoint, path: decode(path[...]) ?? path), password)
    }

    /// Short text for titles and menus: `user@host` or `host:port`.
    public static func displayName(_ endpoint: RemoteEndpoint) -> String {
        let host = endpoint.host.contains(":") ? "[\(endpoint.host)]" : endpoint.host
        let hostPort = endpoint.port.map { "\(host):\($0)" } ?? host
        return endpoint.user.map { "\($0)@\(hostPort)" } ?? hostPort
    }

    private static func decode(_ text: Substring) -> String? {
        let s = String(text)
        return s.removingPercentEncoding ?? s
    }
}
