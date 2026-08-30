import XCTest
@testable import TripTrail

final class MediaPresentationTests: XCTestCase {
    func testFootprintMediaLimitHasAtMostSixSlots() {
        XCTAssertEqual(FootprintMediaPolicy.remainingSlots(existingCount: 0), 6)
        XCTAssertEqual(FootprintMediaPolicy.remainingSlots(existingCount: 4, pendingCount: 1), 1)
        XCTAssertEqual(FootprintMediaPolicy.remainingSlots(existingCount: 6), 0)
        XCTAssertEqual(FootprintMediaPolicy.remainingSlots(existingCount: 12), 0)
    }

    func testMediaPreviewKeepsImagesAndVideosInOriginalOrder() {
        let request = AssetMediaPreviewRequest(
            items: [
                AssetMediaPreviewItem(identifier: "first", kind: .image),
                AssetMediaPreviewItem(identifier: "second", kind: .video),
                AssetMediaPreviewItem(identifier: "first", kind: .image)
            ],
            initialIdentifier: "second"
        )
        XCTAssertEqual(request.items.map(\.identifier), ["first", "second"])
        XCTAssertEqual(request.items.map(\.kind), [.image, .video])
        XCTAssertEqual(request.initialIdentifier, "second")
    }

    func testMediaPagerAlwaysResolvesToACompletePage() {
        XCTAssertEqual(
            MediaPagingPolicy.targetIndex(
                currentIndex: 2,
                itemCount: 5,
                translation: -30,
                predictedTranslation: -35,
                pageWidth: 393
            ),
            2
        )
        XCTAssertEqual(
            MediaPagingPolicy.targetIndex(
                currentIndex: 2,
                itemCount: 5,
                translation: -95,
                predictedTranslation: -130,
                pageWidth: 393
            ),
            3
        )
        XCTAssertEqual(
            MediaPagingPolicy.targetIndex(
                currentIndex: 0,
                itemCount: 5,
                translation: 160,
                predictedTranslation: 190,
                pageWidth: 393
            ),
            0
        )
    }
}
