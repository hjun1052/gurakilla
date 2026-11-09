// Release signing key for in-app updates (Ed25519, CryptoKit).
//
//   swift scripts/update-key.swift genkey        create the key, store it in the login Keychain, print the public key
//   swift scripts/update-key.swift pubkey        print the public key (goes into Updater.publicKey)
//   swift scripts/update-key.swift sign <file>   write <file>.sig (base64 signature of the file's bytes)
//
// The private key never leaves the Keychain item "gurakilla-update-key". Back it up: without it,
// installed copies can't verify new releases and fall back to opening the release page.
import CryptoKit
import Foundation

let service = "gurakilla-update-key"

func security(_ args: [String]) -> (Int32, String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    p.arguments = args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    try! p.run()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
}

func loadKey() -> Curve25519.Signing.PrivateKey {
    let (status, b64) = security(["find-generic-password", "-s", service, "-w"])
    guard status == 0, let raw = Data(base64Encoded: b64),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
        FileHandle.standardError.write(Data("No signing key in Keychain. Run: swift scripts/update-key.swift genkey\n".utf8))
        exit(1)
    }
    return key
}

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "genkey":
    if security(["find-generic-password", "-s", service]).0 == 0 {
        FileHandle.standardError.write(Data("Key already exists; refusing to overwrite.\n".utf8))
        exit(1)
    }
    let key = Curve25519.Signing.PrivateKey()
    let (status, _) = security(["add-generic-password", "-s", service, "-a", "release",
                                "-w", key.rawRepresentation.base64EncodedString()])
    guard status == 0 else { FileHandle.standardError.write(Data("Keychain write failed\n".utf8)); exit(1) }
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "pubkey":
    print(loadKey().publicKey.rawRepresentation.base64EncodedString())
case "sign":
    guard let path = args.dropFirst().first else { print("usage: sign <file>"); exit(2) }
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let sig = try loadKey().signature(for: data)
    try Data(sig.base64EncodedString().utf8).write(to: URL(fileURLWithPath: path + ".sig"))
    print(path + ".sig")
default:
    print("usage: update-key.swift genkey | pubkey | sign <file>")
    exit(2)
}
