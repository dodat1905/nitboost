import CryptoKit
import Foundation

final class Enclosures: NSObject, XMLParserDelegate {
    var values: [[String: String]] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if elementName == "enclosure" { values.append(attributes) }
    }
}

let archive = URL(fileURLWithPath: CommandLine.arguments[1])
let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: "Info.plist")), format: nil) as! [String: Any]
let parser = XMLParser(contentsOf: URL(fileURLWithPath: "appcast.xml"))!
let enclosures = Enclosures()
parser.delegate = enclosures
precondition(parser.parse(), "The appcast must parse")
let enclosure = enclosures.values.first { URL(string: $0["url"] ?? "")?.lastPathComponent == archive.lastPathComponent }!
let data = try Data(contentsOf: archive)
precondition(Int(enclosure["length"]!) == data.count, "The archive length must match the appcast")
let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: info["SUPublicEDKey"] as! String)!)
let signature = Data(base64Encoded: enclosure["sparkle:edSignature"]!)!
precondition(key.isValidSignature(signature, for: data), "The app's public key must verify the archive")
var changed = data
changed[changed.startIndex] ^= 1
precondition(!key.isValidSignature(signature, for: changed), "A changed archive must fail signature verification")
print("PASS: the app's public key accepts the release archive and rejects a changed archive")
