import Foundation

enum Base58 {
    private static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
    private static let decode: [Int: Int] = {
        var map = [Int: Int]()
        for (i, c) in alphabet.enumerated() { map[Int(c.asciiValue!)] = i }
        return map
    }()

    static func decodeToBytes(_ string: String) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: 64)
        var length = 0
        for char in string {
            guard let ascii = char.asciiValue, let value = decode[Int(ascii)] else { return nil }
            var carry = value
            for i in 0..<length {
                carry += 58 * Int(bytes[i])
                bytes[i] = UInt8(carry & 0xFF)
                carry >>= 8
            }
            while carry > 0 {
                bytes[length] = UInt8(carry & 0xFF)
                length += 1
                carry >>= 8
            }
        }
        // Leading zeros
        for char in string {
            guard char == "1" else { break }
            bytes[length] = 0
            length += 1
        }
        let result = Array(bytes[0..<length].reversed())
        return result
    }

    static func encode(_ bytes: [UInt8]) -> String {
        var digits = [Int]()
        for byte in bytes {
            var carry = Int(byte)
            for i in 0..<digits.count {
                carry += 256 * digits[i]
                digits[i] = carry % 58
                carry /= 58
            }
            while carry > 0 { digits.append(carry % 58); carry /= 58 }
        }
        var result = ""
        for byte in bytes { guard byte == 0 else { break }; result.append("1") }
        for digit in digits.reversed() { result.append(alphabet[digit]) }
        return result
    }
}
