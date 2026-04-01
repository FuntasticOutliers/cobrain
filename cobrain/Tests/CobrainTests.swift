import Testing
@testable import cobrain

@Test func fragmentDayFormat() {
    let day = Fragment.makeDay()
    // Should be "YYYY-MM-DD" format
    #expect(day.count == 10)
    #expect(day.contains("-"))
}

@Test func deduplicationDetectsDuplicates() {
    let dedup = DeduplicationService.shared
    let content = "Hello world this is a test"

    let first = dedup.check(content: content, bundleID: "com.test", windowTitle: "Test")
    #expect(first == .newFragment)

    let second = dedup.check(content: content, bundleID: "com.test", windowTitle: "Test")
    #expect(second == .duplicate)
}

@Test func normalizationWorks() {
    let input = "  Hello   World  \n  Test  "
    let normalized = DeduplicationService.normalize(input)
    #expect(normalized == "hello world test")
}
