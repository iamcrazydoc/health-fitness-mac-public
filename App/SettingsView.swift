import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var clientID = Keychain.get(.stravaClientID) ?? ""
    @State private var clientSecret = Keychain.get(.stravaClientSecret) ?? ""
    @State private var adpURL = Keychain.get(.adpURL) ?? ""
    @State private var adpKey = Keychain.get(.adpKey) ?? ""
    @State private var stravaConnected = Strava.isConnected
    @State private var googleID = Keychain.get(.googleClientID) ?? ""
    @State private var googleSecret = Keychain.get(.googleClientSecret) ?? ""
    @State private var googleCalendar = Keychain.get(.googleCalendarID) ?? "primary"
    @State private var googleConnected = GoogleCalendar.isConnected
    @State private var homeCity = HomeSettings.current.city
    @State private var homeAirports = HomeSettings.current.airports.joined(separator: ", ")
    @State private var homeStatus = ""
    @State private var goalTime = Profile.current.goalHalfSeconds.map { Fmt.hms($0) } ?? ""
    @State private var raceDate = Profile.current.raceDate ?? ""
    @State private var raceName = Profile.current.raceName ?? ""
    @State private var dashboardLink = Profile.current.dashboardLink ?? ""
    @State private var goalStatus = ""
    @State private var saved = ""

    var body: some View {
        Form {
            Section("Strava") {
                Text("Uses your own Strava API app (strava.com/settings/api, callback domain localhost). Read-only.")
                    .font(.callout).foregroundStyle(.secondary)
                TextField("Client ID", text: $clientID)
                SecureField("Client Secret", text: $clientSecret)
                HStack {
                    Button("Save") {
                        Keychain.set(clientID.trimmingCharacters(in: .whitespaces), for: .stravaClientID)
                        Keychain.set(clientSecret.trimmingCharacters(in: .whitespaces), for: .stravaClientSecret)
                        saved = "Saved."
                    }
                    Button(stravaConnected ? "Reconnect Strava" : "Connect Strava") {
                        Keychain.set(clientID.trimmingCharacters(in: .whitespaces), for: .stravaClientID)
                        Keychain.set(clientSecret.trimmingCharacters(in: .whitespaces), for: .stravaClientSecret)
                        model.connectStrava()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(clientID.isEmpty || clientSecret.isEmpty)
                    if stravaConnected {
                        Button("Disconnect") { Strava.disconnect(); stravaConnected = false }
                    }
                    Link("Open Strava API settings", destination: AppConfig.stravaSettingsURL)
                }
                Label(stravaConnected ? "Connected" : "Not connected", systemImage: stravaConnected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(stravaConnected ? .green : .secondary)
            }
            Section("Watch data (athletedata)") {
                Text("Readiness, sleep, HRV, resting HR and steps. Paste the MCP server URL and API key from your athletedata account.")
                    .font(.callout).foregroundStyle(.secondary)
                TextField("Server URL (https://…)", text: $adpURL)
                SecureField("API key", text: $adpKey)
                Button("Save and test") {
                    Keychain.set(adpURL.trimmingCharacters(in: .whitespaces), for: .adpURL)
                    Keychain.set(adpKey.trimmingCharacters(in: .whitespaces), for: .adpKey)
                    saved = "Testing…"
                    Task {
                        do {
                            let r = try await Athletedata.recovery(days: 7)
                            saved = "Works: \(r.count) days of watch data."
                            await model.refresh()
                        } catch {
                            saved = "Didn't work: \(error.localizedDescription)"
                        }
                    }
                }
            }
            Section("Google Calendar") {
                Text("Reads your 🏃 and 🏁 run events straight from Google, in the app and the widgets. Read-only. Uses your own Google Desktop app client; the setup guide shows how to make one.")
                    .font(.callout).foregroundStyle(.secondary)
                TextField("Client ID", text: $googleID)
                SecureField("Client Secret", text: $googleSecret)
                TextField("Calendar ID (only if Google can't list your calendars)", text: $googleCalendar, prompt: Text("primary"))
                HStack {
                    Button(googleConnected ? "Reconnect Google" : "Connect Google") {
                        saveGoogle()
                        model.connectGoogle()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(googleID.isEmpty || googleSecret.isEmpty || model.googleSigningIn)
                    Button("Save") { saveGoogle(); saved = "Saved."; Task { await model.refresh() } }
                    if googleConnected {
                        Button("Disconnect") { GoogleCalendar.disconnect(); googleConnected = false; Task { await model.refresh() } }
                    }
                    Link("Setup guide", destination: AppConfig.googleGuideURL)
                }
                Label(googleConnected ? "Connected" : "Not connected", systemImage: googleConnected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(googleConnected ? .green : .secondary)
            }
            Section("Home") {
                Text("Where you live. Flights leaving these airports and hotels away from this city count as trips, and the weather is for here.")
                    .font(.callout).foregroundStyle(.secondary)
                TextField("City", text: $homeCity, prompt: Text("City, State"))
                TextField("Home airports", text: $homeAirports, prompt: Text("3-letter codes, e.g. JFK, LGA"))
                HStack {
                    Button("Save home") { Task { await saveHome() } }
                    Text(homeStatus).font(.callout).foregroundStyle(.secondary)
                }
            }
            Section("Goal") {
                Text("Your half marathon goal and race. Used for the goal card, the widget and the countdown. Stored only on this Mac.")
                    .font(.callout).foregroundStyle(.secondary)
                TextField("Goal time", text: $goalTime, prompt: Text("h:mm:ss, e.g. 1:59:59"))
                TextField("Race date", text: $raceDate, prompt: Text("yyyy-mm-dd"))
                TextField("Race name", text: $raceName, prompt: Text("Optional"))
                TextField("Dashboard link", text: $dashboardLink, prompt: Text("Optional https:// link"))
                HStack {
                    Button("Save goal") { saveGoal() }
                    Text(goalStatus).font(.callout).foregroundStyle(.secondary)
                }
            }
            Section("Mac Calendar") {
                Text(googleConnected ? "Google Calendar is used for your plan. The Mac's Calendar is the backup if Google can't be reached."
                     : model.calendarAccess ? "Reading your planned runs from Calendar." : "Allow access in System Settings > Privacy & Security > Calendars.")
                    .font(.callout).foregroundStyle(.secondary)
                if !model.calendarAccess {
                    Button("Ask for access") { Task { model.calendarAccess = await CalendarPlan.shared.requestAccess(); await model.refresh() } }
                }
            }
            if !saved.isEmpty || model.message != nil {
                Text(model.message ?? saved).font(.callout)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding()
        .onReceive(model.$snap) { _ in stravaConnected = Strava.isConnected; googleConnected = GoogleCalendar.isConnected }
        .onReceive(model.$message) { _ in googleConnected = GoogleCalendar.isConnected }
    }

    private func saveGoal() {
        var p = Profile.current
        let t = goalTime.trimmingCharacters(in: .whitespaces), r = raceDate.trimmingCharacters(in: .whitespaces)
        let link = dashboardLink.trimmingCharacters(in: .whitespaces)
        var notes: [String] = []
        if t.isEmpty { p.goalHalfSeconds = nil } else if let s = Profile.parseTime(t) { p.goalHalfSeconds = s } else { notes.append("goal time not understood") }
        if r.isEmpty { p.raceDate = nil } else if let d = Profile.parseDate(r) { p.raceDate = d } else { notes.append("race date should be yyyy-mm-dd") }
        p.raceName = raceName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : raceName.trimmingCharacters(in: .whitespaces)
        if link.isEmpty { p.dashboardLink = nil } else if link.hasPrefix("https://") { p.dashboardLink = link } else { notes.append("the link must start with https://") }
        Profile.save(p)
        goalStatus = notes.isEmpty ? "Saved." : "Saved, but " + notes.joined(separator: "; ") + "."
        Task { await model.refresh() }
    }

    private func saveHome() async {
        var h = HomeSettings.current
        let city = homeCity.trimmingCharacters(in: .whitespaces)
        h.airports = HomeSettings.parseAirports(homeAirports)
        homeStatus = "Finding \(city)…"
        if !city.isEmpty, let p = try? await Geocoder.search(city).first {
            h.city = city
            h.latitude = p.latitude
            h.longitude = p.longitude
            homeStatus = "Saved: \(p.name). Weather is for here now."
        } else {
            if !city.isEmpty { h.city = city }
            homeStatus = "Saved, but that city wasn't found, so the weather stays where it was."
        }
        HomeSettings.save(h)
        homeAirports = h.airports.joined(separator: ", ")
        await model.refresh()
    }

    private func saveGoogle() {
        Keychain.set(googleID.trimmingCharacters(in: .whitespaces), for: .googleClientID)
        Keychain.set(googleSecret.trimmingCharacters(in: .whitespaces), for: .googleClientSecret)
        let cal = googleCalendar.trimmingCharacters(in: .whitespaces)
        Keychain.set(cal.isEmpty || cal == "primary" ? nil : cal, for: .googleCalendarID)
    }
}
