import AppKit

@main
enum LogicTest {
    static var failures = 0

    @MainActor
    static func main() {
        setvbuf(stdout, nil, _IONBF, 0)            // stream output, do not buffer
        // --- Cap of 5 open tasks ---
        seed(day: today(), tasks: [])
        let a = Store()
        for i in 1...7 { a.add("task \(i)") }
        check("caps at 5 open", a.open.count == 5)
        check("extra adds ignored", a.tasks.count == 5)
        check("isFull true", a.isFull)

        // Completing one frees a slot, and the done task stays visible today.
        a.toggle(a.open[0].id)
        check("open drops to 4 after completing", a.open.count == 4)
        check("completed still shown today", a.completed.count == 1)
        check("not full again", !a.isFull)
        a.add("task 8")
        check("can add again after completing", a.open.count == 5)
        check("completed task still listed", a.completed.count == 1)
        a.add("task 9")
        check("cap still enforced", a.open.count == 5)

        // Blank input is ignored.
        let before = a.tasks.count
        a.add("   ")
        check("blank input ignored", a.tasks.count == before)

        // --- Newest task goes on top ---
        seed(day: today(), tasks: [])
        let n = Store()
        for t in ["first", "second", "third"] { n.add(t) }
        check("newest task is on top", n.open.map(\.text) == ["third", "second", "first"])

        // A completed task in the pile does not push the new one down: the two
        // groups are listed separately, so only the open order matters.
        n.toggle(n.open[2].id)                          // complete "first"
        n.add("fourth")
        check("still on top with a completed task about",
              n.open.map(\.text) == ["fourth", "third", "second"])
        check("completing did not disturb the rest", n.completed.map(\.text) == ["first"])
        check("newest-first order survives a relaunch",
              Store().open.map(\.text) == ["fourth", "third", "second"])

        // --- Editing a task's text ---
        seed(day: today(), tasks: [("keep", false), ("rewrite me", false), ("done one", true)])
        let e = Store()
        let target = e.open[1].id
        e.rename(target, to: "rewritten")
        check("rename replaces the text", e.open.map(\.text) == ["keep", "rewritten"])
        check("rename leaves the id alone", e.open[1].id == target)
        check("rename does not reorder", e.open.first?.text == "keep")

        e.rename(target, to: "   padded  ")
        check("rename trims whitespace", e.open[1].text == "padded")

        e.rename(target, to: "   ")
        check("blank rename is refused", e.open[1].text == "padded")

        e.rename(UUID(), to: "nobody")
        check("rename of an unknown id is ignored", e.tasks.count == 3)

        // Completed tasks can be corrected too — they are still on screen today.
        let doneID = e.completed[0].id
        e.rename(doneID, to: "done, corrected")
        check("a completed task can be renamed", e.completed.map(\.text) == ["done, corrected"])
        check("renaming does not un-complete it", e.completed.count == 1 && e.open.count == 2)

        check("the new text survives a relaunch",
              Store().tasks.map(\.text) == ["keep", "padded", "done, corrected"])

        // --- Reordering open tasks ---
        seed(day: today(), tasks: [("one", false), ("two", false), ("three", false),
                                   ("old done", true)])
        let r = Store()
        r.moveOpen(from: 0, to: 2)
        check("move to the end", r.open.map(\.text) == ["two", "three", "one"])
        r.moveOpen(from: 2, to: 0)
        check("move back to the front", r.open.map(\.text) == ["one", "two", "three"])
        r.moveOpen(from: 1, to: 2)
        check("move down one", r.open.map(\.text) == ["one", "three", "two"])
        check("completed tasks untouched by a reorder", r.completed.map(\.text) == ["old done"])
        r.moveOpen(from: 0, to: 9)
        check("out-of-range move is ignored", r.open.map(\.text) == ["one", "three", "two"])

        let reloaded = Store()
        check("the new order survives a relaunch",
              reloaded.open.map(\.text) == ["one", "three", "two"])
        check("and so do the completed tasks", reloaded.completed.map(\.text) == ["old done"])

        // Completing a task keeps the surviving order intact.
        if let mid = r.open.first(where: { $0.text == "three" }) { r.toggle(mid.id) }
        check("order holds after completing one", r.open.map(\.text) == ["one", "two"])

        // --- Day rollover: completed tasks vanish, open ones carry over ---
        seed(day: daysAgo(1), tasks: [("yesterday open", false), ("yesterday done", true)])
        let b = Store()
        check("completed dropped at rollover", b.completed.isEmpty)
        check("open carried over", b.open.map(\.text) == ["yesterday open"])
        check("day stamp refreshed", b.day == today())

        // A relaunch on the same day keeps everything, completed included.
        seed(day: today(), tasks: [("open", false), ("done", true)])
        let c = Store()
        check("same-day relaunch keeps open", c.open.count == 1)
        check("same-day relaunch keeps completed", c.completed.count == 1)

        // Rollover mid-session (app left running overnight).
        c.rollOverIfNeeded()
        check("no-op when day unchanged", c.completed.count == 1)

        print(failures == 0 ? "\nAll checks passed." : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    static func check(_ name: String, _ ok: Bool) {
        print("\(ok ? "ok  " : "FAIL") \(name)")
        if !ok { failures += 1 }
    }

    static func today() -> String { stamp(Date()) }
    static func daysAgo(_ n: Int) -> String { stamp(Date().addingTimeInterval(-86400 * Double(n))) }
    static func stamp(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }

    static func seed(day: String, tasks: [(String, Bool)]) {
        let list = tasks.map { ["id": UUID().uuidString, "text": $0.0, "done": $0.1] as [String: Any] }
        let data = try! JSONSerialization.data(withJSONObject: ["day": day, "tasks": list])
        UserDefaults.standard.set(data, forKey: "sparks.state.v1")
    }
}
