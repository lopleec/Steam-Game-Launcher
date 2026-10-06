import Foundation
import CommonCrypto
import Security

struct HiddenPasswordRecord: Codable, Equatable, Sendable {
    var salt: Data
    var digest: Data
    var iterations: UInt32
}

enum HiddenPassword {
    static func create(_ password: String) throws -> HiddenPasswordRecord {
        var salt = Data(count: 32)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!) }
        guard status == errSecSuccess else { throw CocoaError(.coderInvalidValue) }
        let rounds: UInt32 = 180_000
        return HiddenPasswordRecord(salt: salt, digest: try derive(password, salt: salt, iterations: rounds), iterations: rounds)
    }
    static func verify(_ password: String, record: HiddenPasswordRecord) -> Bool {
        guard record.salt.count == 32, record.digest.count == 32, (100_000...1_000_000).contains(record.iterations),
              let candidate = try? derive(password, salt: record.salt, iterations: record.iterations) else { return false }
        return zip(candidate, record.digest).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
    private static func derive(_ password: String, salt: Data, iterations: UInt32) throws -> Data {
        let bytes = Array(password.utf8)
        var output = Data(count: 32)
        let status = password.withCString { passwordPointer in
            salt.withUnsafeBytes { saltBytes in
                output.withUnsafeMutableBytes { outputBytes in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordPointer, bytes.count,
                        saltBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations,
                        outputBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), outputBytes.count)
                }
            }
        }
        guard status == kCCSuccess else { throw CocoaError(.coderInvalidValue) }
        return output
    }
}
