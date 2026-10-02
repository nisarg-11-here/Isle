import IsleCore
import SwiftUI

extension Bucket {
    var title: String { ["Today", "Upcoming", "Backlog"][rawValue] }
    var prompt: String {
        ["Add to today — try “groceries 5pm”", "Plan ahead — try “dentist fri 3pm”", "Someday… — try “learn Rust”"][rawValue]
    }
}

struct OpenView: View {
    @Environment(IslandModel.self) private var model

    var body: some View {
        let side = (model.islandSize.width - model.notch.width) / 2 - 20
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                BucketTabs().frame(width: side, alignment: .leading)
                Color.clear.frame(width: model.notch.width)
                HeaderInfo().frame(width: side, alignment: .trailing)
            }
            .frame(height: model.notch.height)
            AddField()
            TaskList()
            if let toast = model.toast {
                ToastBar(toast: toast).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        // A click on empty space ends a rename or a schedule edit.
        .background { Color.clear.contentShape(Rectangle()).onTapGesture { model.endEditing() } }
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.openHeight = $0 }
    }
}

struct BucketTabs: View {
    @Environment(IslandModel.self) private var model
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Bucket.allCases, id: \.self) { b in
                let on = model.bucket == b
                Button {
                    withAnimation(.snappy) { model.bucket = b }
                } label: {
                    Text(b.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(on ? Color.ink : Color.ink.opacity(0.45))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background {
                            if on { Capsule().fill(Color.ink.opacity(0.14)).matchedGeometryEffect(id: "pill", in: pill) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character("\(b.rawValue + 1)")), modifiers: .command)
            }
        }
    }
}

struct HeaderInfo: View {
    @Environment(IslandModel.self) private var model

    var body: some View {
        let p = model.progress
        HStack(spacing: 8) {
            Text(model.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.ink.opacity(0.6))
            if p.total > 0 {
                Text("\(p.done)/\(p.total)").font(.digits(11)).foregroundStyle(Color.ink.opacity(0.45))
                ProgressRing(progress: p).frame(width: 14, height: 14)
            }
        }
    }
}

struct AddField: View {
    @Environment(IslandModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = model
        let typing = !model.draft.trimmingCharacters(in: .whitespaces).isEmpty
        VStack(alignment: .leading, spacing: 8) {
            field(typing)
            if typing {
                let p = model.plan
                WhenChips(now: model.now, day: p.day, minute: p.minute,
                          pickDay: { model.pickDay($0) }, pickTime: { model.pickTime($0) })
                    .padding(.leading, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy, value: typing)
        .onAppear { focus() }
        .onChange(of: model.focusRequest) { focus() }
    }

    private func field(_ typing: Bool) -> some View {
        @Bindable var model = model
        return HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.ink.opacity(focused ? 0.8 : 0.4))
            TextField("", text: $model.draft, prompt: Text(model.bucket.prompt).foregroundColor(Color.ink.opacity(0.3)))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit { model.addDraft() }
            if typing {
                let p = model.plan
                WhenChip(day: p.day, minute: p.minute, now: model.now)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 11).fill(Color.ink.opacity(focused ? 0.1 : 0.06)))
    }

    private func focus() {
        DispatchQueue.main.async { focused = true }
    }
}

/// The day and time choices, shared by the add field and the schedule editor.
enum WhenChoices {
    static func days(_ now: Date) -> [(String, String?)] {
        let today = Day.key(now)
        return [
            ("Today", today),
            ("Tomorrow", Day.adding(1, to: today)),
            ("Weekend", Day.weekend(after: now)),
            ("Next week", Day.next(weekday: 2, after: now)),
            ("Backlog", nil),
        ]
    }

    static let times: [(String, Int?)] = [
        ("Anytime", nil), ("9 AM", 540), ("Noon", 720), ("3 PM", 900), ("6 PM", 1080), ("9 PM", 1260),
    ]
}

/// Two rows of chips: a day, then a time. A time counts as chosen only on a task with a day.
struct WhenChips: View {
    let now: Date
    let day: String?
    let minute: Int?
    let pickDay: (String?) -> Void
    let pickTime: (Int?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(WhenChoices.days(now), id: \.0) { d in Chip(d.0, on: day == d.1) { pickDay(d.1) } }
            }
            HStack(spacing: 6) {
                ForEach(WhenChoices.times, id: \.0) { t in Chip(t.0, on: day != nil && minute == t.1) { pickTime(t.1) } }
            }
        }
    }
}

/// Where a task goes: purple for backlog, orange with a time, blue for a day.
struct WhenChip: View {
    let day: String?
    let minute: Int?
    let now: Date

    var body: some View {
        let color: Color = day == nil ? .islePurple : minute != nil ? .isleOrange : .isleBlue
        Text(Format.when(day: day, minute: minute, now: now))
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.16)))
            .fixedSize()
    }
}

/// Grows with its rows, then scrolls.
struct TaskList: View {
    @Environment(IslandModel.self) private var model
    @State private var contentHeight: CGFloat = 0
    private let maxHeight: CGFloat = 330

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                switch model.bucket {
                case .today: TodayRows()
                case .upcoming: UpcomingRows()
                case .backlog: BacklogRows()
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .frame(height: min(contentHeight, maxHeight))
        .scrollDisabled(contentHeight <= maxHeight)
    }
}

struct TodayRows: View {
    @Environment(IslandModel.self) private var model

    var body: some View {
        let s = model.sections
        if s.isEmpty {
            let waiting = model.store.todos.backlog(model.now).count
            EmptyState(icon: "sun.max.fill", tint: .isleOrange, title: "Clear day",
                       subtitle: "Add a task above, or pull one from the backlog.",
                       action: waiting > 0 ? ("Open Backlog (\(waiting))", { model.bucket = .backlog }) : nil)
        } else {
            let nowMinute = Day.minute(of: model.now)
            if !s.overdue.isEmpty {
                SectionLabel("Overdue", tint: .isleRed)
                ForEach(s.overdue) { TaskRow(todo: $0, meta: .day) }
            }
            ForEach(s.timed.filter { $0.minute! < nowMinute }) { TaskRow(todo: $0) }
            if !s.timed.isEmpty { NowLine(minute: nowMinute) }
            ForEach(s.timed.filter { $0.minute! >= nowMinute }) { TaskRow(todo: $0) }
            if !s.anytime.isEmpty {
                SectionLabel("Anytime")
                ForEach(s.anytime) { TaskRow(todo: $0) }
            }
            if !s.done.isEmpty {
                SectionLabel("Done")
                ForEach(s.done) { TaskRow(todo: $0) }
            }
        }
    }
}

struct UpcomingRows: View {
    @Environment(IslandModel.self) private var model

    var body: some View {
        let groups = model.store.todos.upcoming(model.now)
        if groups.isEmpty {
            EmptyState(icon: "calendar", tint: .isleBlue, title: "Nothing planned",
                       subtitle: "Try “dentist fri 3pm” or “taxes apr 30”.")
        } else {
            ForEach(groups) { group in
                SectionLabel(Format.day(group.day, now: model.now))
                ForEach(group.items) { TaskRow(todo: $0) }
            }
        }
    }
}

struct BacklogRows: View {
    @Environment(IslandModel.self) private var model

    var body: some View {
        let items = model.store.todos.backlog(model.now)
        if items.isEmpty {
            EmptyState(icon: "tray.fill", tint: .islePurple, title: "Backlog is empty",
                       subtitle: "Dump ideas here. Give them a day when you are ready.")
        } else {
            ForEach(items) { TaskRow(todo: $0, meta: .none) }
        }
    }
}

struct SectionLabel: View {
    let text: String
    var tint: Color = Color.ink.opacity(0.35)

    init(_ text: String, tint: Color = Color.ink.opacity(0.35)) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(tint)
            .padding(.leading, 10)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }
}

/// Splits past timed tasks from future ones.
struct NowLine: View {
    let minute: Int

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Color.isleOrange).frame(width: 6, height: 6)
            Rectangle().fill(Color.isleOrange.opacity(0.45)).frame(height: 1)
            Text(Format.time(minute)).font(.digits(10)).foregroundStyle(Color.isleOrange)
        }
        .padding(.horizontal, 16)
        .frame(height: 16)
    }
}

struct EmptyState: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    var action: (String, () -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(tint)
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink.opacity(0.9))
            Text(subtitle).font(.system(size: 11)).foregroundStyle(Color.ink.opacity(0.45))
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(PillButton(fill: Color.ink.opacity(0.12), text: .ink))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

struct ToastBar: View {
    @Environment(IslandModel.self) private var model
    let toast: Toast

    var body: some View {
        HStack {
            Text(toast.text)
                .font(.system(size: 12))
                .foregroundStyle(Color.ink.opacity(0.8))
                .lineLimit(1)
            Spacer()
            Button("Undo") { model.undoLast() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.isleOrange)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.ink.opacity(0.08)))
    }
}
