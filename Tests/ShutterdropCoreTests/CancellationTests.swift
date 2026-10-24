import Foundation
import Testing
@testable import ShutterdropCore

@Test func cancellingTheCameraWaitStopsQuickly() async throws {
    let started = ContinuousClock.now
    let wait = Task { try await CardImporter.waitForCamera(seconds: 30) }
    try await Task.sleep(for: .milliseconds(500))
    wait.cancel()
    await #expect(throws: CancellationError.self) { try await wait.value }
    #expect(ContinuousClock.now - started < .seconds(3))
}
