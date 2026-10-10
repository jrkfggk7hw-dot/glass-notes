// Glass Notes — frosted pastel sticky notes on a whiteboard that lives in the menu bar.
// Other apps can drop notes in by writing JSON files to the Inbox folder.
import SwiftUI
import AppKit

let boardSize = CGSize(width: 720, height: 480)
/// `--snapshot` renders a picture of the board; hover effects are off so the cursor can't sneak in.
let isSnapshot = CommandLine.arguments.contains("--snapshot")
let noteSize = CGSize(width: 180, height: 160)

// MARK: - Model

struct Note: Codable, Identifiable, Equatable {
    var id = UUID()
    var text = ""
    var x: Double
    var y: Double
    var tint = 0
    var tilt = Double.random(in: -2.5...2.5)
    var z: Double = 0
    var created = Date()
    var w: Double?
    var h: Double?

    var size: CGSize { CGSize(width: w ?? noteSize.width, height: h ?? noteSize.height) }
}

let minNoteSize = CGSize(width: 120, height: 90)
let maxNoteSize = CGSize(width: 420, height: 360)

enum Tint {
    static let all: [Color] = [
        Color(red: 1.00, green: 0.76, blue: 0.52),   // peach
        Color(red: 0.97, green: 0.60, blue: 0.74),   // pink
        Color(red: 0.42, green: 0.85, blue: 0.70),   // mint
        Color(red: 0.70, green: 0.66, blue: 0.96),   // lavender
        Color(red: 0.52, green: 0.74, blue: 0.97),   // sky
    ]
}

// MARK: - Store

final class NoteStore: ObservableObject {
    @Published var notes: [Note] = [] { didSet { scheduleSave() } }
    @Published var decor: [Decor] = [] { didSet { scheduleSave() } }
    /// Where the emoji picker will drop its sticker; nil when the picker is closed.
    @Published var pickerAt: CGPoint?
    /// Where the last right-click landed on the board, so menu items add things right there.
    var pointer = CGPoint(x: boardSize.width / 2, y: boardSize.height / 2)

    let dir: URL
    var file: URL { dir.appendingPathComponent("notes.json") }
    var decorFile: URL { dir.appendingPathComponent("decor.json") }
    var inbox: URL { dir.appendingPathComponent("Inbox", isDirectory: true) }
    private var pendingSave: DispatchWorkItem?

    init() {
        if let custom = ProcessInfo.processInfo.environment["GLASSNOTES_DIR"] {
            dir = URL(fileURLWithPath: custom, isDirectory: true)
        } else {
            dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("GlassNotes", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([Note].self, from: data) {
            notes = saved
        }
        if let data = try? Data(contentsOf: decorFile),
           let saved = try? JSONDecoder().decode([Decor].self, from: data) {
            decor = saved
        }
        importInbox()

        // Other apps post this after dropping a file in the inbox.
        DistributedNotificationCenter.default().addObserver(
            forName: .init("GlassNotes.inbox"), object: nil, queue: .main) { [weak self] _ in
            self?.importInbox()
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.saveNow()
        }
    }

    // MARK: Editing

    func binding(_ id: UUID) -> Binding<Note> {
        Binding(
            get: { self.notes.first { $0.id == id } ?? Note(x: 0, y: 0) },
            set: { new in
                if let i = self.notes.firstIndex(where: { $0.id == id }) { self.notes[i] = new }
            })
    }

    @discardableResult
    func add(at point: CGPoint? = nil, text: String = "") -> Note {
        let p = point ?? freeSpot()
        var note = Note(text: text, x: p.x, y: p.y)
        note.tint = Int.random(in: 0..<Tint.all.count)
        note.z = topZ + 1
        notes.append(note)
        return note
    }

    /// The last deleted note, kept for a few seconds so it can be brought back.
    @Published var recentlyDeleted: Note?
    private var recentlyDeletedDecor: [Decor] = []
    private var forgetDeleted: DispatchWorkItem?

    func delete(_ id: UUID) {
        guard let note = notes.first(where: { $0.id == id }) else { return }
        NSApp.keyWindow?.makeFirstResponder(nil)   // so ⌘Z means "undo delete", not "undo typing"
        withAnimation(.spring(response: 0.3)) {
            notes.removeAll { $0.id == id }
            recentlyDeletedDecor = decor.filter { $0.noteID == id }
            decor.removeAll { $0.noteID == id }
            recentlyDeleted = note
        }
        forgetDeleted?.cancel()
        let work = DispatchWorkItem { [weak self] in withAnimation { self?.recentlyDeleted = nil } }
        forgetDeleted = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }

    /// Brings back the last deleted note. Returns false if there's nothing to restore.
    @discardableResult
    func undoDelete() -> Bool {
        guard let note = recentlyDeleted else { return false }
        forgetDeleted?.cancel()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            notes.append(note)
            decor += recentlyDeletedDecor
            recentlyDeletedDecor = []
            recentlyDeleted = nil
        }
        return true
    }

    func lift(_ id: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == id }), notes[i].z < topZ else { return }
        notes[i].z = topZ + 1
    }

    private var topZ: Double { notes.map(\.z).max() ?? 0 }

    /// The spot on the board furthest from every other note.
    private func freeSpot() -> CGPoint {
        let halfW = noteSize.width / 2 + 12, halfH = noteSize.height / 2 + 12
        var best = CGPoint(x: boardSize.width / 2, y: boardSize.height / 2)
        var bestGap = -Double.infinity
        for y in stride(from: halfH, through: boardSize.height - halfH - 40, by: 20) {
            for x in stride(from: halfW, through: boardSize.width - halfW, by: 20) {
                // Overlap measured in "note sizes", so wide and tall gaps count the same.
                let gap = notes.map { max(abs($0.x - x) / noteSize.width, abs($0.y - y) / noteSize.height) }.min() ?? 9
                if gap > bestGap + 0.01 { bestGap = gap; best = CGPoint(x: x, y: y) }
            }
        }
        return best
    }

    // MARK: Inbox (notes from other apps)

    func importInbox() {
        let files = (try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)) ?? []
        for url in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            defer { try? FileManager.default.removeItem(at: url) }
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = json["text"] as? String, !text.isEmpty else { continue }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                _ = add(text: text)
            }
        }
    }

    // MARK: Saving

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        pendingSave?.cancel()
        let enc = JSONEncoder()
        enc.outputFormatting = .prettyPrinted
        try? enc.encode(notes).write(to: file, options: .atomic)
        try? enc.encode(decor).write(to: decorFile, options: .atomic)
    }
}

// MARK: - Glass note

/// Small per-view UI state. (Kept in an ObservableObject rather than @State, which needs a
/// compiler plugin that only ships with full Xcode, not the Command Line Tools.)
final class ViewState: ObservableObject {
    @Published var hovering = false
    @Published var dragStart: CGPoint?
    @Published var resizeStart: CGRect?
    @Published var dragPoint: CGPoint?
}

struct GlassNoteView: View {
    @Binding var note: Note
    var onDelete: () -> Void
    var onLift: () -> Void
    var addMenu: AnyView

    @StateObject private var ui = ViewState()
    @FocusState private var editing: Bool

    private var hovering: Bool { ui.hovering }

    private var tint: Color { Tint.all[note.tint % Tint.all.count] }
    private var lifted: Bool { ui.dragStart != nil || ui.resizeStart != nil }

    var body: some View {
        VStack(spacing: 0) {
            header
            TextEditor(text: $note.text)
                .font(.system(size: 13.5, weight: .regular, design: .rounded))
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
                .focused($editing)
                .padding(.horizontal, 9)
                .padding(.bottom, 10)
        }
        .frame(width: note.size.width, height: note.size.height)
        .background(glass)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(rim)
        .overlay(alignment: .bottomTrailing) { resizeGrip }
        .shadow(color: .black.opacity(lifted ? 0.26 : 0.16), radius: lifted ? 24 : 14, y: lifted ? 16 : 9)
        .shadow(color: tint.opacity(0.35), radius: 5, y: 2)
        .rotationEffect(.degrees(hovering || lifted || editing ? 0 : note.tilt))
        .scaleEffect(lifted ? 1.05 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: lifted)
        .position(x: note.x, y: note.y)
        .onHover { ui.hovering = $0 && !isSnapshot }
        .onAppear {
            // A brand-new blank note is ready to type into.
            if note.text.isEmpty && Date().timeIntervalSince(note.created) < 2 { editing = true }
        }
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    /// Frosted glass, coloured tint, and a curved glossy highlight across the top.
    private var glass: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            tint.opacity(0.36)
            LinearGradient(colors: [.clear, tint.opacity(0.28)], startPoint: .center, endPoint: .bottom)
            Ellipse()
                .fill(LinearGradient(colors: [.white.opacity(0.62), .white.opacity(0.06)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: note.size.width * 1.5, height: note.size.height * 0.85)
                .offset(y: -note.size.height * 0.42)
                .blendMode(.screen)
        }
        .allowsHitTesting(false)
    }

    /// Bright top edge fading out toward the bottom, like light catching the glass.
    private var rim: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.25), .white.opacity(0.05)],
                                         startPoint: .top, endPoint: .bottom), lineWidth: 1)
            .allowsHitTesting(false)
    }

    /// Corner grip: drag to resize. The top-left corner stays put.
    private var resizeGrip: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 8.5, weight: .bold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(90))
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .opacity(hovering || ui.resizeStart != nil ? 0.8 : 0)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("board"))
                    .onChanged { v in
                        if ui.resizeStart == nil {
                            ui.resizeStart = CGRect(x: note.x - note.size.width / 2, y: note.y - note.size.height / 2,
                                                    width: note.size.width, height: note.size.height)
                            onLift()
                        }
                        let r = ui.resizeStart!
                        let w = min(max(r.width + v.translation.width, minNoteSize.width),
                                    min(maxNoteSize.width, boardSize.width - r.minX))
                        let h = min(max(r.height + v.translation.height, minNoteSize.height),
                                    min(maxNoteSize.height, boardSize.height - r.minY))
                        note.w = w; note.h = h
                        note.x = r.minX + w / 2; note.y = r.minY + h / 2
                    }
                    .onEnded { _ in ui.resizeStart = nil }
            )
            .help("Drag to resize")
    }

    /// Drag handle along the top; colour dots and delete appear on hover.
    private var header: some View {
        HStack(spacing: 6) {
            if hovering {
                ForEach(Tint.all.indices, id: \.self) { i in
                    Circle()
                        .fill(Tint.all[i])
                        .overlay(Circle().strokeBorder(.white.opacity(note.tint == i ? 0.95 : 0.4),
                                                       lineWidth: note.tint == i ? 1.5 : 0.5))
                        .frame(width: 11, height: 11)
                        .onTapGesture { note.tint = i }
                }
            }
            Spacer(minLength: 0)
            if hovering {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(.white.opacity(0.35)))
                    .onTapGesture(perform: onDelete)
                    .help("Delete note")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .named("board"))
                .onChanged { v in
                    if ui.dragStart == nil { ui.dragStart = CGPoint(x: note.x, y: note.y); onLift() }
                    let start = ui.dragStart!
                    let halfW = note.size.width / 2, halfH = note.size.height / 2
                    note.x = min(max(start.x + v.translation.width, halfW), boardSize.width - halfW)
                    note.y = min(max(start.y + v.translation.height, halfH), boardSize.height - halfH)
                }
                .onEnded { _ in ui.dragStart = nil }
        )
        .contextMenu { addMenu }
        .onHover { inside in if inside { NSCursor.openHand.push() } else { NSCursor.pop() } }
    }
}

// MARK: - Board

struct BoardBackground: View {
    @Environment(\.colorScheme) private var scheme

    private func glow(_ c: Color, _ radius: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        RadialGradient(colors: [c, c.opacity(0)], center: .center, startRadius: 0, endRadius: radius)
            .frame(width: radius * 2, height: radius * 2)
            .offset(x: x, y: y)
    }

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            (dark ? Color(red: 0.13, green: 0.12, blue: 0.11) : Color(red: 0.99, green: 0.96, blue: 0.89))   // cream
            // Soft pastel light behind the glass so the frosting has something to blur.
            Group {
                glow(Tint.all[1], 330, x: -230, y: -120)
                glow(Tint.all[2], 360, x: 250, y: 140)
                glow(Tint.all[3], 300, x: 120, y: -170)
                glow(Tint.all[0], 260, x: -150, y: 190)
            }
            .opacity(dark ? 0.3 : 0.45)
            Canvas { ctx, size in
                let dot = Color.primary.opacity(dark ? 0.16 : 0.13)
                for x in stride(from: 9.0, to: size.width, by: 18) {
                    for y in stride(from: 9.0, to: size.height, by: 18) {
                        ctx.fill(Path(ellipseIn: CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6)), with: .color(dot))
                    }
                }
            }
        }
        .opacity(0.8)   // a hint of the desktop shows through
    }
}

struct BoardView: View {
    @ObservedObject var store: NoteStore

    var body: some View {
        ZStack {
            BoardBackground()
                .frame(width: boardSize.width, height: boardSize.height)
                .clipped()
                .onTapGesture(count: 2, coordinateSpace: .named("board")) { p in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { _ = store.add(at: p) }
                }
                .contextMenu { addMenu }

            // Each note travels with the stickers and magnets stuck to it.
            ForEach(store.notes) { note in
                ZStack {
                    GlassNoteView(note: store.binding(note.id),
                                  onDelete: { store.delete(note.id) },
                                  onLift: { store.lift(note.id) },
                                  addMenu: AnyView(addMenu))
                    ForEach(store.decor.filter { $0.noteID == note.id }) { d in
                        DecorView(item: d, position: store.position(of: d), store: store).zIndex(d.z)
                    }
                }
                .zIndex(note.z)
            }

            ForEach(store.decor.filter { $0.noteID == nil }) { d in
                DecorView(item: d, position: store.position(of: d), store: store)
                    .zIndex(1_000_000 + d.z)
            }

            if let at = store.pickerAt {
                Color.black.opacity(0.08)
                    .onTapGesture { store.pickerAt = nil }
                    .zIndex(2_000_000)
                EmojiPicker(store: store, at: at).zIndex(2_000_001)
            }

            if store.notes.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "note.text").font(.system(size: 26, weight: .light))
                    Text("Double-click anywhere to add a note")
                        .font(.system(size: 13, design: .rounded))
                }
                .foregroundStyle(.secondary)
                .allowsHitTesting(false)
            }
        }
        .coordinateSpace(name: "board")
        .frame(width: boardSize.width, height: boardSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(.white.opacity(0.5), lineWidth: 0.75))
        .overlay(alignment: .bottom) { toolbar }
        .overlay(alignment: .top) { undoToast }
    }

    /// Right-click menu for the board and note tops.
    @ViewBuilder private var addMenu: some View {
        Menu("Add sticker") {
            ForEach(Stickers.favourites, id: \.self) { e in
                Button(e) { store.addSticker(e, at: store.pointer) }
            }
            Divider()
            Button("More emoji…") { withAnimation(.spring(response: 0.3)) { store.pickerAt = store.pointer } }
        }
        Menu("Add magnet") {
            ForEach(Stickers.magnetNames.indices, id: \.self) { i in
                Button(Stickers.magnetNames[i]) { store.addMagnet(color: i, at: store.pointer) }
            }
        }
        Divider()
        Button("New note here") {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { _ = store.add(at: store.pointer) }
        }
    }

    @ViewBuilder private var undoToast: some View {
        if store.recentlyDeleted != nil {
            HStack(spacing: 10) {
                Text("Note deleted").foregroundStyle(.secondary)
                Button("Undo  ⌘Z") { store.undoDelete() }
                    .buttonStyle(.plain)
                    .fontWeight(.semibold)
            }
            .font(.system(size: 12, design: .rounded))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 0.75))
            .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            ToolbarButton(icon: "plus", help: "New note") {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { _ = store.add() }
            }
            Text("\(store.notes.count) note\(store.notes.count == 1 ? "" : "s")")
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
            ToolbarButton(icon: "power", help: "Quit Glass Notes") { NSApp.terminate(nil) }
        }
        .padding(5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
        .padding(.bottom, 12)
    }
}

struct ToolbarButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    @StateObject private var ui = ViewState()

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(Circle().fill(.white.opacity(ui.hovering ? 0.45 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { ui.hovering = $0 }
        .help(help)
    }
}

// MARK: - App

/// Borderless, fully transparent panel so the desktop shows through the board.
final class BoardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    var store: NoteStore?
    var onClose: (() -> Void)?

    override func sendEvent(_ e: NSEvent) {
        if e.type == .rightMouseDown || (e.type == .leftMouseDown && e.modifierFlags.contains(.control)) {
            let p = e.locationInWindow
            store?.pointer = CGPoint(x: p.x, y: frame.height - p.y)   // board coordinates, top-left origin
        }
        super.sendEvent(e)
    }

    /// A menu bar app has no Edit menu, so the usual shortcuts are wired up here by hand.
    override func performKeyEquivalent(with e: NSEvent) -> Bool {
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard e.type == .keyDown, mods.contains(.command), let key = e.charactersIgnoringModifiers?.lowercased()
        else { return super.performKeyEquivalent(with: e) }
        let typing = firstResponder is NSTextView
        switch (key, mods.contains(.shift)) {
        case ("x", false): return NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self)
        case ("c", false): return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
        case ("v", false): return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
        case ("a", false): return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
        case ("z", false):
            if !typing, store?.undoDelete() == true { return true }
            return NSApp.sendAction(Selector(("undo:")), to: nil, from: self)
        case ("z", true): return NSApp.sendAction(Selector(("redo:")), to: nil, from: self)
        case ("n", false):
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { _ = store?.add() }
            return true
        case ("w", false):
            onClose?()
            return true
        default:
            return super.performKeyEquivalent(with: e)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = NoteStore()
    var item: NSStatusItem!
    var panel: BoardPanel!
    var monitors: [Any] = []

    func applicationDidFinishLaunching(_ note: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Glass Notes")
        item.button?.target = self
        item.button?.action = #selector(toggle)

        panel = BoardPanel(contentRect: NSRect(origin: .zero, size: boardSize),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.becomesKeyOnlyIfNeeded = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false                       // the notes bring their own shadows
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: BoardView(store: store))
        panel.store = store
        panel.onClose = { [weak self] in self?.hide() }

        // Debug: lets a script open the board and log where it landed.
        DistributedNotificationCenter.default().addObserver(forName: .init("GlassNotes.debugToggle"),
                                                            object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.toggle()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let b = self.item.button
                let msg = "visible=\(self.panel.isVisible) frame=\(self.panel.frame) " +
                    "button=\(String(describing: b?.window?.frame)) screen=\(String(describing: b?.window?.screen?.frame)) " +
                    "itemVisible=\(self.item.isVisible) key=\(self.panel.isKeyWindow)\n"
                try? msg.write(to: self.store.dir.appendingPathComponent("debug.log"), atomically: true, encoding: .utf8)
            }
        }
    }

    private var lastHide = Date.distantPast

    @objc func toggle() {
        if panel.isVisible { hide(); return }
        // Clicking the menu bar icon while the board is open can count as a click "outside" the
        // board, which hides it a split second before this runs. Don't reopen it in that case.
        if Date().timeIntervalSince(lastHide) < 0.4 { return }
        show()
    }

    func show() {
        // Drop the board just under the menu bar icon, kept on screen.
        if let button = item.button, let bw = button.window, let screen = bw.screen ?? NSScreen.main {
            let icon = bw.convertToScreen(button.convert(button.bounds, to: nil))
            let vis = screen.visibleFrame
            let x = min(max(icon.midX - boardSize.width / 2, vis.minX + 8), vis.maxX - boardSize.width - 8)
            panel.setFrameOrigin(NSPoint(x: x, y: icon.minY - boardSize.height - 6))
        }
        // Like Spotlight: takes typing without pulling the whole app to the front.
        panel.makeKeyAndOrderFront(nil)
        item.button?.highlight(true)

        // Click anywhere else, or press Esc, to put the board away.
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 { self?.hide(); return nil }
            return e
        } as Any)
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        lastHide = Date()
        item.button?.highlight(false)
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        store.saveNow()
    }
}

// Debug: `GlassNotes --snapshot out.png` renders the board in a normal window, saves a picture and quits.
if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
    let out = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let store = NoteStore()
    let host = NSHostingView(rootView: BoardView(store: store))
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: boardSize),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    window.center()
    window.orderFrontRegardless()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        let view = window.contentView!
        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: out)
        }
        app.terminate(nil)
    }
    app.run()
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
