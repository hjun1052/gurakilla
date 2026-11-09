// Draws the DMG window background (640×430 pt) at 1x and 2x. The bottom 30 pt stay empty for Finder's path bar.
//
//   swift scripts/dmg-background.swift <out-dir>     writes background.png and background@2x.png
//
// Icon positions in make-dmg.sh must match: app at (160, 150), Applications at (480, 150).
import AppKit

let size = CGSize(width: 640, height: 430)

func text(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight = .regular, _ color: NSColor = .black) -> NSAttributedString {
    NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
}

func centered(_ s: NSAttributedString, y: CGFloat) {
    let w = s.size().width
    s.draw(at: CGPoint(x: (size.width - w) / 2, y: y))
}

func draw() {
    NSColor(white: 0.97, alpha: 1).setFill()
    CGRect(origin: .zero, size: size).fill()

    // Arrow from app to Applications.
    let arrow = NSBezierPath()
    arrow.move(to: CGPoint(x: 245, y: 150)); arrow.line(to: CGPoint(x: 385, y: 150))
    arrow.lineWidth = 6; arrow.lineCapStyle = .round
    let head = NSBezierPath()
    head.move(to: CGPoint(x: 370, y: 132)); head.line(to: CGPoint(x: 395, y: 150)); head.line(to: CGPoint(x: 370, y: 168))
    head.lineWidth = 6; head.lineCapStyle = .round; head.lineJoinStyle = .round
    NSColor.systemBlue.setStroke(); arrow.stroke(); head.stroke()

    let gray = NSColor(white: 0.35, alpha: 1)
    centered(text("응용 프로그램 폴더로 드래그하여 설치", 13, .semibold, .black), y: 72)
    centered(text("Drag to Applications to install", 11, .regular, gray), y: 92)

    // First-launch box.
    let box = CGRect(x: 30, y: 262, width: 580, height: 116)
    NSColor.white.setFill()
    let boxPath = NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10)
    boxPath.fill()
    NSColor(white: 0.85, alpha: 1).setStroke(); boxPath.lineWidth = 1; boxPath.stroke()

    let x = box.minX + 18
    text("처음 실행할 때 macOS가 차단하는 경우", 13, .semibold).draw(at: CGPoint(x: x, y: 274))
    text("시스템 설정 → 개인정보 보호 및 보안 → 하단의 ‘그래도 열기’ 클릭", 12).draw(at: CGPoint(x: x, y: 296))
    text("macOS 14에서는 앱을 오른쪽 클릭 → ‘열기’도 가능", 12, .regular, gray).draw(at: CGPoint(x: x, y: 314))
    text("If macOS blocks the first launch: System Settings → Privacy & Security → Open Anyway.", 10.5, .regular, gray)
        .draw(at: CGPoint(x: x, y: 338))
    text("On macOS 14, right-click the app → Open also works.", 10.5, .regular, gray).draw(at: CGPoint(x: x, y: 354))
}

func render(scale: CGFloat, to url: URL) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    let cg = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    // Top-left origin, so the y values above read like the Finder icon positions.
    cg.translateBy(x: 0, y: size.height); cg.scaleBy(x: 1, y: -1)  // rep.size already maps points to pixels
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    draw()
    NSGraphicsContext.current = nil
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
try render(scale: 1, to: out.appendingPathComponent("background.png"))
try render(scale: 2, to: out.appendingPathComponent("background@2x.png"))
