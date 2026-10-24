import IsleCore
import SwiftUI

/// The Notes tab: search and a list of free and day notes, or the open note.
struct NotesView: View {
    @Environment(IslandModel.self) private var model

    var body: some View {
        if let id = model.shownNote, let note = model.notes.notes.first(where: { $0.id == id }) {
            NoteEditor(note: note)
        } else {
            NoteList()
        }
    }
}

private struct NoteList: View {
    @Environment(IslandModel.self) private var model
    @FocusState private var searching: Bool
    @State private var contentHeight: CGFloat = 0
    private let maxHeight: CGFloat = 330

    var body: some View {
        @Bindable var model = model
        let notes = model.notes.notes.matching(model.noteQuery)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.ink.opacity(searching ? 0.8 : 0.4))
                TextField("", text: $model.noteQuery, prompt: Text("Search notes").foregroundColor(Color.ink.opacity(0.3)))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($searching)
                Button { model.newNote() } label: {
                    HStack(spacing: 6) {
                        Text("New")
                        Text("⌘N").opacity(0.6)
                    }
                }
                .buttonStyle(PillButton(fill: Color.ink.opacity(0.12), text: .ink))
                .keyboardShortcut("n", modifiers: .command)
            }
            .padding(.leading, 12)
            .padding(.trailing, 5)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 11).fill(Color.ink.opacity(searching ? 0.1 : 0.06)))
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    if notes.isEmpty {
                        EmptyState(icon: "note.text", tint: .isleBlue,
                                   title: model.noteQuery.isEmpty ? "No notes yet" : "No notes match “\(model.noteQuery)”",
                                   subtitle: "Press ⌘N, or ⌃⌥N from any app.")
                    } else {
                        ForEach(notes) { NoteRow(note: $0) }
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .frame(height: min(contentHeight, maxHeight))
            .scrollDisabled(contentHeight <= maxHeight)
        }
        // Type to search as soon as the tab opens.
        .onAppear { DispatchQueue.main.async { searching = true } }
    }
}

private struct NoteRow: View {
    @Environment(IslandModel.self) private var model
    let note: Note
    @State private var hover = false

    var body: some View {
        Button { model.openNote(note.id) } label: {
            HStack(spacing: 10) {
                Image(systemName: note.day == nil ? "note.text" : "sun.max.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(note.day == nil ? Color.ink.opacity(0.35) : .isleOrange)
                    .frame(width: 18)
                Text(note.day.map { "\(Format.day($0, now: model.now)) · \(note.title)" } ?? note.title)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ink.opacity(0.92))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(Format.day(Day.key(note.updated), now: model.now))
                    .font(.digits(11))
                    .foregroundStyle(Color.ink.opacity(0.4))
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.ink.opacity(hover ? 0.07 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .contextMenu {
            Button("Delete", role: .destructive) { model.deleteNote(note.id) }
        }
    }
}

private struct NoteEditor: View {
    @Environment(IslandModel.self) private var model
    let note: Note

    /// Read when called: a value captured when the view drew can be stale when the editor writes back.
    private var text: String { model.notes.notes.first { $0.id == note.id }?.text ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { model.closeNote() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                        Text("All notes").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Color.ink.opacity(0.8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ink.opacity(0.45))
                Spacer()
                IconButton(icon: "trash", help: "Delete note", tint: .isleRed) { model.deleteNote(note.id) }
            }
            .padding(.horizontal, 10)
            NoteTextView(text: Binding(get: { text }, set: { model.notes.setText(note.id, $0) }),
                         takesFocus: true, onEscape: { model.escape() })
                .padding(8)
                .frame(height: 260)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.ink.opacity(0.06)))
        }
    }

    private var caption: String {
        if let day = note.day { return "Note for \(Format.day(day, now: model.now))" }
        return "Edited \(Format.when(day: Day.key(note.updated), minute: Day.minute(of: note.updated), now: model.now))"
    }
}

/// A plain multi-line text view for notes. SwiftUI's `TextEditor` takes the keyboard late, so keys typed
/// right after a note opens were lost, and it answers Esc with word completion. This view takes the
/// keyboard as soon as it is in the window, and its delegate sends Esc to `onEscape`.
struct NoteTextView: NSViewRepresentable {
    @Binding var text: String
    var takesFocus = false
    /// Lets other views find this text view with `viewWithTag`.
    var tag = 0
    let onEscape: () -> Void
    @Environment(\.colorScheme) private var scheme

    func makeNSView(context: Context) -> NSScrollView {
        let view = FocusingTextView(frame: .zero)
        view.delegate = context.coordinator
        view.isRichText = false  // plain text: nothing pasted can carry links or styles
        view.allowsUndo = true
        view.drawsBackground = false
        view.font = .systemFont(ofSize: 13)
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isVerticallyResizable = true
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        view.string = text
        view.wantsFocus = takesFocus
        view.focusTag = tag
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView else { return }
        // The island sets its own scheme, and the dynamic ink color resolves against this appearance.
        scroll.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        view.textColor = NSColor(Color.ink).withAlphaComponent(0.92)
        view.insertionPointColor = NSColor(Color.ink)
        if view.string != text { view.string = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextView

        init(parent: NoteTextView) { self.parent = parent }

        func textDidChange(_ note: Notification) {
            guard let view = note.object as? NSTextView else { return }
            parent.text = view.string
        }

        func textView(_ view: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.cancelOperation(_:)) || selector == #selector(NSTextView.complete(_:))
            else { return false }
            parent.onEscape()
            return true
        }
    }
}

/// Takes the keyboard when it joins a window, once, if asked to.
final class FocusingTextView: NSTextView {
    var wantsFocus = false
    var focusTag = 0
    override var tag: Int { focusTag }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard wantsFocus, let window else { return }
        if window.makeFirstResponder(self) { wantsFocus = false }
    }
}
