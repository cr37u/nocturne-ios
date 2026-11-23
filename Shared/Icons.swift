import SwiftUI
import UIKit

/// Lucide icons (same set as the Android app and the iOS boards), drawn from their SVG path data
/// on a 24×24 grid. Stroked with round caps/joins; some parts are filled.
struct IconPart {
    enum Kind { case path(String), circle(CGFloat, CGFloat, CGFloat), rect(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat) }
    let kind: Kind
    var filled = false
    var stroked = true
}

enum Icon: String, CaseIterable {
    case moon, moonWave, search, sliders, link, music, more, moreHorizontal, pause, play, next, previous,
         chevronDown, chevronLeft, chevronRight, listPlus, heart, shuffle, `repeat`, volume, airplay, queue,
         plus, xmark, check, trash, pencil, download, lyrics, retry, sort, globe, folder, info, layers,
         activity, storage, clipboard, youtube

    var parts: [IconPart] {
        switch self {
        case .moon:
            return [.init(kind: .path("M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z"))]
        case .moonWave:
            return [.init(kind: .path("M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z")),
                    .init(kind: .path("M8 13v2M11 11v6M14 12.5v3"))]
        case .search:
            return [.init(kind: .circle(11, 11, 7)), .init(kind: .path("m20 20-3.5-3.5"))]
        case .sliders:
            return [.init(kind: .path("M4 6h10M18 6h2M4 12h4M12 12h8M4 18h12")),
                    .init(kind: .circle(16, 6, 2)), .init(kind: .circle(10, 12, 2)), .init(kind: .circle(18, 18, 2))]
        case .link:
            return [.init(kind: .path("M10 13a5 5 0 0 0 7 0l3-3a5 5 0 0 0-7-7l-1 1")),
                    .init(kind: .path("M14 11a5 5 0 0 0-7 0l-3 3a5 5 0 0 0 7 7l1-1"))]
        case .music:
            return [.init(kind: .path("M9 18V5l12-2v13")), .init(kind: .circle(6, 18, 3)), .init(kind: .circle(18, 16, 3))]
        case .more:
            return [.init(kind: .circle(12, 5, 1.6), filled: true, stroked: false),
                    .init(kind: .circle(12, 12, 1.6), filled: true, stroked: false),
                    .init(kind: .circle(12, 19, 1.6), filled: true, stroked: false)]
        case .moreHorizontal:
            return [.init(kind: .circle(5, 12, 1.6), filled: true, stroked: false),
                    .init(kind: .circle(12, 12, 1.6), filled: true, stroked: false),
                    .init(kind: .circle(19, 12, 1.6), filled: true, stroked: false)]
        case .pause:
            return [.init(kind: .rect(6, 4, 4, 16, 1), filled: true, stroked: false),
                    .init(kind: .rect(14, 4, 4, 16, 1), filled: true, stroked: false)]
        case .play:
            return [.init(kind: .path("M7 4.5v15a1 1 0 0 0 1.5.86l12.2-7.5a1 1 0 0 0 0-1.72L8.5 3.64A1 1 0 0 0 7 4.5z"), filled: true, stroked: false)]
        case .next:
            return [.init(kind: .path("m5 4 10 8-10 8z"), filled: true), .init(kind: .path("M19 5v14"))]
        case .previous:
            return [.init(kind: .path("M19 20 9 12l10-8z"), filled: true), .init(kind: .path("M5 19V5"))]
        case .chevronDown:
            return [.init(kind: .path("m6 9 6 6 6-6"))]
        case .chevronLeft:
            return [.init(kind: .path("m15 18-6-6 6-6"))]
        case .chevronRight:
            return [.init(kind: .path("m9 18 6-6-6-6"))]
        case .listPlus:
            return [.init(kind: .path("M3 6h12M3 12h12M3 18h7")), .init(kind: .path("M18 14v6M15 17h6"))]
        case .heart:
            return [.init(kind: .path("M19 14c1.5-1.5 3-3.2 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.8 0-3 .5-4.5 2-1.5-1.5-2.7-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4 3 5.5l7 7z"))]
        case .shuffle:
            return [.init(kind: .path("M16 3h5v5")), .init(kind: .path("M4 20 21 3")), .init(kind: .path("M21 16v5h-5")),
                    .init(kind: .path("m15 15 6 6")), .init(kind: .path("M4 4l5 5"))]
        case .repeat:
            return [.init(kind: .path("m17 2 4 4-4 4")), .init(kind: .path("M3 11v-1a4 4 0 0 1 4-4h14")),
                    .init(kind: .path("m7 22-4-4 4-4")), .init(kind: .path("M21 13v1a4 4 0 0 1-4 4H3"))]
        case .volume:
            return [.init(kind: .path("M11 5 6 9H2v6h4l5 4z")), .init(kind: .path("M15.5 8.5a5 5 0 0 1 0 7"))]
        case .airplay:
            return [.init(kind: .path("M5 17H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2h-1")),
                    .init(kind: .path("m12 15 5 6H7z"))]
        case .queue:
            return [.init(kind: .path("M3 6h13M3 12h13M3 18h9")), .init(kind: .path("M17 15v6l4-3z"), filled: true)]
        case .plus:
            return [.init(kind: .path("M12 5v14M5 12h14"))]
        case .xmark:
            return [.init(kind: .path("M18 6 6 18M6 6l12 12"))]
        case .check:
            return [.init(kind: .path("M20 6 9 17l-5-5"))]
        case .trash:
            return [.init(kind: .path("M3 6h18")), .init(kind: .path("M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6")),
                    .init(kind: .path("M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"))]
        case .pencil:
            return [.init(kind: .path("M17 3a2.83 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5z"))]
        case .download:
            return [.init(kind: .path("M12 15V3")), .init(kind: .path("m7 10 5 5 5-5")),
                    .init(kind: .path("M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"))]
        case .lyrics:
            return [.init(kind: .path("m11 7.6-6 8.2a1 1 0 0 0 .1 1.3l.8.8a1 1 0 0 0 1.3.1L15.1 12")),
                    .init(kind: .path("M16.5 21.2C15.5 20.5 14.4 20 13 20c-2 0-3.9 2.4-6 2-2-.4-2.8-3.4-1.5-4.5")),
                    .init(kind: .circle(16, 7, 5))]
        case .retry:
            return [.init(kind: .path("M21 12a9 9 0 1 1-3-6.7L21 8")), .init(kind: .path("M21 3v5h-5"))]
        case .sort:
            return [.init(kind: .path("m21 16-4 4-4-4")), .init(kind: .path("M17 20V4")),
                    .init(kind: .path("m3 8 4-4 4 4")), .init(kind: .path("M7 4v16"))]
        case .globe:
            return [.init(kind: .circle(12, 12, 10)), .init(kind: .path("M2 12h20")),
                    .init(kind: .path("M12 2a15 15 0 0 1 4 10 15 15 0 0 1-4 10 15 15 0 0 1-4-10 15 15 0 0 1 4-10z"))]
        case .folder:
            return [.init(kind: .path("M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.7-.9L9.6 3.9A2 2 0 0 0 7.9 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2z"))]
        case .info:
            return [.init(kind: .circle(12, 12, 10)), .init(kind: .path("M12 16v-4M12 8h.01"))]
        case .layers:
            return [.init(kind: .path("m12 2 10 5-10 5L2 7z")), .init(kind: .path("m2 17 10 5 10-5")), .init(kind: .path("m2 12 10 5 10-5"))]
        case .activity:
            return [.init(kind: .path("M22 12h-4l-3 9L9 3l-3 9H2"))]
        case .storage:
            return [.init(kind: .path("M22 12H2")),
                    .init(kind: .path("M5.5 5.1 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.5-6.9A2 2 0 0 0 16.8 4H7.2a2 2 0 0 0-1.7 1.1z"))]
        case .clipboard:
            return [.init(kind: .rect(8, 2, 8, 4, 1)),
                    .init(kind: .path("M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"))]
        case .youtube:
            return [.init(kind: .path("M2.5 17a24 24 0 0 1 0-10 2 2 0 0 1 1.4-1.4 49.6 49.6 0 0 1 16.2 0A2 2 0 0 1 21.5 7a24 24 0 0 1 0 10 2 2 0 0 1-1.4 1.4 49.6 49.6 0 0 1-16.2 0A2 2 0 0 1 2.5 17")),
                    .init(kind: .path("m10 15 5-3-5-3z"), filled: true)]
        }
    }
}

/// Renders an `Icon` at `size` points in the current foreground style.
struct IconView: View {
    let icon: Icon
    var size: CGFloat = 20
    var lineWidth: CGFloat = 2
    var filled: Bool = false

    var body: some View {
        let scale = size / 24
        ZStack {
            ForEach(Array(icon.parts.enumerated()), id: \.offset) { _, part in
                let shape = IconShape(kind: part.kind)
                if part.filled || filled {
                    shape.fill(style: FillStyle(eoFill: false))
                }
                if part.stroked {
                    shape.stroke(style: StrokeStyle(lineWidth: lineWidth * scale, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct IconShape: Shape {
    let kind: IconPart.Kind

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let t = CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: s, y: s)
        let base: Path
        switch kind {
        case .path(let d): base = SVGPath.parse(d)
        case .circle(let cx, let cy, let r): base = Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
        case .rect(let x, let y, let w, let h, let rx):
            base = Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: rx)
        }
        return base.applying(t)
    }
}

/// Minimal SVG path-data parser (M L H V C S Q A Z, absolute and relative) — enough for Lucide.
enum SVGPath {
    private static var cache: [String: Path] = [:]
    private static let lock = NSLock()

    static func parse(_ d: String) -> Path {
        lock.lock()
        if let hit = cache[d] { lock.unlock(); return hit }
        lock.unlock()
        let path = build(tokenize(d))
        lock.lock()
        cache[d] = path
        lock.unlock()
        return path
    }

    static func tokenize(_ d: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var previous: Character = " "
        func flush() { if !current.isEmpty { tokens.append(current); current = "" } }
        for ch in d {
            if ch.isLetter && ch != "e" && ch != "E" {
                flush(); tokens.append(String(ch))
            } else if ch == "," || ch.isWhitespace {
                flush()
            } else if ch == "-" {
                if previous == "e" || previous == "E" { current.append(ch) } else { flush(); current.append(ch) }
            } else if ch == "." {
                if current.contains(".") { flush() }
                current.append(ch)
            } else {
                current.append(ch)
            }
            previous = ch
        }
        flush()
        return tokens
    }

    private static func build(_ input: [String]) -> Path {
        var tokens = input
        var path = Path()
        var i = 0
        var cmd: Character = "M"
        var cur = CGPoint.zero
        var start = CGPoint.zero
        var lastCtrl: CGPoint?

        func n() -> CGFloat {
            guard i < tokens.count else { return 0 }
            let v = Double(tokens[i]) ?? 0
            i += 1
            return CGFloat(v)
        }
        // Arc flags may be glued to what follows ("011.5"); split them off.
        func f() -> Bool {
            guard i < tokens.count else { return false }
            let tok = tokens[i]
            if tok.count > 1, let first = tok.first, first == "0" || first == "1" {
                tokens[i] = String(tok.dropFirst())
                return first == "1"
            }
            i += 1
            return tok == "1"
        }
        func numberAhead() -> Bool {
            guard i < tokens.count, let c = tokens[i].first else { return false }
            return c.isNumber || c == "-" || c == "."
        }

        while i < tokens.count {
            let tok = tokens[i]
            if tok.count == 1, let c = tok.first, c.isLetter {
                cmd = c
                i += 1
                if cmd == "z" || cmd == "Z" {
                    path.closeSubpath()
                    cur = start
                    lastCtrl = nil
                    continue
                }
            } else if !numberAhead() {
                i += 1
                continue
            }
            let rel = cmd.isLowercase
            let base = rel ? cur : CGPoint.zero
            switch cmd {
            case "M", "m":
                let p = CGPoint(x: base.x + n(), y: base.y + n())
                path.move(to: p); cur = p; start = p; lastCtrl = nil
                cmd = rel ? "l" : "L" // following pairs are implicit linetos
            case "L", "l":
                let p = CGPoint(x: base.x + n(), y: base.y + n())
                path.addLine(to: p); cur = p; lastCtrl = nil
            case "H", "h":
                let x = (rel ? cur.x : 0) + n()
                cur = CGPoint(x: x, y: cur.y); path.addLine(to: cur); lastCtrl = nil
            case "V", "v":
                let y = (rel ? cur.y : 0) + n()
                cur = CGPoint(x: cur.x, y: y); path.addLine(to: cur); lastCtrl = nil
            case "C", "c":
                let c1 = CGPoint(x: base.x + n(), y: base.y + n())
                let c2 = CGPoint(x: base.x + n(), y: base.y + n())
                let p = CGPoint(x: base.x + n(), y: base.y + n())
                path.addCurve(to: p, control1: c1, control2: c2); cur = p; lastCtrl = c2
            case "S", "s":
                let c1 = lastCtrl.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                let c2 = CGPoint(x: base.x + n(), y: base.y + n())
                let p = CGPoint(x: base.x + n(), y: base.y + n())
                path.addCurve(to: p, control1: c1, control2: c2); cur = p; lastCtrl = c2
            case "Q", "q":
                let c = CGPoint(x: base.x + n(), y: base.y + n())
                let p = CGPoint(x: base.x + n(), y: base.y + n())
                path.addQuadCurve(to: p, control: c); cur = p; lastCtrl = c
            case "A", "a":
                let rx = n(), ry = n()
                _ = n() // x-axis rotation: unused (Lucide arcs are unrotated)
                let large = f()
                let sweep = f()
                let p = CGPoint(x: base.x + n(), y: base.y + n())
                addArc(&path, from: cur, to: p, rx: rx, ry: ry, large: large, sweep: sweep)
                cur = p; lastCtrl = nil
            default:
                i += 1
            }
        }
        return path
    }

    /// Endpoint → center parameterisation, sampled into short segments (y-down coordinates).
    private static func addArc(_ path: inout Path, from p1: CGPoint, to p2: CGPoint, rx rxIn: CGFloat, ry ryIn: CGFloat, large: Bool, sweep: Bool) {
        var rx = abs(rxIn), ry = abs(ryIn)
        if rx == 0 || ry == 0 || p1 == p2 { path.addLine(to: p2); return }
        let dx = (p1.x - p2.x) / 2, dy = (p1.y - p2.y) / 2
        let lambda = (dx * dx) / (rx * rx) + (dy * dy) / (ry * ry)
        if lambda > 1 { let s = sqrt(lambda); rx *= s; ry *= s }
        let num = rx * rx * ry * ry - rx * rx * dy * dy - ry * ry * dx * dx
        let den = rx * rx * dy * dy + ry * ry * dx * dx
        var k = sqrt(max(0, num / den))
        if large == sweep { k = -k }
        let cxp = k * (rx * dy / ry), cyp = k * (-ry * dx / rx)
        let cx = cxp + (p1.x + p2.x) / 2, cy = cyp + (p1.y + p2.y) / 2
        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            return a
        }
        let theta1 = angle(1, 0, (dx - cxp) / rx, (dy - cyp) / ry)
        var dTheta = angle((dx - cxp) / rx, (dy - cyp) / ry, (-dx - cxp) / rx, (-dy - cyp) / ry)
        if !sweep && dTheta > 0 { dTheta -= 2 * .pi }
        if sweep && dTheta < 0 { dTheta += 2 * .pi }
        let steps = max(4, Int(abs(dTheta) / (.pi / 24)))
        for s in 1...steps {
            let t = theta1 + dTheta * CGFloat(s) / CGFloat(steps)
            path.addLine(to: CGPoint(x: cx + rx * cos(t), y: cy + ry * sin(t)))
        }
    }
}
