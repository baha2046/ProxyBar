import Foundation

public final class RequestActivityTimeline: @unchecked Sendable {
    public let bucketCount: Int
    public let bucketDuration: TimeInterval

    private let lock = NSLock()
    private var buckets: [Int64: Int] = [:]

    public init(bucketCount: Int = 12, bucketDuration: TimeInterval = 60) {
        self.bucketCount = max(1, bucketCount)
        self.bucketDuration = max(1, bucketDuration)
    }

    public var totalCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return buckets.values.reduce(0, +)
    }

    public func record(at date: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }

        let index = bucketIndex(for: date)
        buckets[index, default: 0] += 1
        pruneLocked(endingAt: index)
    }

    public func counts(endingAt date: Date = Date()) -> [Int] {
        lock.lock()
        defer { lock.unlock() }

        let current = bucketIndex(for: date)
        pruneLocked(endingAt: current)
        let first = current - Int64(bucketCount - 1)
        return (0..<bucketCount).map { offset in
            buckets[first + Int64(offset), default: 0]
        }
    }

    public func reset() {
        lock.lock()
        buckets.removeAll()
        lock.unlock()
    }

    private func bucketIndex(for date: Date) -> Int64 {
        Int64(floor(date.timeIntervalSince1970 / bucketDuration))
    }

    private func pruneLocked(endingAt current: Int64) {
        let oldest = current - Int64(bucketCount - 1)
        buckets = buckets.filter { $0.key >= oldest && $0.key <= current }
    }
}
