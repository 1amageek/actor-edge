# Repository Guidelines

## Project Structure & Module Organization
ActorEdge follows Swift Package conventions. Core libraries live in `Sources/ActorEdge`, `Sources/ActorEdgeCore`, `Sources/ActorEdgeServer`, and `Sources/ActorEdgeClient`. Shared integration tests reside in `Tests/ActorEdgeTests`, while sample CLI demos live under `Samples/Sources` with separate targets for `SampleChatServer`, `SampleChatClient`, and shared API code. Supplemental architecture notes and diagrams are kept in `docs/` and `Documentation/`; keep new design write-ups alongside existing topics.

## Build, Test, and Development Commands
Use `swift build` for a full debug build of all modules. Run `swift test` to execute the XCTest suites in `Tests/ActorEdgeTests`. When working with the sample apps, invoke `swift run --package-path Samples SampleChatServer` (or `SampleChatClient`) to verify end-to-end flows. If the build cache misbehaves, reset with `swift package clean && swift package resolve`.

## Coding Style & Naming Conventions
Follow standard Swift API Design Guidelines: four-space indentation, braces on the same line, and descriptive camelCase for methods and variables. Prefer `PascalCase` types and acronyms with leading capitals (e.g. `TLSConfiguration`). Keep macros (`@Resolvable`, `@ActorBuilder`) near the declarations they decorate. Organize extensions by capability in separate `// MARK:` blocks, mirroring how existing files segment transport, envelope, and server concerns.

## Testing Guidelines
Tests leverage XCTest; group related behaviors into `ActorEdgeTests` subclasses and give test methods descriptive `testFeatureExpectation` names. Favor async tests that mirror distributed actor usage and use the in-memory transports already provided in fixtures. Reproduce regressions before fixing them, and cover new surface area with targeted tests. Run `swift test --filter ActorEdgeTests/testName` to iterate quickly when diagnosing a single scenario.

## Commit & Pull Request Guidelines
Commit history shows concise, imperative subject lines in sentence case (e.g., “Add JSON serialization support for ActorEdge”), typically under 72 characters. Keep one focused change per commit and mention affected modules in the body when context is needed. Pull requests should summarize the problem, list notable changes, link related issues, and include screenshots or terminal logs for developer tooling updates. Before submission, re-run `swift build` and `swift test`, and note any non-default commands needed for reviewers.

## Samples & Local Demos
Use the `Samples` workspace to validate protocol flows. After adjusting shared APIs, rebuild the sample targets and ensure the server and client still interoperate over gRPC using the default `localhost:9000` endpoint. Document any manual setup (TLS certificates, ports) inside `Samples/README.md` when you introduce it, so future contributors can re-create the demo quickly.
