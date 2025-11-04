# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.1.0]: https://github.com/1amageek/swift-actor-runtime/releases/tag/0.1.0
