import Foundation
import Testing
import VaultStore

@testable import Journal

@MainActor
struct EntityCreationTests {
    @Test(arguments: [VaultEntityKind.person, .place])
    func createsOnceAndReturnsDetailDestination(_ kind: VaultEntityKind) async throws {
        let context = try EntityPageTestContext()
        defer { context.clean() }
        await context.start()
        let model = EntityCreationModel(store: context.store, kind: kind)
        #expect(!model.canSave)
        model.name = "  Kurgusal Ad  "
        #expect(model.canSave)
        let entity = try #require(await model.save())
        #expect(entity.name == "Kurgusal Ad")
        #expect(entity.kind == kind.rawValue)
        #expect(model.created == entity)
        #expect(context.store.content.entities.contains { $0.id == entity.id })
        #expect(FileManager.default.fileExists(atPath: context.root.appendingPathComponent(entity.id).path))
        #expect(!model.canSave)
        #expect(await model.save() == nil)
    }

    @Test func duplicateRequiresQualifierAndVaultSwitchInvalidatesDraft() async throws {
        let context = try EntityPageTestContext()
        defer { context.clean() }
        await context.start()
        let model = EntityCreationModel(store: context.store, kind: .person)
        model.name = "Deniz Arıkan"
        #expect(model.needsQualifier && !model.canSave)
        model.qualifier = "Kurgusal kulüp"
        #expect(model.canSave)
        let entity = try #require(await model.save())
        #expect(entity.qualifier == "Kurgusal kulüp")
        #expect(entity.id != context.path)
        let stale = EntityCreationModel(store: context.store, kind: .place)
        stale.name = "Kurgusal Konum"
        let other = context.directory.appendingPathComponent("Other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        await context.store.select(other)
        #expect(!stale.canSave)
        #expect(await stale.save() == nil)
    }

    /// A refused name (here a note's file name, so no known entity) asks for a qualifier only
    /// while that name is in the field; another name saves without one.
    @Test func refusedNameAsksForQualifierOnlyWhileItIsTyped() async throws {
        let context = try EntityPageTestContext()
        defer { context.clean() }
        await context.start()
        let model = EntityCreationModel(store: context.store, kind: .person)
        model.name = "Okuma Listesi"
        #expect(!model.needsQualifier && model.canSave)
        #expect(await model.save() == nil)
        #expect(model.needsQualifier && !model.canSave && model.errorText != nil)
        model.name = "Kurgusal Ad"
        #expect(!model.needsQualifier && model.canSave)
        model.name = "  okuma listesi "
        #expect(model.needsQualifier && !model.canSave)
    }
}
