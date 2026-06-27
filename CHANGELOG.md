# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Prefer `FoundationEssentials` where the toolchain exposes it, with a
  `Foundation` fallback for host SDKs that do not make `FoundationEssentials`
  directly importable.
- Guard `Distributed`-dependent codec and registry APIs with
  `canImport(Distributed)` so the source models compiler capabilities rather
  than platform-named source variants.

### Documentation
- Added a platform support matrix: native Swift and standard WASM are supported
  and tested; Embedded Swift WASM is explicitly unsupported with the current
  Swift 6.3.1 SDK because `Codable`, `Foundation`/`FoundationEssentials`, and
  `Distributed` are unavailable there.

## [0.5.0] - 2026-05-30

### Fixed
- **Generic substitution type resolution**: `CodableInvocationEncoder.recordGenericSubstitution`
  now records the runtime-mangled type name via `_mangledTypeName` (falling back to
  `_typeName`) instead of `String(reflecting:)`. The previous representation only
  round-tripped for trivial top-level types (e.g. `Int`, `String`); generic, optional,
  collection, and user-defined types produced names that `_typeByName` could not resolve,
  causing `decodeGenericSubstitutions()` to throw on the receiving side. This matches
  swift-distributed-actors' `ClusterInvocationEncoder` and makes generic distributed
  methods and generic distributed actors work across a real transport.

### Changed
- Raised the minimum toolchain to **Swift 6.3** (`swift-tools-version: 6.3`).
- **Breaking (wire/API)**: `InvocationEnvelope.arguments` is now `[Data]` (one encoded
  blob per parameter) instead of a single `Data` holding a JSON-encoded `[Data]`. This
  removes a redundant encode/decode and the extra base64 expansion that occurred when a
  transport serialized the envelope. Transports that construct or inspect `arguments`
  must pass a list of blobs. Mirrors how swift-distributed-actors carries arguments.
- `CodableInvocationEncoder`/`CodableInvocationDecoder` now reuse a single
  `JSONEncoder`/`JSONDecoder` per instance instead of allocating one per argument.

### Added
- Regression tests covering the full encoder → envelope → decoder generic-substitution
  contract for primitive, composite, and user-defined types, multi-substitution ordering,
  and unresolvable-name error reporting.

## [0.2.0] - 2025-01-05

### Added
- `ResponseEnvelope` convenience methods for fluent API:
  - `withExecutionTime(_:)` - Add execution time to response metadata
  - `withHeaders(_:)` - Merge additional headers into response metadata
  - `withHeader(_:value:)` - Add a single header to response metadata
  - Support for method chaining for composing metadata updates
- Comprehensive test coverage for new convenience methods (6 new tests)
- Transport Implementation Guide (`Documentation/TRANSPORT_IMPLEMENTATION.md`):
  - Pattern 1: Direct Response for simple request-response transports
  - Pattern 2: Captured Response for complex protocols (gRPC, ActorEdge)
  - Complete HTTP transport example
  - Best practices for error handling, tracing, and execution time tracking
- Troubleshooting Guide (`Documentation/TROUBLESHOOTING.md`):
  - Common serialization errors and solutions
  - Actor lookup debugging techniques
  - Generic type error resolution
  - Transport error handling patterns
  - Debugging tips and techniques

### Improved
- Enhanced error messages in `CodableInvocationDecoder`:
  - Now includes method name in all error messages
  - Shows expected type on decoding failures
  - Provides argument index for easier debugging
  - Example: "Failed to decode argument at index 0 as Int for method 'readTemperature': ..."
- Added 3 new tests for improved error message validation

### Documentation
- Added comprehensive Transport Implementation Guide with real-world patterns
- Added Troubleshooting Guide covering common issues and solutions
- Enhanced inline documentation for convenience methods

## [0.1.0] - 2025-01-04

### Added
- Initial release of swift-actor-runtime
- `InvocationEnvelope` and `ResponseEnvelope` for transport-agnostic RPC
- `ActorRegistry` for thread-safe actor instance tracking
- `CodableInvocationEncoder`/`Decoder` for Codable argument encoding/decoding
- `CodableResultHandler` for result handling
- **Generic method support**: Full support for distributed methods with generic type parameters
- **Generic actor support**: Support for distributed actors with generic constraints
- `RuntimeError` with standard, serializable error types
- `DistributedTransport` protocol for transport implementations
- Full Swift 6 concurrency support with `Sendable` conformance
- Thread-safe implementation using `Synchronization.Mutex`
- Integration with Swift's built-in `executeDistributedTarget` for method dispatch
- All envelopes fully support Swift's `Codable` protocol
- Complete working example: InMemoryActorSystem
- Comprehensive test suite (55 tests including generic actor tests)
- Complete documentation (README, DESIGN, CLAUDE, CODEC)
- Memory management guidance for strong reference lifecycle
- Recursive lock prevention in ActorRegistry

### Infrastructure
- GitHub Actions CI/CD for macOS and Linux
- MIT License

[0.5.0]: https://github.com/1amageek/swift-actor-runtime/releases/tag/0.5.0
[0.2.0]: https://github.com/1amageek/swift-actor-runtime/releases/tag/0.2.0
[0.1.0]: https://github.com/1amageek/swift-actor-runtime/releases/tag/0.1.0
