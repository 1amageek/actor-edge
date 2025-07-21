import Testing

// Define tags using Swift Testing's tag system
extension Tag {
    @Tag static var core: Self
    @Tag static var transport: Self
    @Tag static var integration: Self
    @Tag static var performance: Self
    @Tag static var regression: Self
    @Tag static var serialization: Self
    @Tag static var invocation: Self
    @Tag static var server: Self
    @Tag static var client: Self
    @Tag static var sample: Self
    @Tag static var unit: Self
    @Tag static var errorHandling: Self
}