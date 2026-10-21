// Checks that an update file's EdDSA signature matches the public key built into the app, so a release never
// ships an update the installed copies would refuse (for example, after the secret was replaced by mistake).
//
// Usage: swift scripts/verify-update-signature.swift <Presenter.app> <file> <base64 signature>
import CryptoKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    print("Usage: verify-update-signature.swift <Presenter.app> <file> <base64 signature>")
    exit(2)
}
let info = NSDictionary(contentsOf: URL(fileURLWithPath: arguments[1]).appendingPathComponent("Contents/Info.plist"))
guard let publicKeyText = info?["SUPublicEDKey"] as? String,
      let publicKeyData = Data(base64Encoded: publicKeyText),
      let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData) else {
    print("error: the app has no valid SUPublicEDKey")
    exit(1)
}
guard let signature = Data(base64Encoded: arguments[3]),
      let file = FileManager.default.contents(atPath: arguments[2]) else {
    print("error: can't read the file or the signature")
    exit(1)
}
guard publicKey.isValidSignature(signature, for: file) else {
    print("error: the signature doesn't match the app's public key")
    exit(1)
}
print("The signature matches the app's public key.")
