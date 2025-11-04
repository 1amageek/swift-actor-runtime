import Testing
import Foundation
@testable import ActorRuntime

@Suite("MethodRegistry Tests")
struct MethodRegistryTests {

    @Test("MethodRegistry register and execute")
    func testRegisterAndExecute() async throws {
        let registry = MethodRegistry()

        // Register a method
        registry.register("readTemperature") { args in
            let temperature = 22.5
            return try JSONEncoder().encode(temperature)
        }

        // Execute the method
        let resultData = try await registry.execute("readTemperature", arguments: Data())
        let temperature = try JSONDecoder().decode(Double.self, from: resultData)

        #expect(temperature == 22.5)
    }

    @Test("MethodRegistry execute with arguments")
    func testExecuteWithArguments() async throws {
        let registry = MethodRegistry()

        struct Args: Codable {
            let value: Int
        }

        // Register a method that uses arguments
        registry.register("addTen") { argsData in
            let args = try JSONDecoder().decode(Args.self, from: argsData)
            let result = args.value + 10
            return try JSONEncoder().encode(result)
        }

        // Execute
        let args = Args(value: 5)
        let argsData = try JSONEncoder().encode(args)
        let resultData = try await registry.execute("addTen", arguments: argsData)
        let result = try JSONDecoder().decode(Int.self, from: resultData)

        #expect(result == 15)
    }

    @Test("MethodRegistry method not found")
    func testMethodNotFound() async {
        let registry = MethodRegistry()

        await #expect(throws: RuntimeError.self) {
            try await registry.execute("nonExistent", arguments: Data())
        }
    }

    @Test("MethodRegistry method throws error")
    func testMethodThrowsError() async {
        let registry = MethodRegistry()

        // Register a method that throws
        registry.register("failingMethod") { _ in
            throw RuntimeError.executionFailed("test", underlying: "Intentional error")
        }

        await #expect(throws: RuntimeError.self) {
            try await registry.execute("failingMethod", arguments: Data())
        }
    }

    @Test("MethodRegistry hasMethod")
    func testHasMethod() {
        let registry = MethodRegistry()

        #expect(!registry.hasMethod("readTemperature"))

        registry.register("readTemperature") { _ in Data() }

        #expect(registry.hasMethod("readTemperature"))
    }

    @Test("MethodRegistry unregister")
    func testUnregister() async throws {
        let registry = MethodRegistry()

        registry.register("readTemperature") { _ in Data() }
        #expect(registry.hasMethod("readTemperature"))

        registry.unregister("readTemperature")
        #expect(!registry.hasMethod("readTemperature"))

        // Execute should fail now
        await #expect(throws: RuntimeError.self) {
            try await registry.execute("readTemperature", arguments: Data())
        }
    }

    @Test("MethodRegistry count")
    func testCount() {
        let registry = MethodRegistry()

        #expect(registry.count == 0)

        registry.register("method1") { _ in Data() }
        #expect(registry.count == 1)

        registry.register("method2") { _ in Data() }
        #expect(registry.count == 2)

        registry.unregister("method1")
        #expect(registry.count == 1)
    }

    @Test("MethodRegistry allMethods")
    func testAllMethods() {
        let registry = MethodRegistry()

        registry.register("method1") { _ in Data() }
        registry.register("method2") { _ in Data() }
        registry.register("method3") { _ in Data() }

        let methods = registry.allMethods()
        #expect(methods.count == 3)
        #expect(methods.contains("method1"))
        #expect(methods.contains("method2"))
        #expect(methods.contains("method3"))
    }

    @Test("MethodRegistry clear")
    func testClear() {
        let registry = MethodRegistry()

        registry.register("method1") { _ in Data() }
        registry.register("method2") { _ in Data() }
        #expect(registry.count == 2)

        registry.clear()
        #expect(registry.count == 0)
        #expect(registry.allMethods().isEmpty)
    }

    @Test("MethodRegistry concurrent execution")
    func testConcurrentExecution() async throws {
        let registry = MethodRegistry()

        // Register multiple methods
        for i in 0..<10 {
            registry.register("method\(i)") { _ in
                let value = i * 2
                return try JSONEncoder().encode(value)
            }
        }

        // Execute concurrently
        await withTaskGroup(of: Int?.self) { group in
            for i in 0..<10 {
                group.addTask {
                    do {
                        let resultData = try await registry.execute("method\(i)", arguments: Data())
                        return try JSONDecoder().decode(Int.self, from: resultData)
                    } catch {
                        return nil
                    }
                }
            }

            var results: [Int] = []
            for await result in group {
                if let value = result {
                    results.append(value)
                }
            }

            #expect(results.count == 10)
        }
    }

    @Test("MethodRegistry overwrite method")
    func testOverwriteMethod() async throws {
        let registry = MethodRegistry()

        // Register first version
        registry.register("getValue") { _ in
            try JSONEncoder().encode(1)
        }

        let result1Data = try await registry.execute("getValue", arguments: Data())
        let result1 = try JSONDecoder().decode(Int.self, from: result1Data)
        #expect(result1 == 1)

        // Overwrite with new implementation
        registry.register("getValue") { _ in
            try JSONEncoder().encode(2)
        }

        let result2Data = try await registry.execute("getValue", arguments: Data())
        let result2 = try JSONDecoder().decode(Int.self, from: result2Data)
        #expect(result2 == 2)
    }

    @Test("MethodRegistry async method execution")
    func testAsyncMethodExecution() async throws {
        let registry = MethodRegistry()

        // Register an async method
        registry.register("asyncMethod") { _ in
            // Simulate async work
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            return try JSONEncoder().encode("completed")
        }

        let resultData = try await registry.execute("asyncMethod", arguments: Data())
        let result = try JSONDecoder().decode(String.self, from: resultData)

        #expect(result == "completed")
    }

    @Test("MethodRegistry error wrapping")
    func testErrorWrapping() async {
        let registry = MethodRegistry()

        struct CustomError: Error {}

        // Register method that throws non-RuntimeError
        registry.register("customError") { _ in
            throw CustomError()
        }

        do {
            _ = try await registry.execute("customError", arguments: Data())
            Issue.record("Expected error to be thrown")
        } catch let error as RuntimeError {
            // Should be wrapped in RuntimeError.executionFailed
            if case .executionFailed(let methodName, _) = error {
                #expect(methodName == "customError")
            } else {
                Issue.record("Expected executionFailed error")
            }
        } catch {
            Issue.record("Expected RuntimeError")
        }
    }
}
