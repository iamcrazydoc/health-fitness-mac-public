import AppKit
import SwiftUI

/// Work with Claude: open a ready-made ask in Claude with your data, or chat here with your own API key.
struct ClaudeView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var recovery: RecoveryModel
    @State private var question = ""
    @State private var copied: String?

    // In-app chat
    @State private var turns: [ClaudeChat.Turn] = []
    @State private var chatContext = ""
    @State private var draft = ""
    @State private var sending = false
    @State private var chatError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Claude").font(.system(size: 28, weight: .semibold, design: .rounded))
                    Spacer()
                }
                openInClaude
                chatCard
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var summary: String { ClaudeContext.summary(model.derived, bodyNotes: bodyNotes) }

    private var bodyNotes: [String] {
        let from = TrainingMath.add(model.derived.todayKey, -30)
        return recovery.entries.filter { $0.date >= from }.sorted { $0.date > $1.date }.map { e in
            "\(e.date): \(e.part), \(e.feel.lowercased()) \(e.severity)/5"
                + (e.symptoms.isEmpty ? "" : "; " + e.symptoms.joined(separator: ", "))
                + (e.note.isEmpty ? "" : "; \"\(e.note)\"")
        }
    }

    // MARK: Open in Claude

    private var openInClaude: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle(text: "Open in Claude")
                Text("Copies an ask and a summary of your data, then opens Claude. Paste with ⌘V. Uses your Claude plan and the connectors you've added there (Strava, Google Calendar and others), so Claude can change your calendar plan when you ask.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                TextField("Optional question to include", text: $question, axis: .vertical).lineLimit(1...3)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(ClaudeAsk.allCases) { ask in
                        Button { open(ask) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Label(ask.title, systemImage: ask.symbol).font(.headline)
                                Text(ask.blurb).font(.caption).foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                HStack {
                    Button("Copy my data only") { copy(ClaudeContext.handoff(nil, question: question, summary: summary), note: "Data copied.") }
                    if let copied { Text(copied).font(.callout).foregroundStyle(.green) }
                }
            }
        }
    }

    private func open(_ ask: ClaudeAsk) {
        copy(ClaudeContext.handoff(ask, question: question, summary: summary), note: "Copied. Paste into Claude with ⌘V.")
        NSWorkspace.shared.open(ClaudeContext.newChatURL)
    }

    private func copy(_ text: String, note: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = note
    }

    // MARK: Chat here

    private var chatCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    CardTitle(text: "Chat here")
                    Spacer()
                    if !turns.isEmpty {
                        Button("Continue in Claude") { continueInClaude() }
                            .help("Copy this chat and your data, then open Claude, where its connectors can change your calendar")
                        Button("New chat") { turns = []; chatContext = ""; chatError = nil }
                    }
                }
                if !ClaudeChat.isConfigured {
                    Text("Optional: add an Anthropic API key in Settings > Claude to chat inside the app. Usage is billed to that key by Anthropic. Your messages and a summary of your data go to Anthropic's API.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Answers come from Claude through your API key. Your messages and a summary of your data are sent with each question.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(turns) { t in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.role == "user" ? "You" : "Claude").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(.init(t.text)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(t.role == "user" ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    }
                    if let chatError { Text(chatError).font(.callout).foregroundStyle(.red) }
                    HStack(alignment: .bottom) {
                        TextField("Ask about your training, plan or recovery", text: $draft, axis: .vertical)
                            .lineLimit(1...5)
                            .onSubmit { send() }
                        if sending { ProgressView().controlSize(.small) }
                        Button("Send") { send() }
                            .keyboardShortcut(.return, modifiers: .command)
                            .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        if turns.isEmpty { chatContext = summary }   // frozen for the conversation
        turns.append(.user(text))
        draft = ""
        chatError = nil
        sending = true
        let ctx = chatContext, history = turns
        Task {
            do {
                let reply = try await ClaudeChat.send(context: ctx, turns: history)
                turns.append(reply)
            } catch {
                chatError = error.localizedDescription
                if turns.last?.role == "user" { draft = turns.removeLast().text }
            }
            sending = false
        }
    }

    private func continueInClaude() {
        let chat = turns.map { ($0.role == "user" ? "Me: " : "Coach: ") + $0.text }.joined(separator: "\n\n")
        let text = """
        I was talking with a coach in my Mac training app. Here's the chat; please pick up from here. \
        If we agreed on plan changes, show them and ask before adding them to my Google Calendar as all-day \
        events titled with 🏃 (or 🏁 for a race) and the distance, like "🏃 Long run · 6 mi".

        \(chat)

        \(chatContext.isEmpty ? summary : chatContext)
        """
        copy(text, note: "Chat copied. Paste into Claude with ⌘V.")
        NSWorkspace.shared.open(ClaudeContext.newChatURL)
    }
}
