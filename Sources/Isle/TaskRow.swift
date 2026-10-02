import IsleCore
import SwiftUI

struct TaskRow: View {
    enum Meta { case none, time, day }

    @Environment(IslandModel.self) private var model
    let todo: Todo
    var meta: Meta = .time
    @State private var hover = false
    @State private var checking = false
    @State private var text = ""
    @FocusState private var fieldFocused: Bool

    private var done: Bool { todo.isDone || checking }
    private var editing: Bool { model.editing == todo.id }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                CheckCircle(done: done) { check() }
                title
                Spacer(minLength: 6)
                if hover && !editing { actions.transition(.opacity) } else { metaView }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 9)
                .fill(.white.opacity(hover || model.scheduling == todo.id ? 0.07 : 0)))
            .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
            if model.scheduling == todo.id {
                ScheduleEditor(todo: todo).transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .contextMenu {
            Button("Today") { model.setDay(todo, model.today) }
            Button("Tomorrow") { model.setDay(todo, Day.adding(1, to: model.today)) }
            Button("Backlog") { model.setDay(todo, nil) }
            Divider()
            Button("Delete", role: .destructive) { model.delete(todo) }
        }
    }

    @ViewBuilder private var title: some View {
        if editing {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .focused($fieldFocused)
                .onAppear {
                    text = todo.title
                    DispatchQueue.main.async { fieldFocused = true }
                }
                .onSubmit { model.rename(todo, to: text) }
        } else {
            Text(todo.title)
                .font(.system(size: 13))
                .strikethrough(done, color: .white.opacity(0.4))
                .foregroundStyle(.white.opacity(done ? 0.35 : 0.92))
                .lineLimit(1)
                .onTapGesture { model.editing = todo.id }
        }
    }

    @ViewBuilder private var metaView: some View {
        switch meta {
        case .time:
            if let m = todo.minute {
                Text(Format.time(m)).font(.digits(11)).foregroundStyle(done ? Color.white.opacity(0.3) : .isleOrange)
            }
        case .day:
            if let d = todo.day {
                Text(Format.day(d, now: model.now)).font(.digits(11)).foregroundStyle(Color.isleRed)
            }
        case .none:
            EmptyView()
        }
    }

    private var actions: some View {
        HStack(spacing: 2) {
            if todo.day != model.today && !todo.isDone {
                IconButton(icon: "sun.max", help: "Move to Today") { model.setDay(todo, model.today) }
            }
            IconButton(icon: "calendar.badge.clock", help: "Schedule") {
                withAnimation(.snappy) { model.scheduling = model.scheduling == todo.id ? nil : todo.id }
            }
            IconButton(icon: "trash", help: "Delete", tint: .isleRed) { model.delete(todo) }
        }
    }

    /// Show the check fill before the row moves to Done.
    private func check() {
        guard !todo.isDone else { return model.toggle(todo) }
        checking = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            model.toggle(todo)
            checking = false
        }
    }
}

/// Day chips, time chips, and a phrase field, under a row.
struct ScheduleEditor: View {
    @Environment(IslandModel.self) private var model
    let todo: Todo
    @State private var phrase = ""
    @State private var bad = false

    var body: some View {
        let today = model.today
        let days: [(String, String?)] = [
            ("Today", today),
            ("Tomorrow", Day.adding(1, to: today)),
            ("Weekend", Day.weekend(after: model.now)),
            ("Next week", Day.next(weekday: 2, after: model.now)),
            ("Backlog", nil),
        ]
        let times: [(String, Int?)] = [("Anytime", nil), ("9 AM", 540), ("Noon", 720), ("3 PM", 900), ("6 PM", 1080), ("9 PM", 1260)]
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(days, id: \.0) { d in Chip(d.0, on: todo.day == d.1) { model.setDay(todo, d.1) } }
            }
            HStack(spacing: 6) {
                ForEach(times, id: \.0) { t in
                    Chip(t.0, on: todo.day != nil && todo.minute == t.1) { model.setTime(todo, t.1) }
                }
            }
            TextField("", text: $phrase, prompt: Text("or type “fri 4pm”, “oct 12”, “in 3 days”").foregroundColor(.white.opacity(0.3)))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.isleRed.opacity(bad ? 0.7 : 0)))
                .onSubmit {
                    if model.reschedule(todo, phrase: phrase) {
                        withAnimation(.snappy) { model.scheduling = nil }
                    } else {
                        bad = true
                    }
                }
                .onChange(of: phrase) { bad = false }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.05)))
        .padding(.leading, 28)
    }
}
