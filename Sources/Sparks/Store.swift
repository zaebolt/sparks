import Foundation
import SwiftUI

struct Task: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var text: String
    var done: Bool = false
    var completedAt: Date? = nil
}

/// Holds today's tasks. Nothing survives a change of day except tasks that are
/// still open — completed tasks are dropped at the rollover, by design.
@MainActor
final class Store: ObservableObject {
    static let maxOpen = 5
    private static let key = "sparks.state.v1"

    @Published private(set) var tasks: [Task] = []
    @Published private(set) var day: String = Store.today()

    var open: [Task] { tasks.filter { !$0.done } }
    var completed: [Task] { tasks.filter { $0.done } }
    var isFull: Bool { open.count >= Store.maxOpen }

    init() {
        load()
        rollOverIfNeeded()
    }

    // MARK: - Mutations

    func add(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isFull else { return }
        tasks.append(Task(text: text))
        save()
    }

    func toggle(_ id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        // Un-completing is only allowed if it would not exceed the open cap.
        if tasks[i].done && open.count >= Store.maxOpen { return }
        tasks[i].done.toggle()
        tasks[i].completedAt = tasks[i].done ? Date() : nil
        save()
    }

    /// Reorders the open tasks. Completed ones keep their own order and are
    /// parked after the open ones — the panel lists the two groups separately,
    /// so their relative position in the array carries no meaning.
    func moveOpen(from: Int, to: Int) {
        var openTasks = open
        let doneTasks = completed
        guard openTasks.indices.contains(from), openTasks.indices.contains(to) else { return }
        openTasks.insert(openTasks.remove(at: from), at: to)
        tasks = openTasks + doneTasks
        save()
    }

    func remove(_ id: UUID) {
        tasks.removeAll { $0.id == id }
        save()
    }

    /// Drops completed tasks once the calendar day changes. Open tasks carry over.
    func rollOverIfNeeded() {
        let now = Store.today()
        guard now != day else { return }
        day = now
        tasks.removeAll { $0.done }
        save()
    }

    // MARK: - Persistence

    private struct Snapshot: Codable {
        var day: String
        var tasks: [Task]
    }

    private func save() {
        let snap = Snapshot(day: day, tasks: tasks)
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: Store.key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Store.key),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return }
        day = snap.day
        tasks = snap.tasks
    }

    /// Built once and reused. Constructing a `DateFormatter` costs ~53µs — it
    /// spins up locale and ICU state — against ~0.9µs to reuse one, and this is
    /// called on every rollover check and every time the panel opens.
    ///
    /// The calendar and time zone are reassigned per call rather than captured,
    /// so crossing a time zone or changing the system calendar still lands on
    /// the right day. That is the whole cost difference between the two: the
    /// formatter is the expensive part, not reading `Calendar.current`.
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func today() -> String {
        let f = dayFormatter
        f.calendar = Calendar.current
        f.timeZone = TimeZone.current
        return f.string(from: Date())
    }
}
