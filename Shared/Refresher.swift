import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Pulls everything live and saves the snapshot. Each source fails on its own; the rest still update.
enum Refresher {
    /// `plan` is the Mac Calendar plan passed in by the app. When Google Calendar is connected the plan
    /// is read from Google instead (in the app and the widgets), and `plan` is only the fallback.
    @discardableResult
    static func refresh(plan: CalendarRead? = nil, reloadWidgets: Bool = true) async -> Snapshot {
        var snap = Store.load()
        var problems: [String] = []

        let weatherTask = Task { try? await Weather.fetch() }
        let googleTask: Task<Result<CalendarRead, Error>, Never>? =
            GoogleCalendar.isConnected ? Task { await capture { try await GoogleCalendar.upcoming() } } : nil
        let recoveryTask: Task<Result<[RecoveryDay], Error>, Never>? =
            Athletedata.isConfigured ? Task { await capture { try await Athletedata.recovery() } } : nil
        let stravaTask: Task<Result<[Strava.Activity], Error>, Never>? =
            Strava.isConnected ? Task { await capture { try await Strava.activities(after: Fmt.date("2025-01-01") ?? Date(timeIntervalSinceNow: -400 * 86400)) } } : nil

        if !HomeSettings.current.hasLocation {
            snap.days = []; snap.hours = []
            problems.append("Set your home in Settings > Home to see the weather.")
        } else if let w = await weatherTask.value { snap.days = w.0; snap.hours = w.1 } else { problems.append("Weather didn't load.") }

        if let recoveryTask {
            switch await recoveryTask.value {
            case .success(let r): if !r.isEmpty { snap.recovery = r }
            case .failure(let e): problems.append("Watch data: \(e.localizedDescription)")
            }
        } else {
            // Strava-only setup: no watch data and no nag. Old watch data is dropped so it isn't shown.
            snap.recovery = []
        }
        snap.watchConnected = Athletedata.isConfigured

        if let stravaTask {
            switch await stravaTask.value {
            case .success(let acts):
                let runs = Strava.runs(from: acts)
                snap.runs = runs
                snap.halfBest = Predictor.bestHalf(runs, previous: snap.halfBest)
                if let p = Predictor.predict(runs) {
                    snap.predictedHalfS = p.0
                    snap.predictedFrom = p.1
                } else {
                    snap.predictedHalfS = nil
                    snap.predictedFrom = nil
                }
            case .failure(let e): problems.append("Strava: \(e.localizedDescription)")
            }
        } else {
            problems.append("Strava isn't connected (Settings > Strava).")
        }

        let picked = PlanSource.pick(google: await googleTask?.value, local: plan)
        if let p = picked.problem { problems.append(p) }
        if let n = picked.read?.note { problems.append(n) }
        if let read = picked.read { snap.plan = read.plan; snap.trips = read.trips; snap.planUpdated = Date() }
        // Plans saved by older versions could hold the built-in plan; drop it.
        if snap.planBuiltIn == true { snap.plan = picked.read?.plan ?? []; snap.planBuiltIn = nil }
        snap.problems = problems
        snap.updated = Date()
        Store.save(snap)
        #if canImport(WidgetKit)
        if reloadWidgets { WidgetCenter.shared.reloadAllTimelines() }
        #endif
        return snap
    }

    private static func capture<T>(_ f: @Sendable () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await f()) } catch { return .failure(error) }
    }
}
