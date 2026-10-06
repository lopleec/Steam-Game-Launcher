import Foundation

struct WallTile {
    var rect: CGRect
    var gameIndex: Int
}

enum WallLayout {
    /// Use world-space indices, so artwork stays continuous across every tile boundary.
    static func tiles(size: CGSize, width: Double, gap: Double, elapsed: Double, speed: Double,
                      vertical: Bool, alternating: Bool, reverse: Bool, gameCount: Int) -> [WallTile] {
        guard gameCount > 0 else { return [] }
        let height = width * 1.5, pitchX = width + gap, pitchY = height + gap
        let columns = Int(ceil(size.width / pitchX)) + 2, rows = Int(ceil(size.height / pitchY)) + 2
        var result: [WallTile] = []
        func modulo(_ index: Int) -> Int { ((index % gameCount) + gameCount) % gameCount }
        if vertical {
            for column in -1..<columns {
                let direction = (alternating && abs(column) % 2 == 1 ? -1.0 : 1.0) * (reverse ? -1 : 1)
                let phase = elapsed * speed * direction
                let step = Int(floor(phase / pitchY)), offset = phase - Double(step) * pitchY
                let stagger = abs(column) % 2 == 0 ? 0 : pitchY * 0.42
                for row in -2..<rows {
                    result.append(WallTile(rect: CGRect(x: Double(column) * pitchX, y: Double(row) * pitchY - offset + stagger, width: width, height: height),
                                           gameIndex: modulo(row + step + column * 7)))
                }
            }
        } else {
            for row in -1..<rows {
                let direction = (alternating && abs(row) % 2 == 1 ? -1.0 : 1.0) * (reverse ? -1 : 1)
                let phase = elapsed * speed * direction
                let step = Int(floor(phase / pitchX)), offset = phase - Double(step) * pitchX
                let stagger = abs(row) % 2 == 0 ? 0 : pitchX * 0.42
                for column in -2..<columns {
                    result.append(WallTile(rect: CGRect(x: Double(column) * pitchX - offset + stagger, y: Double(row) * pitchY, width: width, height: height),
                                           gameIndex: modulo(column + step + row * 7)))
                }
            }
        }
        return result
    }
}
