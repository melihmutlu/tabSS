import CoreGraphics
import Testing
@testable import TabssCore

/// Property checks: Up/Down follow what TileLayout draws, never leave the grid, and stop at the edges.
struct GridNavigationPropertyTests {
    private let metrics = TileLayout.Metrics()

    /// Layouts over a sweep of item counts and panel sizes, so scales below 1 (odd step widths, rounded x) are covered.
    private func layouts() -> [(count: Int, layout: TileLayout)] {
        var result: [(Int, TileLayout)] = []
        for count in 1...60 {
            for width in stride(from: 250.0, through: 2600.0, by: 97.0) {
                for height in [5000.0, 900.0, 600.0, 400.0] {
                    result.append((count, TileLayout(itemCount: count, maxPanelSize: CGSize(width: width, height: height), metrics: metrics)))
                }
            }
        }
        return result
    }

    private func moved(_ count: Int, _ columns: Int, from index: Int, down: Bool) -> Int {
        var selection = Selection(count: count, index: index, columns: columns)
        if down { selection.down() } else { selection.up() }
        return selection.index
    }

    @Test func movesStayInGridAndChangeExactlyOneRowOrStopAtEdges() {
        for (count, layout) in layouts() {
            let grid = GridPosition(count: count, columns: layout.columns)
            for index in 0..<count {
                for down in [true, false] {
                    let target = moved(count, layout.columns, from: index, down: down)
                    #expect((0..<count).contains(target))
                    let edge = down ? grid.row(of: index) == grid.rows - 1 : grid.row(of: index) == 0
                    if edge {
                        #expect(target == index, "count \(count) cols \(layout.columns) idx \(index) down \(down)")
                    } else {
                        #expect(grid.row(of: target) == grid.row(of: index) + (down ? 1 : -1))
                    }
                }
            }
        }
    }

    @Test func movesLandOnTheTileDrawnNearest() {
        var strictMismatches: Set<String> = []
        for (count, layout) in layouts() {
            let grid = GridPosition(count: count, columns: layout.columns)
            let frames = layout.tileFrames
            for index in 0..<count {
                for down in [true, false] {
                    let row = grid.row(of: index) + (down ? 1 : -1)
                    guard (0..<grid.rows).contains(row) else { continue }
                    let target = moved(count, layout.columns, from: index, down: down)
                    let distances = grid.indices(inRow: row).map { abs(frames[$0].midX - frames[index].midX) }
                    let best = distances.min()!
                    let chosen = abs(frames[target].midX - frames[index].midX)
                    // Tie-break rounding of drawn x may differ by at most 1pt from the logical grid.
                    #expect(chosen - best <= 1.0, "count \(count) cols \(layout.columns) idx \(index) -> \(target)")
                    if chosen > best {
                        strictMismatches.insert("count \(count) cols \(layout.columns) scale \(layout.scale) idx \(index) down \(down) -> \(target) (off by \(chosen - best)pt)")
                    }
                }
            }
        }
        // Informational: logical ties drawn 1pt apart because of `.rounded()` on odd step widths.
        if !strictMismatches.isEmpty {
            print("drawn-tie mismatches: \(strictMismatches.count); e.g. \(strictMismatches.sorted().prefix(3))")
        }
    }

    /// With column memory, any vertical move followed by the opposite one returns to where it started.
    @Test func everyVerticalRoundTripReturns() {
        for columns in 1...12 {
            for count in columns...(columns * 6) {
                for start in 0..<count {
                    for down in [true, false] {
                        var selection = Selection(count: count, index: start, columns: columns)
                        down ? selection.down() : selection.up()
                        guard selection.index != start else { continue }
                        down ? selection.up() : selection.down()
                        #expect(selection.index == start, "count \(count) cols \(columns) from \(start) \(down ? "down" : "up")")
                    }
                }
            }
        }
    }
}
