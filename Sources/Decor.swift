// Stickers (Apple emoji) and decorative magnets. Dropped on a note, they stick to it and move with it.
import SwiftUI
import AppKit

struct Decor: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case sticker, magnet }
    var id = UUID()
    var kind: Kind
    var emoji = ""
    var color = 0
    var size: Double
    var rotation = Double.random(in: -12...12)
    /// Board position, or the offset from the note's centre when stuck to a note.
    var x: Double = 0
    var y: Double = 0
    var noteID: UUID?
    var z: Double = 0
}

enum Stickers {
    static let favourites = ["⭐️", "💖", "✨", "🌸", "🔥", "✅", "📌", "🎉", "🌈", "☕️", "🐱", "🦄", "📚", "💡", "🍀", "🎵"]
    static let all: [String] = Array(
        "😀😂🥹😍🥰😎🤓🥳😴🤯😇🙌👏👍💪🙏👀🧠💅🫶❤️🧡💛💚💙💜🖤🤍💖💯✨⭐️🌟💫🌈☀️🌙⚡️🔥❄️" +
        "🌸🌷🌻🌹🍀🌿🌵🍄🐱🐶🐰🦊🐻🐼🐨🦄🐝🦋🐢🐙🐳🦖🍓🍒🍑🍋🍉🍩🍪🧁🍰🍫🍿☕️🧋🍵" +
        "🎉🎈🎁🎀🏆🥇🎯🎨🎵🎧📚✏️📝📌📎💡🔑🔒⏰📅💌📷💻📱🚀✈️🏠🌍🧸🪴🕯️💎🔮🧩✅❌⚠️❓❗️💤"
    ).map(String.init)
    static let magnetNames = ["Peach", "Pink", "Mint", "Lavender", "Sky"]
}

// MARK: - Store

extension NoteStore {
    func position(of d: Decor) -> CGPoint {
        if let nid = d.noteID, let n = notes.first(where: { $0.id == nid }) {
            return CGPoint(x: n.x + d.x, y: n.y + d.y)
        }
        return CGPoint(x: d.x, y: d.y)
    }

    /// The topmost note under a point, if any.
    private func noteUnder(_ p: CGPoint) -> Note? {
        notes.filter { abs(p.x - $0.x) <= $0.size.width / 2 && abs(p.y - $0.y) <= $0.size.height / 2 }
            .max { $0.z < $1.z }
    }

    private func place(_ d: inout Decor, at p: CGPoint) {
        let p = CGPoint(x: min(max(p.x, 12), boardSize.width - 12), y: min(max(p.y, 12), boardSize.height - 12))
        if let n = noteUnder(p) {
            d.noteID = n.id; d.x = p.x - n.x; d.y = p.y - n.y
        } else {
            d.noteID = nil; d.x = p.x; d.y = p.y
        }
        d.z = (decor.map(\.z).max() ?? 0) + 1
    }

    func addSticker(_ emoji: String, at p: CGPoint) {
        var d = Decor(kind: .sticker, emoji: emoji, size: 44)
        place(&d, at: p)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { decor.append(d) }
    }

    func addMagnet(color: Int, at p: CGPoint) {
        var d = Decor(kind: .magnet, color: color, size: 28, rotation: 0)
        place(&d, at: p)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { decor.append(d) }
    }

    func moveDecor(_ id: UUID, to p: CGPoint) {
        guard let i = decor.firstIndex(where: { $0.id == id }) else { return }
        var d = decor[i]
        place(&d, at: p)
        decor[i] = d
    }

    func resizeDecor(_ id: UUID, by factor: Double) {
        guard let i = decor.firstIndex(where: { $0.id == id }) else { return }
        let range: ClosedRange<Double> = decor[i].kind == .sticker ? 22...120 : 18...48
        withAnimation(.spring(response: 0.3)) { decor[i].size = min(max(decor[i].size * factor, range.lowerBound), range.upperBound) }
    }

    func removeDecor(_ id: UUID) {
        withAnimation(.spring(response: 0.3)) { decor.removeAll { $0.id == id } }
    }
}

// MARK: - Views

struct DecorView: View {
    let item: Decor
    let position: CGPoint
    let store: NoteStore

    @StateObject private var ui = ViewState()

    var body: some View {
        let lifted = ui.dragPoint != nil
        face
            .rotationEffect(.degrees(item.rotation))
            .scaleEffect(lifted ? 1.15 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: lifted)
            .position(ui.dragPoint ?? position)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("board"))
                    .onChanged { v in
                        ui.dragPoint = CGPoint(x: position.x + v.translation.width, y: position.y + v.translation.height)
                    }
                    .onEnded { _ in
                        if let p = ui.dragPoint { store.moveDecor(item.id, to: p) }
                        ui.dragPoint = nil
                    }
            )
            .contextMenu {
                Button("Bigger") { store.resizeDecor(item.id, by: 1.25) }
                Button("Smaller") { store.resizeDecor(item.id, by: 0.8) }
                Divider()
                Button("Remove") { store.removeDecor(item.id) }
            }
            .transition(.scale(scale: 0.3).combined(with: .opacity))
    }

    @ViewBuilder private var face: some View {
        switch item.kind {
        case .sticker:
            // Die-cut sticker: a white outline built from stacked shadows, then a soft drop shadow.
            Text(item.emoji)
                .font(.system(size: item.size))
                .shadow(color: .white, radius: 0, x: 1.4, y: 0)
                .shadow(color: .white, radius: 0, x: -1.4, y: 0)
                .shadow(color: .white, radius: 0, x: 0, y: 1.4)
                .shadow(color: .white, radius: 0, x: 0, y: -1.4)
                .shadow(color: .black.opacity(ui.dragPoint != nil ? 0.3 : 0.2), radius: ui.dragPoint != nil ? 7 : 3, y: ui.dragPoint != nil ? 6 : 2)
        case .magnet:
            MagnetDome(color: Tint.all[item.color % Tint.all.count], size: item.size)
        }
    }
}

/// A glossy round fridge magnet.
struct MagnetDome: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(color)
            Circle().fill(RadialGradient(colors: [.white.opacity(0.55), .clear],
                                         center: UnitPoint(x: 0.32, y: 0.28), startRadius: 0, endRadius: size * 0.55))
            Circle().fill(RadialGradient(colors: [.clear, .black.opacity(0.28)],
                                         center: .center, startRadius: size * 0.28, endRadius: size * 0.56))
            Ellipse()
                .fill(.white.opacity(0.85))
                .frame(width: size * 0.34, height: size * 0.18)
                .rotationEffect(.degrees(-30))
                .offset(x: -size * 0.15, y: -size * 0.2)
                .blur(radius: 0.8)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.35), radius: 2, y: 2.5)
        .shadow(color: .black.opacity(0.15), radius: 8, y: 6)
    }
}

/// Glass card with a grid of emoji, plus a field for typing or pasting any other emoji.
final class PickerState: ObservableObject {
    @Published var text = ""
}

struct EmojiPicker: View {
    let store: NoteStore
    let at: CGPoint
    @StateObject private var state = PickerState()

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Pick a sticker").font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                Button { store.pickerAt = nil } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 4), count: 10), spacing: 4) {
                    ForEach(Stickers.all, id: \.self) { e in
                        Text(e)
                            .font(.system(size: 24))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                            .onTapGesture { choose(e) }
                    }
                }
            }
            .frame(height: 170)
            TextField("Type or paste any emoji, then press Return", text: $state.text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .rounded))
                .onSubmit {
                    if let c = state.text.first(where: { $0.unicodeScalars.contains { $0.properties.isEmojiPresentation } || $0.unicodeScalars.count > 1 }) {
                        choose(String(c))
                    }
                }
        }
        .padding(14)
        .frame(width: 420)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.6), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.18), radius: 20, y: 10)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    private func choose(_ e: String) {
        store.addSticker(e, at: at)
        store.pickerAt = nil
    }
}
