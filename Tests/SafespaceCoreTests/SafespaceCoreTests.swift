import CryptoKit
import Foundation
import Testing
@testable import SafespaceCore

// Low iteration counts keep the tests fast; the app uses Vault.defaultIterations.

@Test func encryptDecryptRoundTrip() throws {
    let vault = try Vault.create(password: "correct horse battery staple", iterations: 1_000)
    let entries = [Entry(title: "GitHub", username: "me", password: "s3cr3t!", url: "github.com")]
    let file = try Vault.encrypt(entries, with: vault)

    let (_, decrypted) = try Vault.decrypt(file, password: "correct horse battery staple")
    #expect(decrypted == entries)
}

@Test func ciphertextDoesNotContainPlaintext() throws {
    let vault = try Vault.create(password: "pw", iterations: 1_000)
    let file = try Vault.encrypt([Entry(title: "VerySecretTitle", password: "hunter2hunter2")], with: vault)
    let onDisk = try JSONEncoder().encode(file)
    #expect(String(decoding: onDisk, as: UTF8.self).contains("VerySecretTitle") == false)
    #expect(String(decoding: onDisk, as: UTF8.self).contains("hunter2") == false)
}

@Test func wrongPasswordIsRejected() throws {
    let vault = try Vault.create(password: "right", iterations: 1_000)
    let file = try Vault.encrypt([], with: vault)
    #expect(throws: VaultError.wrongPassword) {
        try Vault.decrypt(file, password: "wrong")
    }
}

@Test func decryptWithStoredKey() throws {
    let vault = try Vault.create(password: "pw", iterations: 1_000)
    let file = try Vault.encrypt([Entry(title: "a")], with: vault)
    #expect(try Vault.decrypt(file, key: vault.key).1.count == 1)

    let other = try Vault.create(password: "pw", iterations: 1_000)
    #expect(throws: VaultError.wrongPassword) {
        try Vault.decrypt(file, key: other.key)
    }
}

@Test func tamperedHeaderIsRejected() throws {
    let vault = try Vault.create(password: "right", iterations: 1_000)
    var file = try Vault.encrypt([], with: vault)
    file.iterations = 999
    #expect(throws: VaultError.self) {
        try Vault.decrypt(file, password: "right")
    }
}

@Test func tamperedCiphertextIsRejected() throws {
    let vault = try Vault.create(password: "right", iterations: 1_000)
    var file = try Vault.encrypt([Entry(title: "x")], with: vault)
    file.ciphertext[file.ciphertext.count / 2] ^= 0xFF
    #expect(throws: VaultError.wrongPassword) {
        try Vault.decrypt(file, password: "right")
    }
}

@Test func eachEncryptionUsesAFreshNonce() throws {
    let vault = try Vault.create(password: "pw", iterations: 1_000)
    let a = try Vault.encrypt([], with: vault)
    let b = try Vault.encrypt([], with: vault)
    #expect(a.ciphertext != b.ciphertext)
}

@Test func storageWritesPrivateFileAndBackup() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let storage = VaultStorage(url: dir.appendingPathComponent("vault.safespace"))
    let vault = try Vault.create(password: "pw", iterations: 1_000)

    try storage.write(Vault.encrypt([], with: vault))
    try storage.write(Vault.encrypt([Entry(title: "a")], with: vault))

    let attributes = try FileManager.default.attributesOfItem(atPath: storage.url.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    #expect(FileManager.default.fileExists(atPath: storage.backupURL.path))
    #expect(try Vault.decrypt(storage.read(), password: "pw").1.count == 1)
}

@Test func groupsRoundTrip() throws {
    let vault = try Vault.create(password: "pw", iterations: 1_000)
    let work = EntryGroup(name: "Work", color: 0x3B7DD8)
    let entries = [Entry(title: "GitHub", groupID: work.id), Entry(title: "Loose")]
    let file = try Vault.encrypt(entries, groups: [work], with: vault)

    let (_, contents) = try Vault.decryptContents(file, password: "pw")
    #expect(contents.groups == [work])
    #expect(contents.entries == entries)
}

@Test func vaultsWithoutGroupsStillOpen() throws {
    // Payload as written before groups existed: no "groups" key, no "groupID" on entries.
    let vault = try Vault.create(password: "pw", iterations: 1_000)
    let legacy = Data(#"{"entries":[{"id":"8C5E3F0A-1B2C-4D5E-8F90-A1B2C3D4E5F6","title":"Old","username":"","password":"x","url":"","notes":"","favorite":false,"createdAt":0,"updatedAt":0}]}"#.utf8)
    var file = try Vault.encrypt([], with: vault)
    let box = try AES.GCM.seal(legacy, using: vault.key, authenticating: file.associatedData)
    file.ciphertext = box.combined!

    let (_, contents) = try Vault.decryptContents(file, password: "pw")
    #expect(contents.groups.isEmpty)
    #expect(contents.entries.map(\.title) == ["Old"])
    #expect(contents.entries[0].groupID == nil)
}

@Test func danglingGroupReferencesAreCleared() throws {
    let vault = try Vault.create(password: "pw", iterations: 1_000)
    let file = try Vault.encrypt([Entry(title: "Orphan", groupID: UUID())], groups: [], with: vault)
    #expect(try Vault.decryptContents(file, password: "pw").1.entries[0].groupID == nil)
}

@Test func suggestedGroupColorAvoidsUsedOnes() {
    let first = EntryGroup(name: "A", color: EntryGroup.palette[0])
    #expect(EntryGroup.suggestedColor(avoiding: []) == EntryGroup.palette[0])
    #expect(EntryGroup.suggestedColor(avoiding: [first]) == EntryGroup.palette[1])
}

@Test func generatorHonoursOptions() {
    for length in [4, 16, 64, 128] {
        let options = PasswordOptions(length: length, uppercase: false, lowercase: true, digits: true, symbols: false)
        let password = PasswordGenerator.generate(options)
        #expect(password.count == length)
        #expect(password.allSatisfy { $0.isLowercase || $0.isNumber })
        #expect(password.contains { $0.isNumber })
        #expect(password.contains { $0.isLowercase })
    }
}

@Test func generatorExcludesAmbiguousCharacters() {
    let options = PasswordOptions(length: 128, excludeAmbiguous: true)
    for _ in 0..<50 {
        #expect(PasswordGenerator.generate(options).allSatisfy { !PasswordGenerator.ambiguous.contains($0) })
    }
}

@Test func generatorUsesCustomSymbolsOnly() {
    let options = PasswordOptions(length: 64, uppercase: false, lowercase: false, digits: false, symbols: true, symbolSet: "#_ #a1")
    let password = PasswordGenerator.generate(options)
    #expect(Set(password).isSubset(of: ["#", "_"]))
}

@Test func generatorReturnsEmptyWhenNothingSelected() {
    let options = PasswordOptions(uppercase: false, lowercase: false, digits: false, symbols: false)
    #expect(PasswordGenerator.generate(options).isEmpty)
    #expect(PasswordGenerator.entropy(of: options) == 0)
}

@Test func passphraseHasRequestedShape() {
    let options = PassphraseOptions(wordCount: 6, separator: ".", capitalize: true, includeNumber: true)
    let phrase = PasswordGenerator.generate(options)
    let words = phrase.split(separator: ".")
    #expect(words.count == 6)
    #expect(words.allSatisfy { $0.first!.isUppercase })
    #expect(phrase.filter { $0.isNumber }.count == 1)
}

@Test func wordListIsLargeAndUnique() {
    #expect(WordList.words.count > 500)
    #expect(Set(WordList.words).count == WordList.words.count)
}

@Test func strengthEstimates() {
    #expect(PasswordStrength(entropy: PasswordStrength.estimateEntropy(of: "password")) == .veryWeak)
    #expect(PasswordStrength(entropy: PasswordStrength.estimateEntropy(of: "aaaaaaaa")) <= .weak)
    #expect(PasswordStrength(entropy: PasswordStrength.estimateEntropy(of: "Rw3!nB8#qT5@zL1&mK7p")) == .veryStrong)
}
