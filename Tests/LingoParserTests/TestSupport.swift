import Foundation

private final class ResultBox<T>: @unchecked Sendable {
    var result: Result<T, Error>?
}

/// Runs `body` on a dedicated thread with a large stack.
///
/// The recursive-descent stringifier (`AST.toLingoSource`) recurses in
/// proportion to expression nesting. Swift Testing executes test bodies on
/// worker threads with smaller stacks than XCTest's main thread, so deeply
/// nested expressions (e.g. long `&` concatenation chains) can overflow the
/// default stack. Hosting that work on a 64 MB stack keeps the tests robust.
func withLargeStack<T>(_ body: @escaping @Sendable () throws -> T) throws -> T {
    let box = ResultBox<T>()
    let semaphore = DispatchSemaphore(value: 0)
    let thread = Thread {
        box.result = Result(catching: body)
        semaphore.signal()
    }
    thread.stackSize = 64 * 1024 * 1024
    thread.start()
    semaphore.wait()
    return try box.result!.get()
}
