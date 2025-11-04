import Testing
import Foundation
import Distributed
@testable import ActorRuntime

// Simplified tests for ActorRegistry without using actual distributed actors
@Suite("ActorRegistry Simple Tests")
struct ActorRegistrySimpleTests {

    // Mock object that conforms to DistributedActor protocol minimally
    class MockDistributedActorStub: @unchecked Sendable {
        let name: String

        init(name: String) {
            self.name = name
        }
    }

    @Test("ActorRegistry basic operations")
    func testBasicOperations() {
        let registry = ActorRegistry()

        #expect(registry.count == 0)
        #expect(registry.allActorIDs().isEmpty)
    }

    @Test("ActorRegistry count tracking")
    func testCountTracking() {
        let registry = ActorRegistry()

        #expect(registry.count == 0)

        // Note: We can't actually register without a real DistributedActor
        // But we can test the count stays consistent
        #expect(registry.count == 0)

        registry.clear()
        #expect(registry.count == 0)
    }

    @Test("ActorRegistry find returns nil for non-existent")
    func testFindNonExistent() {
        let registry = ActorRegistry()

        let found = registry.find(id: "non-existent")
        #expect(found == nil)
    }

    @Test("ActorRegistry allActorIDs empty initially")
    func testAllActorIDsEmpty() {
        let registry = ActorRegistry()

        let ids = registry.allActorIDs()
        #expect(ids.isEmpty)
    }

    @Test("ActorRegistry clear on empty registry")
    func testClearEmpty() {
        let registry = ActorRegistry()

        registry.clear()
        #expect(registry.count == 0)
    }

    @Test("ActorRegistry unregister non-existent is no-op")
    func testUnregisterNonExistent() {
        let registry = ActorRegistry()

        // Should not crash
        registry.unregister(id: "non-existent")
        #expect(registry.count == 0)
    }

    @Test("ActorRegistry thread safety")
    func testThreadSafety() async {
        let registry = ActorRegistry()

        // Perform concurrent reads (should not crash)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    _ = registry.find(id: "test")
                    _ = registry.count
                    _ = registry.allActorIDs()
                }
            }
        }

        #expect(registry.count == 0)
    }

    @Test("ActorRegistry multiple clears")
    func testMultipleCears() {
        let registry = ActorRegistry()

        registry.clear()
        registry.clear()
        registry.clear()

        #expect(registry.count == 0)
    }

    @Test("ActorRegistry ID formats")
    func testVariousIDFormats() {
        let registry = ActorRegistry()

        // Test with various ID formats
        let ids = [
            "simple-id",
            "UUID:\(UUID().uuidString)",
            "with/slash",
            "with spaces",
            "😀emoji",
            "",
            "123456789"
        ]

        for id in ids {
            let found = registry.find(id: id)
            #expect(found == nil)
        }
    }
}
