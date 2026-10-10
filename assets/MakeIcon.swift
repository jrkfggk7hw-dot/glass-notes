// Draws the Glass Notes app icon (a lavender glass note held by a glossy pink magnet)
// and writes a 1024px PNG. Run: swiftc assets/MakeIcon.swift -o /tmp/makeicon && /tmp/makeicon out.png
import SwiftUI
import AppKit

let lavender = Color(red: 0.70, green: 0.66, blue: 0.96)
let lavenderDeep = Color(red: 0.55, green: 0.50, blue: 0.90)
let ink = Color(red: 0.24, green: 0.20, blue: 0.54)
let pink = Color(red: 0.97, green: 0.60, blue: 0.74)
let mint = Color(red: 0.42, green: 0.85, blue: 0.70)
let peach = Color(red: 1.00, green: 0.76, blue: 0.52)

struct Icon: View {
    var body: some View {
        ZStack {
            // macOS icon grid: an 824pt squircle centred on a 1024 canvas.
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.975, blue: 0.93), Color(red: 0.96, green: 0.91, blue: 0.82)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    ZStack {
                        RadialGradient(colors: [pink.opacity(0.45), .clear], center: UnitPoint(x: 0.15, y: 0.12), startRadius: 0, endRadius: 420)
                        RadialGradient(colors: [mint.opacity(0.4), .clear], center: UnitPoint(x: 0.9, y: 0.92), startRadius: 0, endRadius: 440)
                        RadialGradient(colors: [peach.opacity(0.35), .clear], center: UnitPoint(x: 0.1, y: 0.95), startRadius: 0, endRadius: 320)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous))
                )
                .overlay(dots.clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous)))
                .overlay(RoundedRectangle(cornerRadius: 185, style: .continuous)
                    .strokeBorder(.white.opacity(0.7), lineWidth: 3))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.22), radius: 18, y: 12)

            note
                .rotationEffect(.degrees(-4))
                .offset(y: 46)

            magnet.offset(y: -196)
        }
        .frame(width: 1024, height: 1024)
    }

    var dots: some View {
        Canvas { ctx, size in
            for x in stride(from: 26.0, to: size.width, by: 52) {
                for y in stride(from: 26.0, to: size.height, by: 52) {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)),
                             with: .color(Color(red: 0.55, green: 0.48, blue: 0.38).opacity(0.18)))
                }
            }
        }
        .frame(width: 824, height: 824)
    }

    var note: some View {
        let shape = RoundedRectangle(cornerRadius: 70, style: .continuous)
        return shape
            .fill(LinearGradient(colors: [lavender.opacity(0.92), lavenderDeep.opacity(0.95)], startPoint: .top, endPoint: .bottom))
            // glossy curved highlight (an overlay, so its size doesn't push the note around)
            .overlay(
                Ellipse()
                    .fill(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 760, height: 330)
                    .offset(y: -190)
                    .blendMode(.screen)
            )
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 34) {
                    Capsule().fill(ink.opacity(0.32)).frame(width: 300, height: 26)
                    Capsule().fill(ink.opacity(0.32)).frame(width: 230, height: 26)
                    Capsule().fill(ink.opacity(0.32)).frame(width: 270, height: 26)
                }
                .padding(.leading, 76)
                .padding(.top, 200)
            }
        .frame(width: 540, height: 520)
        .clipShape(shape)
        .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.3), .white.opacity(0.08)],
                                                   startPoint: .top, endPoint: .bottom), lineWidth: 5))
        .shadow(color: .black.opacity(0.2), radius: 30, y: 24)
        .shadow(color: lavenderDeep.opacity(0.4), radius: 10, y: 6)
    }

    var magnet: some View {
        ZStack {
            Circle().fill(pink)
            Circle().fill(RadialGradient(colors: [.white.opacity(0.6), .clear], center: UnitPoint(x: 0.32, y: 0.28), startRadius: 0, endRadius: 95))
            Circle().fill(RadialGradient(colors: [.clear, Color(red: 0.6, green: 0.2, blue: 0.35).opacity(0.45)], center: .center, startRadius: 48, endRadius: 92))
            Ellipse().fill(.white.opacity(0.9))
                .frame(width: 58, height: 30)
                .rotationEffect(.degrees(-30))
                .offset(x: -26, y: -34)
                .blur(radius: 2)
        }
        .frame(width: 170, height: 170)
        .shadow(color: .black.opacity(0.35), radius: 8, y: 10)
        .shadow(color: .black.opacity(0.15), radius: 24, y: 20)
    }
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png")
let ok: Bool = MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = 1
    guard let cg = renderer.cgImage else { return false }
    let rep = NSBitmapImageRep(cgImage: cg)
    return (try? rep.representation(using: .png, properties: [:])?.write(to: out)) != nil
}
print(ok ? "wrote \(out.path)" : "render failed")
