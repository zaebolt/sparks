import SwiftUI

extension Notification.Name {
    static let sparksDidOpen = Notification.Name("sparksDidOpen")
}

private let accent = Color(nsColor: Palette.accent)

/// Drawn once, not per frame. `header` is a computed property, so it runs on
/// every body evaluation — and a drag rewrites `dragTranslation` on every
/// mouse-move event, so that is 60-120 times a second. Building the NSImage
/// there costs ~33µs each time to redraw a glyph that never changes; reusing
/// one costs ~4.6µs. The image keeps its drawing handler, so it still
/// re-renders itself for whatever scale factor the display it lands on wants.
private let headerIcon = Icon.statusItem(size: 15)

/// Row text, and the metrics used to line the controls up with it. The checkbox
/// and the delete button are nudged down to sit dead centre on the capitals of
/// the *first* line of a task, however many lines it wraps to — derived from the
/// font rather than guessed at, so the two can never drift apart.
private let rowFontSize: CGFloat = 12.5
private let rowFont = NSFont.systemFont(ofSize: rowFontSize)
private let rowCapCentre = rowFont.ascender - rowFont.capHeight / 2
private let rowLineHeight = rowFont.ascender - rowFont.descender
private let rowControlSize: CGFloat = 14
private let rowGap: CGFloat = 1

private extension View {
    /// Sizes a row control and centres it on the cap height of the row text.
    ///
    /// Two things here are load-bearing. The offset is padding rather than an
    /// alignment guide, because a guide shifts the view outside the row's bounds
    /// where clicks stop landing on it. And the outer frame states an explicit
    /// height, because without one the button's hit region collapses to a sliver
    /// down its right edge — it still draws, it just stops being clickable.
    func rowControl() -> some View {
        frame(width: rowControlSize, height: rowControlSize)
            .padding(.top, rowCapCentre - rowControlSize / 2)
            .frame(width: 18, height: rowLineHeight, alignment: .top)
            .contentShape(Rectangle())
    }
}

/// Reports each open row's height, so a drag knows when it has cleared its
/// neighbour. Rows are not a fixed height — a task can wrap to two lines.
private struct RowHeights: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]
    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Reports how tall the task list actually is, so the panel can size to it.
private struct ContentHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ContentView: View {
    @ObservedObject var store: Store
    @State private var draft = ""
    @State private var listHeight: CGFloat = 0
    @State private var rowHeights: [UUID: CGFloat] = [:]
    @State private var dragging: UUID?
    @State private var dragTranslation: CGFloat = 0
    @State private var dragFrom = 0
    @State private var dragTo = 0
    @State private var cancelWatch: Any?
    @FocusState private var fieldFocused: Bool

    /// Past this the list scrolls; below it the panel just grows.
    private let maxListHeight: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            composer
            if store.tasks.isEmpty {
                emptyState
            } else {
                list
            }
            footer
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial)
        .onAppear { focusSoon() }
        .onDisappear { stopWatchingForCancel() }
        .onReceive(NotificationCenter.default.publisher(for: .sparksDidOpen)) { _ in
            focusSoon()
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 7) {
            Image(nsImage: headerIcon)
                .renderingMode(.template)
                .foregroundStyle(accent)
            Text("Today")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text(Date(), format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField(store.isFull ? "Five is the limit — finish one first" : "What needs doing?",
                      text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($fieldFocused)
                .disabled(store.isFull)
                .onSubmit(submit)

            Text("\(store.open.count)/\(Store.maxOpen)")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(store.isFull ? accent : Color.secondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(fieldFocused ? accent.opacity(0.55) : Color.primary.opacity(0.09),
                                      lineWidth: 1)
                )
        )
        .padding(.horizontal, 12)
    }

    private var emptyState: some View {
        Text("A clear head. Type above to start.")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 18)
            .padding(.bottom, 14)
    }

    private var list: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: rowGap) {
                ForEach(Array(store.open.enumerated()), id: \.element.id) { index, task in
                    TaskRow(task: task,
                            lifted: dragging == task.id,
                            toggle: { toggle(task.id) },
                            remove: { remove(task.id) })
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(key: RowHeights.self,
                                                       value: [task.id: geo.size.height])
                            }
                        )
                        .offset(y: dragging == task.id ? dragTranslation : shift(forRowAt: index))
                        .zIndex(dragging == task.id ? 1 : 0)
                        .gesture(reorderGesture(for: task, at: index))
                }

                if !store.completed.isEmpty {
                    Text("Done today")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.top, store.open.isEmpty ? 6 : 12)
                        .padding(.bottom, 3)

                    ForEach(store.completed) { task in
                        TaskRow(task: task,
                                lifted: false,
                                toggle: { toggle(task.id) },
                                remove: { remove(task.id) })
                    }
                }
            }
            .padding(.vertical, 8)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: ContentHeight.self, value: geo.size.height)
                }
            )
        }
        .frame(height: min(max(listHeight, 1), maxListHeight))
        .scrollDisabled(listHeight <= maxListHeight)
        .onPreferenceChange(ContentHeight.self) { listHeight = $0 }
        .onPreferenceChange(RowHeights.self) { rowHeights = $0 }
    }

    private var footer: some View {
        HStack(spacing: 0) {
            Text(HotKey.displayName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.07)))
            Text("  to open")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 9)
        .padding(.bottom, 10)
        .overlay(Divider(), alignment: .top)
    }

    // MARK: - Actions

    private func submit() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        withAnimation(.snappy(duration: 0.22)) { store.add(draft) }
        draft = ""
        if store.isFull { fieldFocused = false }
    }

    private func toggle(_ id: UUID) {
        withAnimation(.snappy(duration: 0.25)) { store.toggle(id) }
    }

    private func remove(_ id: UUID) {
        withAnimation(.snappy(duration: 0.22)) { store.remove(id) }
    }

    // MARK: - Reordering

    /// Only open tasks reorder. Needs 4pt of travel before it engages, so a
    /// plain click still falls through to the row's tap-to-complete.
    ///
    /// The store is left alone until the drop. Reordering it mid-drag tears down
    /// and rebuilds the row the gesture is attached to, which cancels the
    /// gesture — you could only ever move a task one place per drag. Instead the
    /// target is computed as the pointer moves and the other rows are shifted
    /// visually, so nothing the gesture depends on changes underneath it.
    private func reorderGesture(for task: Task, at index: Int) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                if dragging != task.id {
                    dragging = task.id
                    dragFrom = index
                    dragTo = index
                    watchForCancel()
                }
                dragTranslation = value.translation.height
                let target = targetIndex(from: dragFrom, travelled: dragTranslation)
                if target != dragTo {
                    withAnimation(.snappy(duration: 0.18)) { dragTo = target }
                }
            }
            .onEnded { _ in
                stopWatchingForCancel()
                let from = dragFrom, to = dragTo
                dragging = nil
                dragTranslation = 0
                dragTo = from
                if from != to { store.moveOpen(from: from, to: to) }
            }
    }

    /// Right-clicking mid-drag calls it off, the way it does most everywhere else.
    ///
    /// This cannot be done from the gesture. SwiftUI treats the right button as
    /// an interruption and drops the DragGesture without ever calling `onEnded`,
    /// which leaves the row lifted and the gap open until something else happens
    /// to reset it. So the right button is watched for directly.
    private func watchForCancel() {
        stopWatchingForCancel()
        cancelWatch = NSEvent.addLocalMonitorForEvents(
            matching: [.rightMouseDown, .rightMouseUp]
        ) { event in
            if event.type == .rightMouseDown {
                cancelDrag()
            } else {
                stopWatchingForCancel()             // the interruption is over
            }
            return nil                              // swallow both: they only call it off
        }
    }

    private func stopWatchingForCancel() {
        if let cancelWatch { NSEvent.removeMonitor(cancelWatch) }
        cancelWatch = nil
    }

    /// Puts everything back where it was. `dragTo` returns to `dragFrom`, so if a
    /// stray `onEnded` does arrive it finds nothing to move.
    ///
    /// Deliberately no "cancelled" flag held until the button comes up. SwiftUI
    /// has already dropped the gesture by this point and sends nothing further,
    /// so a flag would buy nothing — and if anything ever failed to clear it,
    /// dragging would stop working altogether.
    private func cancelDrag() {
        guard dragging != nil else { return }
        withAnimation(.snappy(duration: 0.2)) {
            dragging = nil
            dragTranslation = 0
            dragTo = dragFrom
        }
    }

    /// Where the dragged row would land, stepping over each neighbour it has
    /// travelled more than halfway across. Rows are not a uniform height.
    private func targetIndex(from: Int, travelled: CGFloat) -> Int {
        var index = from
        var remaining = travelled
        while remaining > 0, index + 1 < store.open.count {
            let h = rowHeight(at: index + 1)
            guard remaining > h / 2 else { break }
            remaining -= h
            index += 1
        }
        while remaining < 0, index > 0 {
            let h = rowHeight(at: index - 1)
            guard -remaining > h / 2 else { break }
            remaining += h
            index -= 1
        }
        return index
    }

    /// How far a row that is not being dragged should slide to open up the gap.
    private func shift(forRowAt index: Int) -> CGFloat {
        guard dragging != nil, dragFrom != dragTo else { return 0 }
        let h = rowHeight(at: dragFrom)
        if dragTo > dragFrom, index > dragFrom, index <= dragTo { return -h }
        if dragTo < dragFrom, index >= dragTo, index < dragFrom { return h }
        return 0
    }

    private func rowHeight(at index: Int) -> CGFloat {
        let open = store.open
        guard open.indices.contains(index) else { return 26 }
        return (rowHeights[open[index].id] ?? 25) + rowGap
    }

    private func focusSoon() {
        guard !store.isFull else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { fieldFocused = true }
    }
}

private struct TaskRow: View {
    let task: Task
    let lifted: Bool
    let toggle: () -> Void
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            // Checkbox and text are one tap target rather than a Button plus a
            // label: the whole row completes the task, and there is no Button
            // hit region to go subtly out of step with what is drawn.
            HStack(alignment: .top, spacing: 9) {
                ZStack {
                    if task.done {
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(accent)
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color(nsColor: Palette.onAccent))
                    } else {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.55), lineWidth: 1.4)
                    }
                }
                .rowControl()

                Text(task.text)
                    .font(.system(size: rowFontSize))
                    .foregroundStyle(task.done ? Color.secondary : Color.primary)
                    .strikethrough(task.done, color: .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: toggle)

            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rowControl()
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(lifted ? 0.12 : (hovering ? 0.05 : 0)))
                .shadow(color: .black.opacity(lifted ? 0.25 : 0), radius: 6, y: 2)
                .padding(.horizontal, 8)
        )
        // Without this, hover is hit-tested against the row's *content*, so
        // entering over the padding — the margin left of the checkbox, the strip
        // above or below the text — never triggers it. The row only lit up if the
        // pointer happened to cross a glyph or a control on its way in.
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
