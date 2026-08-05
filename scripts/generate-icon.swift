// PokeDexBar 앱 아이콘 생성기 — Ultra-T (포켓볼 + 상단 토큰 T + 레드 스퀘어클)
// 사용: swift scripts/generate-icon.swift <출력.png> [size=1024]
// 좌표는 SVG 시안(viewBox 100x100, 위가 원점)을 기준으로 정의하고 NSImage(아래가 원점)로 변환한다.
import AppKit

let args = CommandLine.arguments
let outPath = args.count > 1 ? args[1] : "build/icon_1024.png"
let size = args.count > 2 ? (Int(args[2]) ?? 1024) : 1024

let S = CGFloat(size)
let f = S / 100.0   // SVG 단위 → 픽셀

// SVG(top-down) 좌표 → NSImage(bottom-up) 변환
func P(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * f, y: S - y * f) }
func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
    NSRect(x: x * f, y: S - (y + h) * f, width: w * f, height: h * f)
}
func col(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: 1)
}

// 팔레트 (시안 #1 Ultra-T)
let bgTop = col(226, 59, 59)     // #e23b3b
let bgBot = col(140, 15, 18)     // #8c0f12
let red   = col(238, 21, 21)     // #ee1515
let white = col(243, 244, 246)   // #f3f4f6
let black = col(22, 24, 29)      // #16181d

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current
ctx?.imageInterpolation = .high
ctx?.shouldAntialias = true

// 1) 스퀘어클 배경 + 세로 그라디언트 (위=밝은 레드, 아래=어두운 레드)
let bgRect = R(3, 3, 94, 94)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 22 * f, yRadius: 22 * f)
NSGradient(starting: bgTop, ending: bgBot)?.draw(in: bgPath, angle: 270)

// 2) 포켓볼 — 중심 (50,52), 반지름 30
let cx: CGFloat = 50, cy: CGFloat = 52, rr: CGFloat = 30
let ballRect = R(cx - rr, cy - rr, rr * 2, rr * 2)
let ballPath = NSBezierPath(ovalIn: ballRect)

NSGraphicsContext.saveGraphicsState()
ballPath.addClip()
// 하단(화이트) 전체 → 상단 레드 → 밴드(블랙)
white.setFill(); ballRect.fill()
red.setFill();   R(0, 0, 100, 47).fill()          // 상단 절반(밴드 위)
black.setFill(); R(0, 47, 100, 10).fill()         // 가로 밴드
// 상단 토큰 T (화이트, Ultra Ball H 위치)
white.setFill()
NSBezierPath(roundedRect: R(39, 31, 22, 5.4), xRadius: 1.2 * f, yRadius: 1.2 * f).fill()   // 가로획
NSBezierPath(roundedRect: R(47.3, 31, 5.4, 15), xRadius: 1.2 * f, yRadius: 1.2 * f).fill() // 세로획
NSGraphicsContext.restoreGraphicsState()

// 3) 외곽 링
black.setStroke()
let ring = NSBezierPath(ovalIn: ballRect.insetBy(dx: 1.4 * f, dy: 1.4 * f))
ring.lineWidth = 2.8 * f
ring.stroke()

// 4) 중앙 버튼 (블랙 링 + 화이트)
black.setFill(); NSBezierPath(ovalIn: R(cx - 9.2, cy - 9.2, 18.4, 18.4)).fill()
white.setFill(); NSBezierPath(ovalIn: R(cx - 5.3, cy - 5.3, 10.6, 10.6)).fill()
black.setStroke()
let btnRing = NSBezierPath(ovalIn: R(cx - 5.3, cy - 5.3, 10.6, 10.6))
btnRing.lineWidth = 0.8 * f
btnRing.stroke()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("PNG 인코딩 실패\n".data(using: .utf8)!)
    exit(1)
}
try? FileManager.default.createDirectory(
    atPath: (outPath as NSString).deletingLastPathComponent,
    withIntermediateDirectories: true)
do {
    try png.write(to: URL(fileURLWithPath: outPath))
    print("saved: \(outPath) (\(size)px)")
} catch {
    FileHandle.standardError.write("쓰기 실패: \(error)\n".data(using: .utf8)!)
    exit(1)
}
