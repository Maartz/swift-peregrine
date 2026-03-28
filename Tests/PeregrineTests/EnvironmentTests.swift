import Testing
@testable import Peregrine

@Suite("Environment")
struct EnvironmentTests {
    @Test func defaultsToDevWhenUnset() {
        // PEREGRINE_ENV is not set in the test process by default
        // so Peregrine.env should fall back to .dev
        #expect(Peregrine.env == .dev)
    }

    @Test func environmentRawValues() {
        #expect(Environment(rawValue: "dev") == .dev)
        #expect(Environment(rawValue: "test") == .test)
        #expect(Environment(rawValue: "prod") == .prod)
        #expect(Environment(rawValue: "staging") == nil)
        #expect(Environment(rawValue: "") == nil)
    }

    @Test func environmentIsSendable() {
        let env: any Sendable = Environment.dev
        #expect(env is Environment)
    }
}
