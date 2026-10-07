public import Foundation
import Security
import Synchronization

/// A saved connection (bookmark). The password is never part of it; it lives in a `PasswordStore`.
public struct ConnectionProfile: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var endpoint: RemoteEndpoint
    /// Folder opened after login; "" = the login directory.
    public var initialPath: String
    /// FTP only: passive data connections (EPSV/PASV).
    public var passiveMode: Bool
    /// FTP only: how the server encodes names.
    public var encoding: ServerEncoding

    public init(
        id: UUID = UUID(),
        name: String = "",
        endpoint: RemoteEndpoint,
        initialPath: String = "",
        passiveMode: Bool = true,
        encoding: ServerEncoding = .auto
    ) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.initialPath = initialPath
        self.passiveMode = passiveMode
        self.encoding = encoding
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, endpoint, initialPath, passiveMode, encoding
    }

    /// Profiles saved before `encoding` existed decode as `.auto`.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        endpoint = try c.decode(RemoteEndpoint.self, forKey: .endpoint)
        initialPath = try c.decode(String.self, forKey: .initialPath)
        passiveMode = try c.decode(Bool.self, forKey: .passiveMode)
        encoding = try c.decodeIfPresent(ServerEncoding.self, forKey: .encoding) ?? .auto
    }

    /// Options for `RemoteConnections.session`.
    public var connectOptions: ConnectOptions { ConnectOptions(passiveMode: passiveMode, encoding: encoding) }

    /// The name, or `user@host` when it has none.
    public var title: String { name.isEmpty ? RemoteURL.displayName(endpoint) : name }

    /// Where the panel goes after connecting; path "" until the login directory is known.
    public var location: RemoteLocation { RemoteLocation(endpoint: endpoint, path: initialPath) }
}

/// Passwords per endpoint (protocol, host, port, user).
public protocol PasswordStore: Sendable {
    func password(for endpoint: RemoteEndpoint) -> String?
    func save(_ password: String, for endpoint: RemoteEndpoint) throws
    func remove(for endpoint: RemoteEndpoint)
}

/// Internet passwords in the login keychain, readable in Keychain Access.
public struct KeychainPasswordStore: PasswordStore {
    public init() {}

    public func password(for endpoint: RemoteEndpoint) -> String? {
        var query = Self.query(endpoint)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func save(_ password: String, for endpoint: RemoteEndpoint) throws {
        let data = Data(password.utf8)
        let query = Self.query(endpoint)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "\(RemoteURL.displayName(endpoint)) (iCommander)"
            item[kSecAttrDescription as String] = "iCommander"
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    public func remove(for endpoint: RemoteEndpoint) {
        SecItemDelete(Self.query(endpoint) as CFDictionary)
    }

    private static func query(_ endpoint: RemoteEndpoint) -> [String: Any] {
        let proto: CFString = switch endpoint.proto {
        case .sftp: kSecAttrProtocolSSH
        case .ftp: kSecAttrProtocolFTP
        case .ftps: kSecAttrProtocolFTPS
        }
        return [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: endpoint.host,
            kSecAttrPort as String: endpoint.effectivePort,
            kSecAttrProtocol as String: proto,
            kSecAttrAccount as String: endpoint.user ?? "",
        ]
    }
}

public struct KeychainError: LocalizedError, Sendable {
    public var status: OSStatus

    public var errorDescription: String? {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
    }
}

/// Passwords kept in memory (tests, or when the keychain is not wanted).
public final class MemoryPasswordStore: PasswordStore {
    private let passwords = Mutex<[RemoteEndpoint: String]>([:])

    public init() {}

    public func password(for endpoint: RemoteEndpoint) -> String? {
        passwords.withLock { $0[endpoint] }
    }

    public func save(_ password: String, for endpoint: RemoteEndpoint) throws {
        passwords.withLock { $0[endpoint] = password }
    }

    public func remove(for endpoint: RemoteEndpoint) {
        passwords.withLock { $0[endpoint] = nil }
    }
}
