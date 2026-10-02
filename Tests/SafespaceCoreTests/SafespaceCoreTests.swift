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
    let storage = VaultStorage(url: dir.appendingPathComponent("vault.dat"))
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

/// Written by the Windows app (windows/src/core.js). Both apps must read each other's vaults.
private let windowsVaultFixture = #"""
{
  "ciphertext": "5XZcgslGm+KiHZ0BqhDKrZxk2KQel9y/uzqN4KSeg2YUB5knQswYynJZ6FJx0lCUWVFNJTB8yiwYC2lpTcwNmN/PiZUB2jr+at+QS35jajZeeq56iJi99+43LmPY5SojNSvugWogLP7awitCPjTUz3hWEWbXwIW57CVAmuFikY7+uZhtevOJBjaM1fE5XGUpetsKxIbBan0W0LAWCE2YGLMtikWX/420tSNro4TS1ZXpPUqUz/K1XggHNxNoAAuhULWPoEKq5jflVNsQx9HIoIZCs2wi26lcyQyIASHlK0WPXvD4p8HJP3QvZ+8/h8rpxaqc4h4upzHQSPcY7F68e8t7+CC32ETJtyy01l00rmVpYo2PbF8Aw0eToKc4W0N/NAdDFq0EPIPMajB9duJckzlwaf3bVA6gClxosaa6bqw8wLXbrrnEKZq/F1eC4x9lvKOWPmxyu9fsJsNzdHlu0/gO5Z7IFwVvA/CczUD0VaW8vS5QHFLUF+s7Hxb3XJpFOdeSs4aoTd0SL7KmLl3IUMDBNUO2dgGI/yc9zSkZa4/nU/y6CHnGhqGTPM16h/7/yK2+Z+V3omO0sC71jrfu0H+Trhv+0dIdi7mpP9IpmGNLUxOkwbgXQ/+Yi04tI2H51aJFK4RrUlk6jdNATZfttDzdQWq4Fz1o5FLoFuujOQ8pej5ybbgMScWDeKOgY1MAOD8XFFxNjFMxEKYNsUH/dELBsl+wTpYQa14=",
  "iterations": 1000,
  "kdf": "PBKDF2-HMAC-SHA256",
  "salt": "burgEdwx1IVcsbj6LzjMsuyF0IE3oXp2YnhTVZ+zVXg=",
  "version": 1
}
"""#

@Test func opensVaultWrittenByWindowsApp() throws {
    let file = try JSONDecoder().decode(VaultFile.self, from: Data(windowsVaultFixture.utf8))
    let (_, contents) = try Vault.decryptContents(file, password: "windows-fixture")
    #expect(contents.groups.map(\.name) == ["Work"])
    #expect(contents.groups.first?.color == 0x3B7DD8)
    #expect(contents.entries.count == 2)
    let github = try #require(contents.entries.first)
    #expect(github.title == "GitHub")
    #expect(github.password == "tmfEzEgKeHwpBD9BUJff")
    #expect(github.notes == "Ünïcode ✓")
    #expect(github.favorite)
    #expect(github.groupID == contents.groups.first?.id)
    #expect(github.createdAt == Date(timeIntervalSinceReferenceDate: 781_000_000.5))
    #expect(contents.entries[1].groupID == nil)
}

@Test func defaultVaultIsADatFile() {
    #expect(VaultStorage.default.url.lastPathComponent == "vault.dat")
}

@Test func legacyVaultIsRenamedToDat() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let vault = try Vault.create(password: "pw", iterations: 1_000)
    let legacy = VaultStorage(url: dir.appendingPathComponent(VaultStorage.legacyFileName))
    try legacy.write(Vault.encrypt([Entry(title: "old")], with: vault))
    try legacy.write(Vault.encrypt([Entry(title: "old")], with: vault)) // leaves a .bak

    let storage = VaultStorage(url: dir.appendingPathComponent("vault.dat"))
    try storage.migrateLegacyFile()
    #expect(storage.exists)
    #expect(!legacy.exists)
    #expect(FileManager.default.fileExists(atPath: storage.backupURL.path))
    #expect(try Vault.decrypt(storage.read(), password: "pw").1.map(\.title) == ["old"])

    // Never overwrites a vault that is already there.
    try legacy.write(Vault.encrypt([], with: vault))
    try storage.migrateLegacyFile()
    #expect(legacy.exists)
    #expect(try Vault.decrypt(storage.read(), password: "pw").1.count == 1)
}

@Test func adoptCopiesAVaultFileButNeverReplacesOne() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let vault = try Vault.create(password: "pw", iterations: 1_000)
    let source = VaultStorage(url: dir.appendingPathComponent("backup/old.safespace"))
    try source.write(Vault.encrypt([Entry(title: "kept")], with: vault))

    let storage = VaultStorage(url: dir.appendingPathComponent("Safespace/vault.dat"))
    try storage.adopt(source.url)
    #expect(try Vault.decrypt(storage.read(), password: "pw").1.map(\.title) == ["kept"])
    #expect(throws: VaultError.vaultExists) { try storage.adopt(source.url) }

    let junk = dir.appendingPathComponent("notes.txt")
    try Data("hello".utf8).write(to: junk)
    #expect(throws: VaultError.corruptFile) { try VaultStorage(url: dir.appendingPathComponent("other.dat")).adopt(junk) }
}

@Test func importMergesWithoutLosingAnything() {
    let work = EntryGroup(name: "Work", color: 0x3B7DD8)
    let importedWork = EntryGroup(name: " work ", color: 0xD94B3D)
    let banking = EntryGroup(name: "Banking", color: 0x0B8F57)
    let shared = Entry(title: "GitHub", password: "a", updatedAt: Date(timeIntervalSince1970: 100))
    var newerShared = shared
    newerShared.password = "b"
    newerShared.updatedAt = Date(timeIntervalSince1970: 200)
    let current = VaultContents(entries: [shared, Entry(title: "Mail", username: "me", password: "x")], groups: [work])
    let imported = VaultContents(
        entries: [
            newerShared,
            Entry(title: "Mail", username: "me", password: "x"),  // same login, different id
            Entry(title: "Bank", password: "y", groupID: banking.id),
            Entry(title: "Jira", password: "z", groupID: importedWork.id),
        ],
        groups: [importedWork, banking]
    )

    let (merged, summary) = current.merging(imported)
    #expect(summary == ImportSummary(added: 2, updated: 1, skipped: 1, groupsAdded: 1))
    #expect(summary.message == "Imported 3 logins · 1 new group · 1 already here")
    #expect(merged.groups.map(\.name) == ["Work", "Banking"])
    #expect(merged.entries.count == 4)
    #expect(merged.entries.first { $0.id == shared.id }?.password == "b")
    #expect(merged.entries.first { $0.title == "Jira" }?.groupID == work.id)
    #expect(merged.entries.first { $0.title == "Bank" }?.groupID == banking.id)

    // Importing the same file again changes nothing.
    let (again, second) = merged.merging(imported)
    #expect(again == merged)
    #expect(second.added == 0 && second.updated == 0)
}

// MARK: - Original SafeSpace (C++ vault.dat)

/// Writes a vault the way the original app's `Vault::save` does.
private func classicVaultData(_ records: [ClassicVault.Record], password: String, iterations: UInt32 = 1_000) throws -> Data {
    func u32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    func i64(_ v: Int64) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    func str(_ s: String) -> Data { u32(UInt32(s.utf8.count)) + Data(s.utf8) }

    var plain = u32(UInt32(records.count)) + u32(UInt32(records.count + 1))
    for (index, r) in records.enumerated() {
        plain += u32(UInt32(index + 1))
        plain += str(r.service) + str(r.username) + str(r.password) + str(r.category) + str(r.notes)
        plain += i64(Int64(r.created.timeIntervalSince1970)) + i64(Int64(r.updated.timeIntervalSince1970))
    }
    let salt = Vault.randomData(count: 16)
    let key = try Vault.deriveKey(password: password, salt: salt, iterations: iterations)
    let box = try AES.GCM.seal(plain, using: key)
    return Data("SAFESPC\0".utf8) + u32(1) + u32(iterations) + salt + Data(box.nonce) + box.tag
        + u32(UInt32(box.ciphertext.count)) + box.ciphertext
}

@Test func classicVaultDecrypts() throws {
    let records = [
        ClassicVault.Record(service: "GitHub", username: "me", password: "s3cr3t!", category: "Work", notes: "2FA on",
                            created: Date(timeIntervalSince1970: 1_700_000_000), updated: Date(timeIntervalSince1970: 1_700_000_500)),
        ClassicVault.Record(service: "Bänk", username: "ü", password: "pässwörd", category: "",
                            created: Date(timeIntervalSince1970: 1_600_000_000), updated: Date(timeIntervalSince1970: 1_600_000_000)),
    ]
    let data = try classicVaultData(records, password: "hunter2 ✓")
    #expect(ClassicVault.isClassic(data))
    #expect(try ClassicVault.decrypt(data, password: "hunter2 ✓") == records)
}

@Test func classicVaultWrongPasswordIsRejected() throws {
    let data = try classicVaultData([ClassicVault.Record(service: "a")], password: "right")
    #expect(throws: VaultError.wrongPassword) {
        try ClassicVault.decrypt(data, password: "wrong")
    }
}

@Test func classicVaultTruncatedIsCorrupt() throws {
    let data = try classicVaultData([ClassicVault.Record(service: "a")], password: "pw")
    #expect(throws: VaultError.corruptFile) {
        try ClassicVault.decrypt(data.dropLast(3), password: "pw")
    }
    #expect(throws: VaultError.corruptFile) {
        try ClassicVault.validate(Data("not a vault".utf8))
    }
}

@Test func classicCategoriesBecomeGroups() throws {
    let records = [
        ClassicVault.Record(service: "GitHub", category: "Work"),
        ClassicVault.Record(service: "Chase", category: "Finance"),
        ClassicVault.Record(service: "Amex", category: " finance "),
        ClassicVault.Record(service: "Misc"),
    ]
    let contents = ClassicVault.convert(records)
    #expect(contents.groups.map(\.name) == ["Work", "Finance"])
    #expect(contents.groups[0].color != contents.groups[1].color)
    #expect(contents.entries.map(\.groupID) == [contents.groups[0].id, contents.groups[1].id, contents.groups[1].id, nil])
}

@Test func classicVaultIsAdoptedAndUpgradedKeepingTheOriginal() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let source = dir.appendingPathComponent("vault-from-pc.dat")
    let original = try classicVaultData([ClassicVault.Record(service: "GitHub", category: "Work")], password: "pw")
    try original.write(to: source)

    let storage = VaultStorage(url: dir.appendingPathComponent("Safespace/vault.dat"))
    try storage.adopt(source)
    #expect(storage.holdsClassicVault)

    let contents = try ClassicVault.contents(of: Data(contentsOf: storage.url), password: "pw")
    let vault = try Vault.create(password: "pw", iterations: 1_000)
    try storage.upgradeClassic(to: Vault.encrypt(contents.entries, groups: contents.groups, with: vault))

    #expect(!storage.holdsClassicVault)
    #expect(try Data(contentsOf: storage.classicURL) == original)
    let (_, reopened) = try Vault.decryptContents(storage.read(), password: "pw")
    #expect(reopened.entries.map(\.title) == ["GitHub"])
    #expect(reopened.groups.map(\.name) == ["Work"])
}
