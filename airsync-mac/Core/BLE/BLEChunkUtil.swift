import Foundation

struct BLEChunkUtil {
    
    static func splitIntoChunks(payload: String, mtu: Int) -> [Data] {
        guard let data = payload.data(using: .utf8) else { return [] }
        let maxPayloadSize = mtu - BLEConstants.chunkHeaderSize
        
        guard maxPayloadSize > 0 else { return [] }
        
        let totalChunks = Int(ceil(Double(data.count) / Double(maxPayloadSize)))
        var chunks: [Data] = []
        
        for i in 0..<totalChunks {
            let start = i * maxPayloadSize
            let end = min(start + maxPayloadSize, data.count)
            let chunkData = data.subdata(in: start..<end)
            
            var chunk = Data()
            let index = UInt16(i).bigEndian
            let total = UInt16(totalChunks).bigEndian
            
            withUnsafeBytes(of: index) { chunk.append(contentsOf: $0) }
            withUnsafeBytes(of: total) { chunk.append(contentsOf: $0) }
            
            chunk.append(chunkData)
            chunks.append(chunk)
        }
        
        return chunks
    }
    
    static func reassemble(chunks: [Int: Data]) -> String {
        let sortedIndices = chunks.keys.sorted()
        var combinedData = Data()
        
        for index in sortedIndices {
            if let chunkData = chunks[index] {
                combinedData.append(chunkData)
            }
        }
        
        return String(data: combinedData, encoding: .utf8) ?? ""
    }
    
    static func parseHeader(from data: Data) -> (current: Int, total: Int)? {
        guard data.count >= BLEConstants.chunkHeaderSize else { return nil }
        
        let current = data.subdata(in: 0..<2).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        let total = data.subdata(in: 2..<4).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        
        return (Int(current), Int(total))
    }
    
    static func getPayload(from data: Data) -> Data {
        guard data.count > BLEConstants.chunkHeaderSize else { return Data() }
        return data.subdata(in: BLEConstants.chunkHeaderSize..<data.count)
    }
}
