import Foundation
import Network

/// A one-shot local web server on 127.0.0.1 that catches Google's sign-in redirect.
/// It listens on a random free port, answers the browser with a short page, then stops.
final class LoopbackServer {
    private final class Once { var fired = false }

    private let queue = DispatchQueue(label: "com.binoy.healthfitness.loopback")
    private var listener: NWListener?
    private var waiter: CheckedContinuation<GoogleCalendar.Callback, Error>?
    private var pending: Result<GoogleCalendar.Callback, Error>?

    /// Starts listening and returns the port.
    func start() async throws -> UInt16 {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let l = try NWListener(using: params)
        listener = l
        let once = Once()
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<UInt16, Error>) in
            l.stateUpdateHandler = { state in
                guard !once.fired else { return }
                switch state {
                case .ready:
                    once.fired = true
                    c.resume(returning: l.port?.rawValue ?? 0)
                case .failed(let e):
                    once.fired = true
                    c.resume(throwing: e)
                case .cancelled:
                    once.fired = true
                    c.resume(throwing: CancellationError())
                default: break
                }
            }
            l.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
            l.start(queue: queue)
        }
    }

    /// Waits for the sign-in redirect (five minutes at most).
    func waitForCallback(timeout: TimeInterval = 300) async throws -> GoogleCalendar.Callback {
        try await withCheckedThrowingContinuation { c in
            queue.async {
                if let p = self.pending { self.pending = nil; c.resume(with: p); self.stopOnQueue(); return }
                self.waiter = c
                self.queue.asyncAfter(deadline: .now() + timeout) {
                    self.finish(.failure(HFError.parse("Google sign-in (timed out after 5 minutes)")))
                }
            }
        }
    }

    func stop() { queue.async { self.stopOnQueue() } }

    private func stopOnQueue() {
        listener?.cancel()
        listener = nil
    }

    private func finish(_ r: Result<GoogleCalendar.Callback, Error>) {
        if let w = waiter {
            waiter = nil
            w.resume(with: r)
            stopOnQueue()
        } else if listener != nil, pending == nil {
            pending = r
        }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, _ in
            let text = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            let cb = GoogleCalendar.parseCallback(request: text)
            let (status, body): (String, String)
            switch cb {
            case .code?: (status, body) = ("200 OK", "Google Calendar is connected. You can close this tab and go back to Health and Fitness.")
            case .error?: (status, body) = ("200 OK", "Google sign-in was cancelled. You can close this tab.")
            case nil: (status, body) = ("404 Not Found", "Not found.")
            }
            let html = "<!doctype html><meta charset=utf-8><title>Health and Fitness</title>"
                + "<body style=\"font:16px -apple-system,sans-serif;margin:48px\"><p>\(body)</p></body>"
            let resp = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
            conn.send(content: Data(resp.utf8), completion: .contentProcessed { _ in conn.cancel() })
            if let cb { self?.finish(.success(cb)) }
        }
    }
}
