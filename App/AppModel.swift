import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var snap: Snapshot = Store.load()
    @Published var refreshing = false
    @Published var calendarAccess = false
    @Published var message: String?

    private var timer: Timer?

    var derived: Derived { Derived(snap: snap) }

    func start() {
        Task {
            calendarAccess = await CalendarPlan.shared.requestAccess()
            await refresh()
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        calendarAccess = CalendarPlan.shared.hasAccess
        let plan = CalendarPlan.shared.upcoming()
        snap = await Refresher.refresh(plan: plan)
    }

    // MARK: Google Calendar sign-in (opens the browser, comes back to a one-time local listener)
    @Published var googleSigningIn = false

    func connectGoogle() {
        guard let clientID = Keychain.get(.googleClientID), GoogleCalendar.hasClient else {
            message = "Add your Google Client ID and Client Secret first."
            return
        }
        guard !googleSigningIn else { return }
        googleSigningIn = true
        Task {
            defer { googleSigningIn = false }
            let server = LoopbackServer()
            do {
                let port = try await server.start()
                let redirect = "http://127.0.0.1:\(port)"
                let pkce = GoogleCalendar.PKCE()
                let state = UUID().uuidString
                guard let url = GoogleCalendar.authorizeURL(clientID: clientID, redirect: redirect, state: state, challenge: pkce.challenge) else {
                    server.stop()
                    message = "Couldn't build the Google sign-in link."
                    return
                }
                message = "Finish signing in to Google in your browser."
                NSWorkspace.shared.open(url)
                switch try await server.waitForCallback() {
                case .error(let e):
                    message = "Google sign-in was cancelled (\(e))."
                case .code(let code, let returned):
                    guard returned == state else { message = "Google sign-in didn't match this request. Try again."; return }
                    try await GoogleCalendar.exchange(code: code, verifier: pkce.verifier, redirect: redirect)
                    message = "Google Calendar connected."
                    await refresh()
                }
            } catch {
                server.stop()
                message = "Google sign-in failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Strava sign-in (opens the browser, comes back through healthfitness://)
    func connectStrava() {
        guard let url = Strava.authorizeURL() else { message = "Add your Strava Client ID and Secret first."; return }
        NSWorkspace.shared.open(url)
    }

    func handle(url: URL) {
        guard url.scheme == "healthfitness" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let err = items.first(where: { $0.name == "error" })?.value { message = "Strava sign-in was cancelled (\(err))."; return }
        guard let code = items.first(where: { $0.name == "code" })?.value else { return }
        Task {
            do {
                try await Strava.exchange(code: code)
                message = "Strava connected."
                await refresh()
            } catch {
                message = "Strava sign-in failed: \(error.localizedDescription)"
            }
        }
    }
}
