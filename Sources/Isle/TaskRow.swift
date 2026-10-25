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
    // ponytail: one search of the notes per row; pass `taskIDsWithNotes` down if lists grow long.
    private var hasNote: Bool { model.notes.taskNote(todo.id) != nil }

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
                .fill(Color.ink.opacity(hover || model.scheduling == todo.id ? 0.07 : 0)))
            .contentShape(Rectangle())  // the whole row, not only its text, takes hover and clicks
            .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
            .onTapGesture { model.endEditing() }
            if model.scheduling == todo.id {
                ScheduleEditor(todo: todo).transition(.opacity.combined(with: .move(edge: .top)))
            }
            if model.noting == todo.id {
                TaskNoteEditor(todo: todo).transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        // Save the rename when it ends: Return, a click elsewhere, or a click on another title.
        .onChange(of: editing) { was, isEditing in
            if was && !isEditing { model.rename(todo, to: text) }
        }
        .contextMenu {
            Button("Today") { model.setDay(todo, model.today) }
            Button("Tomorrow") { model.setDay(todo, Day.adding(1, to: model.today)) }
            Button("Backlog") { model.setDay(todo, nil) }
            Divider()
            Button(hasNote ? "Edit Note" : "Add Note") { model.toggleNote(todo) }
            Button("Delete", role: .destructive) { model.delete(todo) }
        }
    }

    @ViewBuilder private var title: some View {
        if editing {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Color.ink)
                .focused($fieldFocused)
                .onAppear {
                    text = todo.title
                    DispatchQueue.main.async { fieldFocused = true }
                }
                .onSubmit { model.endEditing() }
                .onExitCommand {
                    text = todo.title  // Esc cancels the rename
                    model.endEditing()
                }
        } else {
            Text(todo.title)
                .font(.system(size: 13))
                .strikethrough(done, color: Color.ink.opacity(0.4))
                .foregroundStyle(Color.ink.opacity(done ? 0.35 : 0.92))
                .lineLimit(1)
                .onTapGesture {
                    model.noting = nil
                    model.editing = todo.id
                }
            if hasNote {
                Image(systemName: "note.text")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.ink.opacity(0.4))
                    .help("Has a note")
            }
        }
    }

    @ViewBuilder private var metaView: some View {
        switch meta {
        case .time:
            if let m = todo.minute {
                Text(Format.time(m)).font(.digits(11)).foregroundStyle(done ? Color.ink.opacity(0.3) : .isleOrange)
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
            IconButton(icon: "note.text", help: "Note") { model.toggleNote(todo) }
            IconButton(icon: "calendar.badge.clock", help: "Schedule") {
                withAnimation(.snappy) {
                    model.noting = nil
                    model.scheduling = model.scheduling == todo.id ? nil : todo.id
                }
            }
            IconButton(icon: "trash", help: "Delete", tint: .isleRed) { model.delete(todo) }
        }
    }

    /// Show the check fill before the row moves to Done.
    private func check() {
        guard !checking else { return }  // a double-click must not undo the check
        guard !todo.isDone else { return model.toggle(todo) }
        checking = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            model.toggle(todo)
            checking = false
        }
    }
}

/// Day chips, time chips, and a phrase field, under a row.
/// Done, Return, Esc, or a click elsewhere closes it. Each chip applies at once.
struct ScheduleEditor: View {
    @Environment(IslandModel.self) private var model
    let todo: Todo
    @State private var phrase = ""
    @State private var bad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WhenChips(now: model.now, day: todo.day, minute: todo.minute,
                      pickDay: { model.setDay(todo, $0) }, pickTime: { model.setTime(todo, $0) })
            HStack(spacing: 8) {
                TextField("", text: $phrase, prompt: Text("or type “fri 4pm”, “oct 12”, “in 3 days”").foregroundColor(Color.ink.opacity(0.3)))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.ink.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.isleRed.opacity(bad ? 0.7 : 0)))
                    .onSubmit(apply)
                    .onChange(of: phrase) { bad = false }
                Button("Done", action: apply)
                    .buttonStyle(PillButton(fill: .ink, text: .inkInverse))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.ink.opacity(0.05)))
        .padding(.leading, 28)
    }

    /// An empty phrase just closes. A phrase that does not read as a date turns the field red.
    private func apply() {
        let typed = phrase.trimmingCharacters(in: .whitespaces)
        if typed.isEmpty || model.reschedule(todo, phrase: typed) {
            model.endEditing()
        } else {
            bad = true
        }
    }
}

/// A note under a task row. Each change saves at once, like every note.
struct TaskNoteEditor: View {
    @Environment(IslandModel.self) private var model
    let todo: Todo

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            NoteTextView(text: Binding(get: { model.notes.taskNote(todo.id)?.text ?? "" },
                                       set: { model.notes.setTaskNote(todo.id, $0) }),
                         takesFocus: true, onEscape: { model.escape() })
                .frame(height: 64)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.ink.opacity(0.06)))
            Button("Done") { model.endEditing() }
                .buttonStyle(PillButton(fill: .ink, text: .inkInverse))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.ink.opacity(0.05)))
        .padding(.leading, 28)
    }
}
