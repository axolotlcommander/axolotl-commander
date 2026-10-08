// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

/// Short names for open server connections (volume bar buttons, menus): the host name, made
/// longer only as far as needed to tell connections apart. Endpoints hold no password, so
/// labels never show one.
public enum ServerLabels {
    public static func labels(for endpoints: [RemoteEndpoint]) -> [RemoteEndpoint: String] {
        var level = Dictionary(endpoints.map { ($0, 0) }, uniquingKeysWith: { first, _ in first })
        while true {
            var labels: [RemoteEndpoint: String] = [:]
            for (endpoint, depth) in level { labels[endpoint] = label(endpoint, level: depth) }
            let groups = Dictionary(grouping: labels.keys) { labels[$0] ?? "" }
            var changed = false
            for group in groups.values where group.count > 1 {
                for endpoint in group where level[endpoint, default: 0] < 3 {
                    level[endpoint, default: 0] += 1
                    changed = true
                }
            }
            if !changed { return labels }
        }
    }

    /// 0: `host`; 1: `user@host`; 2: `user@host:port` (port only when not the default);
    /// 3: `protocol://user@host:port`.
    private static func label(_ endpoint: RemoteEndpoint, level: Int) -> String {
        switch level {
        case 0: endpoint.host
        case 1: endpoint.user.map { "\($0)@\(endpoint.host)" } ?? endpoint.host
        case 2: RemoteURL.displayName(endpoint)
        default: "\(endpoint.proto.rawValue)://\(RemoteURL.displayName(endpoint))"
        }
    }
}
