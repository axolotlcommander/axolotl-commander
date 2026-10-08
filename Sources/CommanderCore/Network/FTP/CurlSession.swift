// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The iCommander Authors

internal import CCurl
import Foundation
import Darwin
import Synchronization

// One reused libcurl easy handle, confined to a private serial queue so blocking
// curl_easy_perform never runs on the cooperative pool. The handle keeps the control
// connection between transfers; curl_easy_reset clears options but not connections.

/// libcurl global state, initialized once (lazily, thread-safe).
let curlGlobalReady: Bool = icmd_curl_global_init() == CURLE_OK

/// Login and connection settings applied to every transfer.
struct CurlSettings: Sendable {
    var user: String
    var password: String
    var useTLS: Bool
    var verifyTLS: Bool
    var passive: Bool
    var connectTimeout: TimeInterval
    var responseTimeout: TimeInterval
    /// Decodes server replies.
    var encoding: ServerEncoding = .auto
}

/// One transfer.
struct CurlRequest: Sendable {
    enum Output: Sendable { case discard, memory, file(URL) }

    var url: String
    var customRequest: String?
    var noBody = false
    /// Raw FTP commands sent after login (CURLOPT_QUOTE), as bytes (names in the server's
    /// encoding); a "*" prefix ignores failure.
    var quote: [[UInt8]] = []
    var output: Output = .discard
    /// Uploaded with STOR to `url`.
    var upload: URL?
    var wantFileTime = false
}

struct CurlResult: Sendable {
    /// CURLcode; `CurlResult.disconnected` / `.localFailure` mark failures before curl ran.
    var code: UInt32
    var responseCode = 0
    var errorText = ""
    var body = Data()
    /// Server modification time (seconds since 1970).
    var fileTime: Int64?
    /// Server reply lines seen during the transfer.
    var replies: [String] = []
    /// The login directory as the server sent it (PWD).
    var entryPath: [UInt8]?
    /// Bytes written (download) or read (upload).
    var transferred: Int64 = 0
    var cancelled = false
    /// errno when a local file could not be opened.
    var localErrno: Int32 = 0

    static let disconnected: UInt32 = 0xFFFF_0001
    static let localFailure: UInt32 = 0xFFFF_0002

    var ok: Bool { code == CURLE_OK.rawValue && !cancelled }

    /// The last 4xx/5xx reply, or the last reply.
    var lastReply: String? {
        replies.last { $0.first == "4" || $0.first == "5" } ?? replies.last
    }

    /// A data transfer was started by the server (125/150 reply).
    var dataStarted: Bool {
        transferred > 0 || replies.contains { $0.hasPrefix("150") || $0.hasPrefix("125") }
    }
}

/// Per-transfer state shared with the C callbacks; mutated only on the session queue,
/// except `cancelled`.
private final class TransferState: @unchecked Sendable {
    let cancelled = Atomic<Bool>(false)
    let progress: (@Sendable (Int64) -> Void)?
    var fd: Int32 = -1
    var memory = Data()
    var toMemory = false
    var replies: [String] = []
    var transferred: Int64 = 0
    var encoding = ServerEncoding.auto

    init(progress: (@Sendable (Int64) -> Void)?) { self.progress = progress }

    var isCancelled: Bool { cancelled.load(ordering: .relaxed) }

    static func from(_ p: UnsafeMutableRawPointer?) -> TransferState {
        Unmanaged<TransferState>.fromOpaque(p!).takeUnretainedValue()
    }
}

final class CurlSession: @unchecked Sendable {
    private let queue = DispatchQueue(label: "icommander.FTP", qos: .userInitiated)
    private var handle: UnsafeMutableRawPointer?  // confined to `queue`

    init() {
        _ = curlGlobalReady
        handle = curl_easy_init()
    }

    deinit {
        if let handle { curl_easy_cleanup(handle) }
    }

    /// Runs one transfer; task cancellation aborts it (`cancelled` set in the result).
    func perform(
        _ request: CurlRequest, settings: CurlSettings, progress: (@Sendable (Int64) -> Void)? = nil
    ) async -> CurlResult {
        let state = TransferState(progress: progress)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<CurlResult, Never>) in
                queue.async { cont.resume(returning: self.run(request, settings, state)) }
            }
        } onCancel: {
            state.cancelled.store(true, ordering: .relaxed)
        }
    }

    /// Ends the session (libcurl sends QUIT).
    func close() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.async {
                if let h = self.handle { curl_easy_cleanup(h) }
                self.handle = nil
                cont.resume()
            }
        }
    }

    // MARK: Queue-confined

    private func run(_ r: CurlRequest, _ s: CurlSettings, _ st: TransferState) -> CurlResult {
        guard let h = handle else { return CurlResult(code: CurlResult.disconnected) }
        if st.isCancelled { return CurlResult(code: CURLE_ABORTED_BY_CALLBACK.rawValue, cancelled: true) }

        var uploadSize: Int64 = 0
        switch r.output {
        case .discard: break
        case .memory: st.toMemory = true
        case .file(let url):
            st.fd = open(url.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
            if st.fd < 0 { return CurlResult(code: CurlResult.localFailure, localErrno: errno) }
        }
        if let up = r.upload {
            st.fd = open(up.path, O_RDONLY)
            if st.fd < 0 { return CurlResult(code: CurlResult.localFailure, localErrno: errno) }
            var sb = stat()
            if fstat(st.fd, &sb) == 0 { uploadSize = Int64(sb.st_size) }
        }
        defer {
            if st.fd >= 0 { Darwin.close(st.fd) }
        }

        let errorBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(CURL_ERROR_SIZE) + 1)
        errorBuffer.initialize(repeating: 0, count: Int(CURL_ERROR_SIZE) + 1)
        defer { errorBuffer.deallocate() }

        var quote: UnsafeMutablePointer<curl_slist>?
        for cmd in r.quote {
            quote = (cmd + [0]).withUnsafeBufferPointer { buf in
                buf.withMemoryRebound(to: CChar.self) { curl_slist_append(quote, $0.baseAddress) }
            }
        }
        st.encoding = s.encoding
        defer { curl_slist_free_all(quote) }

        return withExtendedLifetime(st) {
            let me = Unmanaged.passUnretained(st).toOpaque()
            curl_easy_reset(h)
            // Drop every pointer into this frame before returning (cleanup may still talk to the server).
            defer { curl_easy_reset(h) }

            _ = icmd_curl_setopt_ptr(h, CURLOPT_ERRORBUFFER, errorBuffer)
            _ = icmd_curl_setopt_str(h, CURLOPT_URL, r.url)
            _ = icmd_curl_setopt_long(h, CURLOPT_NOSIGNAL, 1)
            _ = icmd_curl_setopt_str(h, CURLOPT_USERNAME, s.user)
            _ = icmd_curl_setopt_str(h, CURLOPT_PASSWORD, s.password)
            _ = icmd_curl_setopt_long(h, CURLOPT_CONNECTTIMEOUT_MS, max(1, Int(s.connectTimeout * 1000)))
            _ = icmd_curl_setopt_long(h, CURLOPT_SERVER_RESPONSE_TIMEOUT, max(1, Int(s.responseTimeout)))
            _ = icmd_curl_setopt_long(h, CURLOPT_TCP_KEEPALIVE, 1)
            _ = icmd_curl_setopt_long(h, CURLOPT_FTP_FILEMETHOD, Int(CURLFTPMETHOD_SINGLECWD.rawValue))
            if s.useTLS {
                _ = icmd_curl_setopt_long(h, CURLOPT_USE_SSL, Int(CURLUSESSL_ALL.rawValue))
                if !s.verifyTLS {
                    _ = icmd_curl_setopt_long(h, CURLOPT_SSL_VERIFYPEER, 0)
                    _ = icmd_curl_setopt_long(h, CURLOPT_SSL_VERIFYHOST, 0)
                }
            }
            if !s.passive { _ = icmd_curl_setopt_str(h, CURLOPT_FTPPORT, "-") }

            _ = icmd_curl_setopt_write(h, CURLOPT_HEADERFUNCTION) { ptr, size, n, ud in
                let st = TransferState.from(ud)
                let count = size * n
                if let ptr, count > 0 {
                    let bytes = UnsafeRawBufferPointer(start: ptr, count: count)
                    let line = st.encoding.decode(bytes).trimmingCharacters(in: .newlines)
                    if !line.isEmpty { st.replies.append(line) }
                }
                return count
            }
            _ = icmd_curl_setopt_ptr(h, CURLOPT_HEADERDATA, me)
            _ = icmd_curl_setopt_write(h, CURLOPT_WRITEFUNCTION) { ptr, size, n, ud in
                let st = TransferState.from(ud)
                let count = size * n
                if st.isCancelled { return 0 }
                guard let ptr, count > 0 else { return count }
                if st.toMemory {
                    st.memory.append(UnsafeRawPointer(ptr).assumingMemoryBound(to: UInt8.self), count: count)
                } else if st.fd >= 0 {
                    var done = 0
                    while done < count {
                        let w = Darwin.write(st.fd, ptr + done, count - done)
                        if w < 0 { if errno == EINTR { continue }; return 0 }
                        done += w
                    }
                }
                st.transferred += Int64(count)
                st.progress?(st.transferred)
                return count
            }
            _ = icmd_curl_setopt_ptr(h, CURLOPT_WRITEDATA, me)
            _ = icmd_curl_setopt_long(h, CURLOPT_NOPROGRESS, 0)
            _ = icmd_curl_setopt_xferinfo(h) { ud, _, _, _, _ in
                TransferState.from(ud).isCancelled ? 1 : 0
            }
            _ = icmd_curl_setopt_ptr(h, CURLOPT_XFERINFODATA, me)

            if let custom = r.customRequest { _ = icmd_curl_setopt_str(h, CURLOPT_CUSTOMREQUEST, custom) }
            if r.noBody { _ = icmd_curl_setopt_long(h, CURLOPT_NOBODY, 1) }
            if quote != nil { _ = icmd_curl_setopt_slist(h, CURLOPT_QUOTE, quote) }
            if r.wantFileTime { _ = icmd_curl_setopt_long(h, CURLOPT_FILETIME, 1) }
            if r.upload != nil {
                _ = icmd_curl_setopt_long(h, CURLOPT_UPLOAD, 1)
                _ = icmd_curl_setopt_off(h, CURLOPT_INFILESIZE_LARGE, curl_off_t(uploadSize))
                _ = icmd_curl_setopt_read(h) { buf, size, n, ud in
                    let st = TransferState.from(ud)
                    if st.isCancelled { return Int(CURL_READFUNC_ABORT) }
                    guard let buf else { return Int(CURL_READFUNC_ABORT) }
                    while true {
                        let got = Darwin.read(st.fd, buf, size * n)
                        if got < 0 { if errno == EINTR { continue }; return Int(CURL_READFUNC_ABORT) }
                        if got > 0 {
                            st.transferred += Int64(got)
                            st.progress?(st.transferred)
                        }
                        return got
                    }
                }
                _ = icmd_curl_setopt_ptr(h, CURLOPT_READDATA, me)
            }

            let code = curl_easy_perform(h)
            _ = icmd_curl_setopt_ptr(h, CURLOPT_ERRORBUFFER, nil)

            var result = CurlResult(code: code.rawValue)
            var response = 0
            _ = icmd_curl_getinfo_long(h, CURLINFO_RESPONSE_CODE, &response)
            result.responseCode = response
            var entry: UnsafePointer<CChar>?
            if icmd_curl_getinfo_string(h, CURLINFO_FTP_ENTRY_PATH, &entry) == CURLE_OK, let entry {
                result.entryPath = Array(UnsafeRawBufferPointer(start: entry, count: strlen(entry)))
            }
            if r.wantFileTime {
                var t: curl_off_t = -1
                if icmd_curl_getinfo_off(h, CURLINFO_FILETIME_T, &t) == CURLE_OK, t >= 0 { result.fileTime = Int64(t) }
            }
            let message = String(cString: errorBuffer)
            result.errorText = message.isEmpty ? String(cString: curl_easy_strerror(code)) : message
            result.body = st.memory
            result.replies = st.replies
            result.transferred = st.transferred
            result.cancelled = st.isCancelled && code != CURLE_OK
            return result
        }
    }
}
