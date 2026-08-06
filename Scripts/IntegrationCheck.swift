import Foundation

@main enum IntegrationCheck {
    static func main() async throws {
        let binary = try CodexBinaryLocator().locate()
        let client = CodexAppServerClient(transport: ProcessAppServerTransport(executableURL: binary.url))
        do {
            try await client.connect()
            _ = try await client.requestAccount()
            let result = try await client.requestRateLimits()
            _ = try await client.requestTokenUsage()
            let snapshot = QuotaMapper.snapshot(from: result)
            guard snapshot.weekly != nil else { throw CodexMeterError.invalidResponse("未识别到 7 天额度") }
            print("项目客户端握手、账户读取、7 天额度与 Token 历史读取：PASS")
            await client.disconnect()
        } catch {
            await client.disconnect()
            throw error
        }
    }
}
