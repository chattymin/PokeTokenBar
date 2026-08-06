// PokeDexBar 앱 아이콘 생성기 — 도감 그리드(채운 칸 + 아직 못 채운 칸).
// 사용: swift scripts/generate-icon.swift <출력.png> [size=1024]
//
// 2x2 인 이유는 16px 때문이다. 도감은 실제로 6열 그리드지만 16px 아이콘에서 3x3 은 칸 하나가
// 2.5px 라 죽처럼 뭉친다. 2x2 는 16px 에서도 칸이 4px 라 형태가 남는다.
//
// **이 파일이 아이콘의 단일 소스다.** 예전엔 `assets/icon.svg` 로 실제 아이콘을 만들고 이 파일은
// 옛 디자인(포켓볼)을 그대로 그리고 있어서, `generate-icns.sh` 를 돌리면 앱 아이콘이 조용히 옛
// 디자인으로 되돌아갔다. SVG 를 고칠 땐 여기도 같이 고쳐라.
import AppKit

let args = CommandLine.arguments
let outPath = args.count > 1 ? args[1] : "build/icon_1024.png"
let size = args.count > 2 ? (Int(args[2]) ?? 1024) : 1024

let S = CGFloat(size)
let f = S / 100.0   // 시안 단위(100x100, 위가 원점) → 픽셀

/// 시안(top-down) 좌표 → NSImage(bottom-up) 사각형.
func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
    NSRect(x: x * f, y: S - (y + h) * f, width: w * f, height: h * f)
}
func col(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a)
}

let bgTop = col(23, 27, 35)      // #171b23 — 앱의 어두운 팝오버와 같은 계열
let bgBot = col(10, 12, 17)      // #0a0c11
let accent = col(240, 81, 56)    // #f05138

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current
ctx?.imageInterpolation = .high
ctx?.shouldAntialias = true

// 1) 스퀘어클 배경
let bgPath = NSBezierPath(roundedRect: R(3, 3, 94, 94), xRadius: 22 * f, yRadius: 22 * f)
NSGradient(starting: bgTop, ending: bgBot)?.draw(in: bgPath, angle: 270)

// 2) 도감 그리드 — 채운 칸과 아직 못 채운 칸이 섞여 있다.
//    "모으는 중"이 이 앱의 상태다. 다 채운 그리드는 할 일이 없어 보이고, 균일하게 채운 2x2 는
//    런처 아이콘처럼 읽힌다. 그래서 큰 사이즈는 3x3 으로 성긴 패턴을 보여준다.
//    작은 사이즈에서만 2x2 로 떨어뜨린다 — 16px 에서 3x3 은 칸이 2.5px 라 죽처럼 뭉친다.
//    (사이즈마다 직접 렌더하는 스크립트라 이렇게 나눌 수 있다. 다운스케일이면 불가능하다.)
let columns = size >= 64 ? 3 : 2
/// 채운 칸의 (행, 열). 대각선으로 비어 있어 "아직 남았다"가 보인다.
let filled: Set<[Int]> = columns == 3
    ? [[0, 0], [0, 1], [1, 0], [1, 2], [2, 1]]
    : [[0, 0], [0, 1], [1, 0]]

let span: CGFloat = 62                                   // 그리드 전체가 차지하는 폭
let gap: CGFloat = columns == 3 ? 5 : 7
let cell = (span - gap * CGFloat(columns - 1)) / CGFloat(columns)
let origin = (100 - span) / 2
let radius = (columns == 3 ? 4.5 : 7) * f

for row in 0..<columns {
    for column in 0..<columns {
        let rect = R(origin + CGFloat(column) * (cell + gap),
                     origin + CGFloat(row) * (cell + gap),
                     cell, cell)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        if filled.contains([row, column]) {
            accent.setFill()
            path.fill()
        } else {
            // 아직 못 채운 칸 — 윤곽선만(도감의 실루엣 칸에 해당).
            accent.withAlphaComponent(0.34).setStroke()
            path.lineWidth = (columns == 3 ? 3 : 4) * f
            path.stroke()
        }
    }
}

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
