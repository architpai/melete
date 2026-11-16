import MeleteCore
import SwiftData
import SwiftUI

/// Task list in the full panel. Click circle = done / undone. Click title = select (credited at 0:00).
/// Double-click title = rename. Hover row = planned stepper (− / +) and delete (×). Drag a row = reorder.
/// Done tasks stay, struck through.
struct TaskListView: View {
    let vm: NotchViewModel
    @Query(sort: [SortDescriptor(\TaskItem.sortIndex), SortDescriptor(\TaskItem.createdAt)]) private var tasks: [TaskItem]
    @State private var adding = false
    @State private var newTitle = ""
    @State private var renaming: UUID?
    @State private var renameText = ""
    @State private var rowFrames: [UUID: CGRect] = [:]
    @FocusState private var focus: Field?

    private enum Field: Hashable { case add, rename }

    /// Row pitch: 30 pt row + 2 pt gap (mock `.task`).
    private let pitch: CGFloat = 32
    @State private var dragging: UUID?
    @State private var dragY: CGFloat = 0

    var body: some View {
        // Read the pointer here (not only inside ForEach rows) so hover changes redraw the list.
        let hovered = hoveredRow(vm.pointerInPanel)
        ScrollView(.vertical) {
            VStack(spacing: 2) {
                ForEach(Array(tasks.enumerated()), id: \.element.id) { i, t in
                    row(t, hovered: hovered == t.id)
                        .offset(y: offset(for: i, id: t.id))
                        .zIndex(dragging == t.id ? 1 : 0)
                        .gesture(reorder(t, index: i))
                }
                addRow
            }
        }
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize)
    }

    /// Drag to reorder (a plain gesture: List drag-and-drop does not start in a non-activating panel).
    private func reorder(_ t: TaskItem, index i: Int) -> some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { v in
                if renaming != nil { return }
                dragging = t.id
                dragY = v.translation.height
            }
            .onEnded { _ in
                defer { dragging = nil; dragY = 0 }
                guard dragging == t.id else { return }
                let target = targetIndex(from: i)
                if target != i {
                    store.move(fromOffsets: IndexSet(integer: i), toOffset: target > i ? target + 1 : target)
                }
            }
    }

    private func targetIndex(from i: Int) -> Int {
        min(max(0, i + Int((dragY / pitch).rounded())), max(0, tasks.count - 1))
    }

    private func offset(for index: Int, id: UUID) -> CGFloat {
        guard let d = dragging, let from = tasks.firstIndex(where: { $0.id == d }) else { return 0 }
        if id == d { return dragY }
        let to = targetIndex(from: from)
        if from < to, index > from, index <= to { return -pitch }
        if from > to, index >= to, index < from { return pitch }
        return 0
    }

    private var store: MeleteStore { vm.taskStore }

    private func hoveredRow(_ pointer: CGPoint?) -> UUID? {
        guard dragging == nil, let p = pointer else { return nil }
        return rowFrames.first { $0.value.contains(p) }?.key
    }
    private var engine: TimerEngine { vm.engine }

    private func row(_ t: TaskItem, hovered: Bool) -> some View {
        let selected = engine.currentTaskID == t.id
        let isHovered = hovered && renaming != t.id
        return HStack(spacing: 9) {
            Button { store.setDone(t, !t.isDone) } label: { radio(t, selected: selected) }
                .buttonStyle(.plain)
                .accessibilityLabel(t.isDone ? "Mark not done" : "Mark done")
            if renaming == t.id {
                TextField("", text: $renameText)
                    .textFieldStyle(.plain)
                    .focused($focus, equals: .rename)
                    .onSubmit { commitRename(t) }
                    .onExitCommand { renaming = nil }
            } else {
                Text(t.title)
                    .strikethrough(t.isDone)
                    .foregroundStyle(t.isDone ? Color.white.opacity(0.4) : Mono.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { startRename(t) }
                    .onTapGesture { toggleSelect(t) }
                    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction(named: "Rename") { startRename(t) }
            }
            if isHovered {
                HStack(spacing: 0) {
                    stepButton("minus", "Fewer planned pomodoros") { store.setPlanned(t, t.plannedPomodoros - 1) }
                    stepButton("plus", "More planned pomodoros") { store.setPlanned(t, t.plannedPomodoros + 1) }
                }
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1)))
            }
            Text("\(t.completedPomodoros) / \(t.plannedPomodoros)")
                .font(NotchFont.small).monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.55))
            if isHovered {
                Button { delete(t) } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(Mono.ink2)
                .help("Delete task").accessibilityLabel("Delete task")
            }
        }
        .font(NotchFont.row)
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(selected ? 0.09 : (isHovered ? 0.04 : 0))))
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.12), value: dragging)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: { rowFrames[t.id] = $0 })
    }

    @ViewBuilder private func radio(_ t: TaskItem, selected: Bool) -> some View {
        Group {
            if t.isDone {
                Circle().fill(Color.white.opacity(0.4))
                    .overlay(Image(systemName: "checkmark").font(.system(size: 7, weight: .heavy)).foregroundStyle(.black))
            } else if selected {
                Circle().strokeBorder(Color.white, lineWidth: 4)
            } else {
                Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5)
            }
        }
        .frame(width: 13, height: 13)
        .frame(width: 16, height: 30)
        .contentShape(Rectangle())
    }

    private func stepButton(_ icon: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 8, weight: .bold)).frame(width: 18, height: 18).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(Mono.ink2).help(help).accessibilityLabel(help)
    }

    private var addRow: some View {
        HStack(spacing: 9) {
            Image(systemName: "plus").font(.system(size: 10, weight: .semibold)).frame(width: 16)
            if adding {
                TextField("", text: $newTitle, prompt: Text("New task").foregroundStyle(Color.white.opacity(0.38)))
                    .textFieldStyle(.plain)
                    .focused($focus, equals: .add)
                    .onSubmit(addTask)
                    .onExitCommand { adding = false; newTitle = "" }
            } else {
                Text("Add task").frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(NotchFont.row)
        .foregroundStyle(adding ? Mono.ink : Mono.ink2)
        .padding(.horizontal, 9)
        .frame(height: 30)
        .contentShape(Rectangle())
        .onTapGesture { if !adding { adding = true; focus = .add } }
        .accessibilityAddTraits(.isButton)
    }

    private func addTask() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { adding = false; return }
        store.addTask(title: title)
        newTitle = ""
        focus = .add
    }

    private func toggleSelect(_ t: TaskItem) {
        guard !t.isDone else { return }
        engine.currentTaskID = engine.currentTaskID == t.id ? nil : t.id
    }

    private func startRename(_ t: TaskItem) {
        renameText = t.title
        renaming = t.id
        focus = .rename
    }

    private func commitRename(_ t: TaskItem) {
        let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { store.rename(t, to: title) }
        renaming = nil
    }

    private func delete(_ t: TaskItem) {
        if engine.currentTaskID == t.id { engine.currentTaskID = nil }
        rowFrames[t.id] = nil
        store.delete(t)
    }
}
