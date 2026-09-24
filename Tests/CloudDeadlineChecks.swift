import Foundation

@main struct CloudDeadlineChecks {
    @MainActor static func main() async throws {
        let value = try await withCloudDeadline(seconds: 1) { 42 }
        precondition(value == 42)
        enum TestFailure: Error { case expected }
        do {
            let _: Int = try await withCloudDeadline(seconds: 1) { throw TestFailure.expected }
            fatalError("Error should propagate")
        } catch TestFailure.expected { }
        let start = Date()
        do {
            let _: Int = try await withCloudDeadline(seconds: 0.03) {
                // Deliberately ignores cancellation, like a stalled callback API.
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { continuation.resume(returning: 7) }
                }
            }
            fatalError("Stalled work should time out")
        } catch CloudTimeout.expired { }
        precondition(Date().timeIntervalSince(start) < 0.2)
        let task = Task { @MainActor in
            try await withCloudDeadline(seconds: 1) {
                try await Task.sleep(nanoseconds: 500_000_000)
                return 1
            }
        }
        task.cancel()
        do { _ = try await task.value; fatalError("Cancelled work should stop") }
        catch is CancellationError { }
        let retry = try await withCloudDeadline(seconds: 1) { 99 }
        precondition(retry == 99)
        // Let the timed-out callback finish: it must not resume its caller twice.
        try await Task.sleep(nanoseconds: 400_000_000)
        print("PASS: deadline success, failure, stalled callback, cancellation, retry, late completion")
    }
}
