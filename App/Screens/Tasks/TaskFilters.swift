import SwiftUI

/// Manşet-row filter icon shared by the list, kanban and timeline: person, place, project.
/// Accent while a filter is on.
struct TaskFiltersMenu: View {
    @Bindable var model: TasksModel

    var body: some View {
        InkHeaderMenu(
            "Filtre", systemImage: "line.3.horizontal.decrease", isActive: model.hasFilters,
            identifier: "tasks.filter"
        ) {
            ForEach(["person", "place"], id: \.self) { kind in
                Menu(LocalizedStringKey(kind == "person" ? "Kişiler" : "Konumlar")) {
                    ForEach(model.store.content.entities.filter { $0.kind == kind }) { entity in
                        Button {
                            model.entityFilter = entity.id
                        } label: {
                            Text(verbatim: entity.name)
                            if let qualifier = entity.qualifier { Text(verbatim: qualifier) }
                            if model.entityFilter == entity.id { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
            Menu("Projeler") {
                ForEach(model.projects, id: \.self) { project in
                    Button {
                        model.projectFilter = project
                    } label: {
                        Text(verbatim: project)
                        if model.projectFilter == project { Image(systemName: "checkmark") }
                    }
                }
            }
            if model.hasFilters { Button("Filtreleri temizle") { model.clearFilters() } }
        }
    }
}

/// Names the active filters and clears them. Shown under the view menu only while a filter
/// is on; draws no horizontal page margin of its own.
struct TaskFilterBand: View {
    let model: TasksModel

    var body: some View {
        HStack(spacing: 8) {
            if let path = model.entityFilter,
                let entity = model.store.content.entities.first(where: { $0.id == path })
            {
                TagChip(
                    title: entity.name,
                    systemImage: entity.kind == "place" ? "mappin" : "person")
            }
            if let project = model.projectFilter {
                TagChip(title: project, systemImage: "folder")
            }
            Spacer(minLength: 0)
            Button {
                model.clearFilters()
            } label: {
                Label("Filtreleri temizle", systemImage: "xmark.circle")
                    .labelStyle(.iconOnly)
                    .tapTarget()
            }
            .buttonStyle(InkTextButtonStyle())
        }
    }
}
