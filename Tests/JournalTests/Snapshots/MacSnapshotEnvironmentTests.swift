#if os(macOS)
    import Testing

    @Suite("Mac snapshot execution policy")
    struct MacSnapshotEnvironmentTests {
        @Test(
            arguments: [
                (nil, nil, false),
                ("false", nil, false),
                ("1", nil, false),
                (nil, "0", false),
                (nil, "true", false),
                (nil, "1", true),
                ("false", "1", true),
                ("true", nil, true),
                ("true", "0", true),
                ("true", "1", true),
            ] as [(String?, String?, Bool)])
        func executionPolicy(ci: String?, local: String?, expected: Bool) {
            var environment: [String: String] = [:]
            environment["CI"] = ci
            environment["SNAPSHOT_MAC_LOCAL"] = local
            #expect(MacSnapshotEnvironment.shouldRun(environment: environment) == expected)
        }
    }
#endif
