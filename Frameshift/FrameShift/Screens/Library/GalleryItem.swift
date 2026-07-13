import Foundation

/// One gallery unit: a single captured photo, or a whole burst behind its
/// cover. Shared by the preview pager, its filmstrip, and the library grid.
struct GalleryItem: Identifiable {
    var shots: [CapturedPhoto]
    var isBurst: Bool { shots.count > 1 }
    var cover: CapturedPhoto { shots.first { $0.isBurstBest } ?? shots[0] }
    var id: UUID { (isBurst ? shots[0].burstID : nil) ?? shots[0].id }

    /// Groups a newest-first shot list into items, preserving order. Shots
    /// sharing a burstID collapse into one item wherever the first appears.
    static func group(_ shots: [CapturedPhoto]) -> [GalleryItem] {
        var result: [GalleryItem] = []
        var burstIndex: [UUID: Int] = [:]
        for shot in shots {
            if let burstID = shot.burstID, let index = burstIndex[burstID] {
                result[index].shots.append(shot)
            } else {
                if let burstID = shot.burstID { burstIndex[burstID] = result.count }
                result.append(GalleryItem(shots: [shot]))
            }
        }
        return result
    }
}
