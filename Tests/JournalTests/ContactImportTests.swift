import Foundation
import Testing
import VaultFormat
import VaultStore

@testable import Journal

#if os(iOS)
    import Contacts
#endif

@Suite("Contact import plan tests")
struct ContactImportPlanTests {
    @Test func newContactIsPlannedForCreation() {
        let plan = ContactImportPlan.build(
            selected: [ContactName(name: "  Baran Kaya ", nickname: " Baro ")],
            existingNames: ["Deniz Arıkan"])
        #expect(plan.toCreate == [ContactImportPlan.Item(id: 0, name: "Baran Kaya", aliases: ["Baro"])])
        #expect(plan.alreadyExists.isEmpty)
        #expect(plan.invalid.isEmpty)
        #expect(!plan.isEmpty)
        #expect(ContactImportPlan.build(selected: []).isEmpty)
    }

    @Test func existingNameIsSkipped() {
        let plan = ContactImportPlan.build(
            selected: [ContactName(name: "Deniz Arıkan")], existingNames: ["Deniz Arıkan"])
        #expect(plan.toCreate.isEmpty)
        #expect(plan.alreadyExists == [.init(id: 0, name: "Deniz Arıkan", reason: .alreadyExists)])
    }

    @Test func existingAliasIsSkipped() {
        let plan = ContactImportPlan.build(
            selected: [ContactName(name: "Deniz")], existingNames: ["Mert Aksu"], existingAliases: ["Deniz"])
        #expect(plan.toCreate.isEmpty)
        #expect(plan.alreadyExists == [.init(id: 0, name: "Deniz", reason: .alreadyExists)])
    }

    @Test func caseAndNormalizationVariantsAreTheSameName() {
        let decomposed = "S\u{0327}ule"
        #expect(decomposed.unicodeScalars.count == 5)
        let plan = ContactImportPlan.build(
            selected: [ContactName(name: "deniz ARIKAN"), ContactName(name: decomposed)],
            existingNames: ["Deniz Arıkan", "Şule"])
        // The Turkish capital `I` reads as `ı`, so "ARIKAN" is "arıkan" and the store refuses it too.
        #expect(plan.toCreate.isEmpty)
        #expect(plan.alreadyExists.map(\.name) == ["deniz ARIKAN", decomposed])

        let lower = ContactImportPlan.build(
            selected: [ContactName(name: "DENİZ arıkan")], existingNames: ["deni\u{0307}z Arıkan"])
        #expect(lower.toCreate.isEmpty)
    }

    /// The store's collision rule: the Turkish key (`İ` → `i`, `I` → `ı`) or the default lowercase
    /// mapping alone makes two names one.
    @Test func turkishCapitalsFollowTheStoreCollisionRule() {
        func skipped(_ name: String, _ existing: [ExistingEntityInfo]) -> Bool {
            ContactImportPlan.build(selected: [ContactName(name: name)], existingEntities: existing).toCreate.isEmpty
        }
        #expect(skipped("DENİZ", [.init(name: "Deniz")]))
        #expect(skipped("IŞIK", [.init(name: "Işık")]))
        #expect(skipped("SELIN", [.init(name: "Selin")]))
        #expect(skipped("Selin", [.init(name: "X", fileStem: "SELIN")]))
        #expect(!skipped("İşık", [.init(name: "Işık")]))
        let nickname = ContactImportPlan.build(
            selected: [ContactName(name: "Baran Kaya", nickname: "IŞIK")],
            existingEntities: [.init(name: "X", aliases: ["ışık"])])
        #expect(nickname.toCreate.map(\.aliases) == [[]])
        let selection = ContactImportPlan.build(selected: [ContactName(name: "Deniz"), ContactName(name: "DENİZ")])
        #expect(selection.alreadyExists == [.init(id: 1, name: "DENİZ", reason: .duplicateInSelection)])
    }

    /// A person with a qualifier lives in "Ad (ayırt edici).md" but is still that name; an entity
    /// of another type and a bare filename block the name as well (the store refuses the file).
    @Test func qualifiedPeopleOtherTypesAndFilenamesBlockTheName() {
        let existing = [
            ExistingEntityInfo(name: "Mert Aksu", aliases: ["Mert"], fileStem: "Mert Aksu (iş)"),
            ExistingEntityInfo(name: "Liman Ofis", aliases: ["ofis"], fileStem: "Liman Ofis"),
            ExistingEntityInfo(name: "Görünen Ad", fileStem: "AliVeli"),
        ]
        let plan = ContactImportPlan.build(
            selected: [
                ContactName(name: "Mert Aksu"), ContactName(name: "Ofis"), ContactName(name: "Ali/Veli"),
                ContactName(name: "MERT AKSU (iş)"), ContactName(name: "Yeni Kişi"),
            ],
            existingEntities: existing)
        #expect(plan.alreadyExists.map(\.name) == ["Mert Aksu", "Ofis", "Ali/Veli", "MERT AKSU (iş)"])
        #expect(plan.alreadyExists.allSatisfy { $0.reason == .alreadyExists })
        #expect(plan.toCreate.map(\.name) == ["Yeni Kişi"])
    }

    @Test func duplicateInSelectionCountsAsOne() {
        let plan = ContactImportPlan.build(
            selected: [
                ContactName(name: "Kemal Soylu"), ContactName(name: "kemal soylu"),
                ContactName(name: "Kemal  Soylu", nickname: "Kemo"), ContactName(name: "Kemal:Soylu"),
                ContactName(name: "KemalSoylu"),
            ])
        // Runs of spaces collapse in the filename, so the third is the same file as the first;
        // the fifth is the same file as the fourth once ":" is stripped.
        #expect(plan.toCreate.map(\.name) == ["Kemal Soylu", "Kemal:Soylu"])
        #expect(plan.toCreate.allSatisfy { $0.aliases.isEmpty })
        #expect(plan.alreadyExists.map(\.id) == [1, 2, 4])
        #expect(plan.alreadyExists.allSatisfy { $0.reason == .duplicateInSelection })
        #expect(Set(plan.alreadyExists.map(\.id)).count == 3)
    }

    @Test func emptyAndInvalidNamesAreRejected() {
        let tooLong = String(repeating: "ş", count: 130)
        let plan = ContactImportPlan.build(
            selected: [
                ContactName(name: ""), ContactName(name: "   "), ContactName(name: "/\\:*?"),
                ContactName(name: ".gizli"), ContactName(name: "Ali\u{0007}Veli"), ContactName(name: "Ali\nVeli"),
                ContactName(name: tooLong), ContactName(name: "#.gizli", nickname: "Lakap"),
            ])
        #expect(plan.toCreate.isEmpty)
        #expect(plan.alreadyExists.isEmpty)
        #expect(plan.invalid.map(\.id) == Array(0..<8))
        #expect(plan.invalid.prefix(4).map(\.name) == ["", "", "/\\:*?", ".gizli"])
    }

    @Test func nameKeepsItsCharactersWhileTheFilenameDropsThem() throws {
        let valid = try #require(ContactImportPlan.validatedName(" Dr. Ali [Veli] | Jr. # "))
        #expect(valid.name == "Dr. Ali [Veli] | Jr. #")
        #expect(valid.fileStem == "Dr. Ali Veli Jr.")
        #expect(ContactImportPlan.validatedName("Ali ")?.fileStem == "Ali")
    }

    @Test func nicknameThatCollidesIsDroppedButThePersonIsKept() {
        func aliases(_ selected: [ContactName], _ existing: [ExistingEntityInfo] = []) -> [[String]] {
            let plan = ContactImportPlan.build(selected: selected, existingEntities: existing)
            #expect(plan.toCreate.count == selected.count)
            return plan.toCreate.map(\.aliases)
        }
        let baran = "Baran Kaya"
        // Existing name, existing alias (case differs), existing filename.
        #expect(aliases([ContactName(name: baran, nickname: "deniz")], [.init(name: "Deniz")]) == [[]])
        #expect(aliases([ContactName(name: baran, nickname: "MEMO")], [.init(name: "X", aliases: ["Memo"])]) == [[]])
        #expect(aliases([ContactName(name: baran, nickname: "Dosya")], [.init(name: "X", fileStem: "dosya")]) == [[]])
        // Another selected name: later and earlier in the selection.
        #expect(aliases([ContactName(name: "Ahmet Çelik", nickname: "Ali"), ContactName(name: "Ali")]) == [[], []])
        #expect(aliases([ContactName(name: "Ali"), ContactName(name: "Ahmet Çelik", nickname: "ali")]) == [[], []])
        // Its own name, an alias already planned for an earlier person, blank and control characters.
        #expect(aliases([ContactName(name: "Apo", nickname: "APO")]) == [[]])
        #expect(
            aliases([ContactName(name: "Ahmet Çelik", nickname: "Apo"), ContactName(name: baran, nickname: "apo")])
                == [["Apo"], []])
        #expect(aliases([ContactName(name: baran, nickname: "  ")]) == [[]])
        #expect(aliases([ContactName(name: baran, nickname: "Ba\u{0000}ro")]) == [[]])
        // No collision: kept as typed, forbidden filename characters included (an alias is not a file).
        #expect(aliases([ContactName(name: baran, nickname: " Baro/1 ")]) == [["Baro/1"]])
    }
}

@Suite("Contact import model integration tests")
struct ContactImportModelTests {
    /// Every file under the vault with its bytes, hidden files included.
    private func snapshot(_ root: URL) throws -> [String: Data] {
        var files: [String: Data] = [:]
        let base = root.resolvingSymlinksInPath().path
        let enumerator = try #require(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]))
        for case let url as URL in enumerator {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            files[String(url.resolvingSymlinksInPath().path.dropFirst(base.count))] = try Data(contentsOf: url)
        }
        return files
    }

    /// The imported file is the file the app's own "create a person, then add an alias" path writes.
    @Test @MainActor func importedFileEqualsManuallyCreatedPersonByteForByte() async throws {
        let imported = try EntityPageTestContext()
        defer { imported.clean() }
        await imported.start()
        let manual = try EntityPageTestContext()
        defer { manual.clean() }
        await manual.start()
        let before = try snapshot(imported.root)

        let model = ContactImportModel(store: imported.store)
        model.prepare(candidates: [
            ContactName(name: "Baran Kaya", nickname: "Baro"), ContactName(name: "Zehra: Yıldırım"),
        ])
        await model.importContacts()
        #expect(
            model.result == .init(created: ["Baran Kaya", "Zehra: Yıldırım"], skipped: [], failed: []))

        let first = try await manual.store.createEntity(kind: .person, name: "Baran Kaya", qualifier: nil)
        try await manual.store.setList(at: first.file, key: "aliases", values: [.text("Baro")])
        let second = try await manual.store.createEntity(kind: .person, name: "Zehra: Yıldırım", qualifier: nil)
        #expect(first.file == "people/Baran Kaya.md")
        #expect(second.file == "people/Zehra Yıldırım.md")

        var added = try snapshot(imported.root)
        for (path, bytes) in before {
            #expect(added[path] == bytes, "existing file changed: \(path)")
            added[path] = nil
        }
        #expect(Set(added.keys) == ["/" + first.file, "/" + second.file])
        for file in [first.file, second.file] {
            let expected = try Data(contentsOf: manual.root.appendingPathComponent(file))
            #expect(added["/" + file] == expected, "\(file) differs from the manual path")
        }
        // The alias is in the index as well, from the same single write.
        let known = try #require(imported.store.knownEntities.first { $0.file == first.file })
        #expect(known.name == "Baran Kaya")
        #expect(known.aliases == ["Baro"])
        #expect(imported.store.knownEntities.first { $0.file == second.file }?.name == "Zehra: Yıldırım")
    }

    @Test @MainActor func existingPeopleAreSkippedAndNoFileChanges() async throws {
        let context = try EntityPageTestContext()
        defer { context.clean() }
        // A person whose visible name differs from its filename: the filename is taken as well.
        try Data("---\ntype: person\nname: Başka Görünen\n---\n".utf8).write(
            to: context.root.appendingPathComponent("people/Dosya Adı.md"))
        await context.start()
        let before = try snapshot(context.root)

        let model = ContactImportModel(store: context.store)
        // Name, case variant, alias of a person, name of a qualified person, a place and its alias,
        // a filename.
        let names = [
            "Deniz Arıkan", "deniz arıkan", "Deniz abi", "Mert Aksu", "Liman Ofis", "Ofis", "Ev", "Dosya Adı",
        ]
        model.prepare(candidates: names.map { ContactName(name: $0, nickname: "Yeni Lakap") })
        let plan = try #require(model.plan)
        #expect(plan.toCreate.isEmpty)
        #expect(plan.alreadyExists.map(\.name) == names)

        await model.importContacts()
        #expect(model.result == .init(created: [], skipped: names, failed: []))
        #expect(try snapshot(context.root) == before)
    }

    /// The plan and the store read Turkish capitals alike: what the plan skips the store refuses as
    /// taken, and what the plan creates the store accepts.
    @Test @MainActor func planAndStoreAgreeOnTurkishCapitals() async throws {
        let context = try EntityPageTestContext()
        defer { context.clean() }
        await context.start()
        // Turkish key only, default lowercase only, Turkish key only, neither.
        let names = ["DENİZ ARIKAN", "SELIN KORKMAZ", "ECE YALIN", "İŞIK YENİ"]
        let model = ContactImportModel(store: context.store)
        model.prepare(candidates: names.map { ContactName(name: $0) })
        let plan = try #require(model.plan)
        #expect(plan.alreadyExists.map(\.name) == Array(names.prefix(3)))
        #expect(plan.toCreate.map(\.name) == [names[3]])
        for name in names {
            do {
                _ = try await context.store.createEntity(kind: .person, name: name, qualifier: nil)
                #expect(plan.toCreate.contains { $0.name == name }, "store accepted \(name)")
            } catch VaultStoreError.nameTaken {
                #expect(plan.alreadyExists.contains { $0.name == name }, "store refused \(name)")
            }
        }
    }

    /// A file that appears between the summary and the write is never overwritten: the store's
    /// exclusive creation refuses it, the model reports it as skipped and goes on.
    @Test @MainActor func fileCreatedAfterThePlanIsNotOverwritten() async throws {
        let context = try EntityPageTestContext()
        defer { context.clean() }
        await context.start()

        let model = ContactImportModel(store: context.store)
        model.prepare(candidates: [
            ContactName(name: "Önce Gelen"), ContactName(name: "Baran Kaya", nickname: "Baro"),
            ContactName(name: "Sonra Gelen"),
        ])
        #expect(model.plan?.toCreate.count == 3)

        let foreign = Data("---\ntype: person\nname: Baran Kaya\ntelefon: kurgusal\n---\nDışarıdan yazıldı.\n".utf8)
        let url = context.root.appendingPathComponent("people/baran kaya.md")
        try foreign.write(to: url)

        await model.importContacts()
        #expect(
            model.result == .init(created: ["Önce Gelen", "Sonra Gelen"], skipped: ["Baran Kaya"], failed: []))
        #expect(try Data(contentsOf: url) == foreign)
        let people = try FileManager.default.contentsOfDirectory(
            atPath: context.root.appendingPathComponent("people").path)
        #expect(people.filter { $0.lowercased() == "baran kaya.md" } == ["baran kaya.md"])
        #expect(people.contains("Önce Gelen.md"))
        #expect(people.contains("Sonra Gelen.md"))
    }

    @Test @MainActor func failureDoesNotStopTheRest() async throws {
        var attempted: [String] = []
        let model = ContactImportModel(
            existing: [ExistingEntityInfo(name: "Var Olan")],
            creator: { item in
                attempted.append(item.name)
                if item.name == "Hatalı Kişi" { throw VaultStoreError.staleTarget }
                if item.name == "Araya Giren" { throw VaultStoreError.nameTaken }
            })
        model.prepare(candidates: [
            ContactName(name: "Birinci"), ContactName(name: "Hatalı Kişi"), ContactName(name: "Var Olan"),
            ContactName(name: "Araya Giren"), ContactName(name: "İkinci"),
        ])
        await model.importContacts()

        #expect(attempted == ["Birinci", "Hatalı Kişi", "Araya Giren", "İkinci"])
        #expect(model.result?.created == ["Birinci", "İkinci"])
        #expect(model.result?.skipped == ["Var Olan", "Araya Giren"])
        #expect(model.result?.failed == ["Hatalı Kişi"])
        #expect(!model.isImporting)
    }

    /// A second tap while the first import runs, or after it finished, writes nothing again.
    @Test @MainActor func importRunsOnceForOnePlan() async throws {
        var attempted: [String] = []
        var model: ContactImportModel?
        var busyDuringWrite: [Bool] = []
        var planDuringWrite: [[String]?] = []
        let created = ContactImportModel(creator: { item in
            attempted.append(item.name)
            busyDuringWrite.append(model?.isImporting ?? false)
            // Re-entrant triggers from inside the write: the model is importing, so it must refuse
            // a second import, a cancel and a new selection. (Bounded so a broken guard fails
            // instead of recursing forever.)
            if attempted.count < 8 { await model?.importContacts() }
            model?.cancel()
            planDuringWrite.append(model?.plan?.toCreate.map(\.name))
            model?.prepare(candidates: [ContactName(name: "Araya Sokulan")])
            planDuringWrite.append(model?.plan?.toCreate.map(\.name))
        })
        model = created
        created.prepare(candidates: [ContactName(name: "Birinci"), ContactName(name: "İkinci")])
        await created.importContacts()
        await created.importContacts()

        #expect(attempted == ["Birinci", "İkinci"])
        #expect(busyDuringWrite == [true, true])
        #expect(planDuringWrite == Array(repeating: ["Birinci", "İkinci"], count: 4))
        #expect(created.result == .init(created: ["Birinci", "İkinci"], skipped: [], failed: []))
    }

    @Test @MainActor func preparingAndCancellingWritesNothing() async throws {
        let context = try EntityPageTestContext()
        defer { context.clean() }
        await context.start()
        let before = try snapshot(context.root)

        let model = ContactImportModel(store: context.store)
        model.prepare(candidates: [ContactName(name: "Asla Oluşmayacak", nickname: "Asla")])
        #expect(model.plan?.toCreate.map(\.name) == ["Asla Oluşmayacak"])
        #expect(try snapshot(context.root) == before)

        model.cancel()
        #expect(model.plan == nil)
        #expect(model.result == nil)
        await model.importContacts()
        #expect(model.result == nil)
        #expect(try snapshot(context.root) == before)
    }

    /// The plan repeats the store's name rule (Core keeps it internal). This pins the copy to the
    /// store: what the plan calls invalid the store rejects, and the filename is the one predicted.
    @Test @MainActor func nameRuleMatchesTheStore() async throws {
        let context = try EntityPageTestContext()
        defer { context.clean() }
        await context.start()

        let names = [
            "Ali/Veli", "Ayşe: Kaya", "A|B#C^D[E]", ".nokta", "#.nokta", " Sonda Boşluk  ", "İki  Boşluk",
            "S\u{0327}ule Decomposed", "Soru? Yıldız*", "\"Tırnak\" <Ok>", "Sekme\tVar", "Satır\nVar", "///",
            "Dr. Öner Sağlam Jr.", String(repeating: "ö", count: 130),
        ]
        for name in names {
            let plan = ContactImportPlan.validatedName(name)
            do {
                let entity = try await context.store.createEntity(kind: .person, name: name, qualifier: nil)
                let valid = try #require(plan, "store accepted \(name.debugDescription)")
                #expect(entity.file == "people/" + valid.fileStem + ".md")
                #expect(context.store.knownEntities.first { $0.file == entity.file }?.name == valid.name)
            } catch VaultStoreError.invalidName {
                #expect(plan == nil, "store rejected \(name.debugDescription)")
            }
        }
    }
}

#if os(iOS)
    /// The reader is the only code that sees a `CNContact`. A locally built contact needs no store
    /// and no permission.
    @Suite("Contact name reader tests")
    struct ContactNameReaderTests {
        private let secrets = [
            "5550100", "kurgusal@example.invalid", "Kurgu Sokak", "Kurgu Limited", "Müdür", "Gizli not", "Bölüm",
        ]

        private func makeContact(_ configure: (CNMutableContact) -> Void = { _ in }) -> CNMutableContact {
            let contact = CNMutableContact()
            contact.phoneNumbers = [CNLabeledValue(label: CNLabelHome, value: CNPhoneNumber(stringValue: secrets[0]))]
            contact.emailAddresses = [CNLabeledValue(label: CNLabelHome, value: secrets[1] as NSString)]
            let address = CNMutablePostalAddress()
            address.street = secrets[2]
            contact.postalAddresses = [CNLabeledValue(label: CNLabelHome, value: address)]
            contact.organizationName = secrets[3]
            contact.jobTitle = secrets[4]
            contact.note = secrets[5]
            contact.departmentName = secrets[6]
            contact.birthday = DateComponents(year: 1990, month: 5, day: 14)
            contact.imageData = Data([1, 2, 3])
            configure(contact)
            return contact
        }

        private func expectNoSecrets(_ value: ContactName, _ contact: CNContact) {
            let text = value.name + "|" + (value.nickname ?? "")
            for secret in secrets + [contact.identifier, "1990"] {
                #expect(!text.contains(secret))
            }
        }

        @Test func personNameAndNicknameAreTheOnlyFieldsRead() {
            let contact = makeContact {
                $0.namePrefix = "Dr."
                $0.givenName = "Baran"
                $0.familyName = "Kaya"
                $0.nameSuffix = "Jr."
                $0.nickname = "  Baro "
            }
            let value = ContactNameReader.name(from: contact)
            // The system formatter decides order and affixes; its answer is used unchanged.
            #expect(value.name == CNContactFormatter.string(from: contact, style: .fullName))
            #expect(value.name.contains("Baran"))
            #expect(value.name.contains("Kaya"))
            #expect(value.nickname == "Baro")
            expectNoSecrets(value, contact)
        }

        @Test func singleNameComponentIsEnough() {
            let family = makeContact { $0.familyName = "Kaya" }
            #expect(ContactNameReader.name(from: family) == ContactName(name: "Kaya"))
            let given = makeContact { $0.givenName = "Baran" }
            #expect(ContactNameReader.name(from: given) == ContactName(name: "Baran"))
        }

        @Test func companyCardHasNoPersonName() {
            let company = makeContact { $0.contactType = .organization }
            #expect(ContactNameReader.name(from: company) == ContactName(name: ""))
            // A person card without any name: the formatter would answer with the organization.
            let unnamed = makeContact()
            #expect(CNContactFormatter.string(from: unnamed, style: .fullName)?.isEmpty == false)
            #expect(ContactNameReader.name(from: unnamed) == ContactName(name: ""))
            // A company card that also carries a name is still a company.
            let named = makeContact {
                $0.contactType = .organization
                $0.givenName = "Baran"
            }
            #expect(ContactNameReader.name(from: named) == ContactName(name: ""))
            expectNoSecrets(ContactNameReader.name(from: named), named)
        }

        @Test func nicknameAloneBecomesTheName() {
            let contact = makeContact { $0.nickname = "Dede" }
            let value = ContactNameReader.name(from: contact)
            #expect(value == ContactName(name: "Dede"))
            expectNoSecrets(value, contact)
        }

        @Test func emptyContactIsKeptAsAnInvalidEntry() {
            let value = ContactNameReader.name(from: CNMutableContact())
            #expect(value == ContactName(name: ""))
            #expect(ContactImportPlan.build(selected: [value]).invalid.count == 1)
        }
    }
#endif
