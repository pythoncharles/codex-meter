import Foundation

struct JSONLStreamDecoder {
    private var buffer = Data()
    let maximumLineBytes: Int
    init(maximumLineBytes: Int = 4 * 1024 * 1024) { self.maximumLineBytes = maximumLineBytes }

    mutating func append(_ data: Data) -> [Data] {
        buffer.append(data)
        var messages = [Data]()
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            guard line.count <= maximumLineBytes, !line.allSatisfy({ $0 == 9 || $0 == 10 || $0 == 13 || $0 == 32 }) else { continue }
            messages.append(Data(line))
        }
        if buffer.count > maximumLineBytes { buffer.removeAll() }
        return messages
    }
}
