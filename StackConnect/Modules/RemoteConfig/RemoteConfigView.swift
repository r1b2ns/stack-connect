import SwiftUI
import APIProviderFirebase

// MARK: - Factory

@MainActor
struct RemoteConfigViewFactory {
    static func build(project: FirebaseProjectModel, account: AccountModel) -> some View {
        RemoteConfigEntry(project: project, account: account)
    }
}

// MARK: - Entry

private struct RemoteConfigEntry: View {
    let project: FirebaseProjectModel
    let account: AccountModel

    @StateObject private var viewModel: RemoteConfigViewModel

    init(project: FirebaseProjectModel, account: AccountModel) {
        self.project = project
        self.account = account
        _viewModel = StateObject(wrappedValue: RemoteConfigViewModel(project: project, account: account))
    }

    var body: some View {
        RemoteConfigView(viewModel: viewModel)
    }
}

// MARK: - View

struct RemoteConfigView<ViewModel: RemoteConfigViewModelProtocol>: View {

    @ObservedObject var viewModel: ViewModel

    var body: some View {
        buildContent()
            .navigationTitle(String(localized: "Remote Config"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $viewModel.uiState.searchQuery,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: String(localized: "Search parameters")
            )
            .toolbar { buildToolbar() }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .sheet(item: $viewModel.uiState.selectedParameter) { item in
                RemoteConfigParameterDetailSheet(
                    item: item,
                    conditions: viewModel.uiState.conditions,
                    onSave: { name, param in
                        viewModel.updateParameter(name, parameter: param)
                    },
                    onDelete: { name in
                        viewModel.deleteParameter(name)
                    }
                )
            }
            .sheet(isPresented: $viewModel.uiState.showCreateParameter) {
                RemoteConfigCreateParameterSheet(
                    conditions: viewModel.uiState.conditions,
                    existingNames: Set(viewModel.uiState.parameters.map(\.name))
                ) { name, param in
                    viewModel.addParameter(name, parameter: param)
                    viewModel.uiState.showCreateParameter = false
                } onCancel: {
                    viewModel.uiState.showCreateParameter = false
                }
            }
            .toast(message: $viewModel.uiState.toastMessage)
    }

    // MARK: - Content

    @ViewBuilder
    private func buildContent() -> some View {
        if viewModel.uiState.isLoading && viewModel.uiState.parameters.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.uiState.error {
            buildError(error)
        } else {
            buildList()
        }
    }

    private func buildError(_ message: String) -> some View {
        ContentUnavailableView {
            Label(String(localized: "Error"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button(String(localized: "Retry")) {
                Task { await viewModel.load() }
            }
        }
    }

    private func buildList() -> some View {
        List {
            buildConditionsRow()
            buildParametersSection()
            buildVersionSection()
        }
    }

    // MARK: - Conditions Row

    private func buildConditionsRow() -> some View {
        Section {
            NavigationLink {
                RemoteConfigConditionsView(
                    conditions: $viewModel.uiState.conditions,
                    onAdd: { viewModel.addCondition($0) },
                    onUpdate: { viewModel.updateCondition(at: $0, with: $1) },
                    onDelete: { viewModel.deleteCondition(at: $0) },
                    onMove: { viewModel.moveCondition(from: $0, to: $1) },
                    onDuplicate: { viewModel.duplicateCondition($0) }
                )
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .font(.body)
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.indigo)
                        .clipShape(RoundedRectangle(cornerRadius: 7))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Conditions"))
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)

                        Text(viewModel.uiState.conditions.isEmpty
                             ? String(localized: "No conditions")
                             : "\(viewModel.uiState.conditions.count) condition\(viewModel.uiState.conditions.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Parameters Section

    @ViewBuilder
    private func buildParametersSection() -> some View {
        Section {
            if viewModel.uiState.filteredParameters.isEmpty {
                if !viewModel.uiState.searchQuery.isEmpty {
                    Text(String(localized: "No results for \"\(viewModel.uiState.searchQuery)\""))
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    Text(String(localized: "No parameters defined"))
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            } else {
                ForEach(viewModel.uiState.filteredParameters) { item in
                    Button {
                        viewModel.uiState.selectedParameter = item
                    } label: {
                        buildParameterRow(item)
                    }
                    .foregroundStyle(.primary)
                }
                .onDelete { indexSet in
                    let names = indexSet.map { viewModel.uiState.filteredParameters[$0].name }
                    names.forEach { viewModel.deleteParameter($0) }
                }
            }
        } header: {
            HStack {
                Text("Parameters")
                Spacer()
                Text("\(viewModel.uiState.filteredParameters.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func buildParameterRow(_ item: RemoteConfigParameterItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.valueType.iconName)
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(item.valueType.color)
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 4) {
                    Text(item.displayValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if !item.conditionNames.isEmpty {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text("\(item.conditionNames.count) condition\(item.conditionNames.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                if let desc = item.parameter.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Version Section

    @ViewBuilder
    private func buildVersionSection() -> some View {
        if let version = viewModel.uiState.version {
            Section {
                if let number = version.versionNumber {
                    HStack {
                        Label(String(localized: "Version"), systemImage: "clock.arrow.circlepath")
                        Spacer()
                        Text("#\(number)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let email = version.updateUser?.email {
                    HStack {
                        Label(String(localized: "Last Published By"), systemImage: "person.fill")
                        Spacer()
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                if let time = version.updateTime {
                    HStack {
                        Label(String(localized: "Published At"), systemImage: "calendar")
                        Spacer()
                        Text(time.formattedPublishDate)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Last Published Version")
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func buildToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                viewModel.uiState.showCreateParameter = true
            } label: {
                Image(systemName: "plus")
            }
        }

        ToolbarItem(placement: .secondaryAction) {
            Button {
                Task { await viewModel.saveTemplate() }
            } label: {
                if viewModel.uiState.isSaving {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Label(String(localized: "Publish"), systemImage: "arrow.up.circle.fill")
                }
            }
            .disabled(viewModel.uiState.isSaving)
        }
    }
}

// MARK: - Conditions Screen

struct RemoteConfigConditionsView: View {

    @Binding var conditions: [RemoteConfigCondition]

    let onAdd: (RemoteConfigCondition) -> Void
    let onUpdate: (Int, RemoteConfigCondition) -> Void
    let onDelete: (Int) -> Void
    let onMove: (IndexSet, Int) -> Void
    let onDuplicate: (RemoteConfigCondition) -> Void

    @State private var showAddCondition = false
    @State private var editingConditionIndex: Int? = nil

    var body: some View {
        List {
            if conditions.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "No Conditions"), systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Add a condition to target specific users or environments.")
                }
            } else {
                ForEach(Array(conditions.enumerated()), id: \.element.id) { index, condition in
                    buildConditionRow(condition, index: index)
                }
                .onMove(perform: onMove)
                .onDelete { indexSet in
                    indexSet.sorted(by: >).forEach { onDelete($0) }
                }
            }
        }
        .navigationTitle(String(localized: "Conditions"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editingConditionIndex = nil
                    showAddCondition = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
        }
        .sheet(isPresented: $showAddCondition) {
            RemoteConfigAddConditionSheet(
                editingCondition: editingConditionIndex.flatMap { conditions[safe: $0] },
                onSave: { condition in
                    if let idx = editingConditionIndex {
                        onUpdate(idx, condition)
                    } else {
                        onAdd(condition)
                    }
                    editingConditionIndex = nil
                    showAddCondition = false
                },
                onCancel: {
                    editingConditionIndex = nil
                    showAddCondition = false
                }
            )
        }
    }

    private func buildConditionRow(_ condition: RemoteConfigCondition, index: Int) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(condition.tagColor.swiftUIColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(condition.name)
                    .font(.body)
                    .fontWeight(.medium)

                if let expr = condition.expression, !expr.isEmpty {
                    Text(expr)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let desc = condition.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            editingConditionIndex = index
            showAddCondition = true
        }
        .contextMenu {
            Button {
                editingConditionIndex = index
                showAddCondition = true
            } label: {
                Label(String(localized: "Edit"), systemImage: "pencil")
            }

            Button {
                onDuplicate(condition)
            } label: {
                Label(String(localized: "Duplicate"), systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive) {
                onDelete(index)
            } label: {
                Label(String(localized: "Delete"), systemImage: "trash")
            }
        }
    }
}

// MARK: - Parameter Detail Sheet

struct RemoteConfigParameterDetailSheet: View {

    let item: RemoteConfigParameterItem
    let conditions: [RemoteConfigCondition]
    let onSave: (String, RemoteConfigParameter) -> Void
    let onDelete: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var description: String
    @State private var valueType: RemoteConfigParameter.ValueType
    @State private var defaultValue: String
    @State private var useInAppDefault: Bool
    @State private var conditionalValues: [ConditionalEntry]
    @State private var showDeleteAlert = false

    struct ConditionalEntry: Identifiable {
        let id = UUID()
        var conditionName: String
        var value: String
    }

    init(
        item: RemoteConfigParameterItem,
        conditions: [RemoteConfigCondition],
        onSave: @escaping (String, RemoteConfigParameter) -> Void,
        onDelete: @escaping (String) -> Void
    ) {
        self.item = item
        self.conditions = conditions
        self.onSave = onSave
        self.onDelete = onDelete

        _name = State(initialValue: item.name)
        _description = State(initialValue: item.parameter.description ?? "")
        _valueType = State(initialValue: item.parameter.valueType ?? .string)
        _defaultValue = State(initialValue: item.parameter.defaultValue?.value ?? "")
        _useInAppDefault = State(initialValue: item.parameter.defaultValue?.useInAppDefault ?? false)
        _conditionalValues = State(initialValue:
            (item.parameter.conditionalValues ?? [:])
                .sorted { $0.key < $1.key }
                .map { ConditionalEntry(conditionName: $0.key, value: $0.value.value ?? "") }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                buildIdentitySection()
                buildDefaultValueSection()
                buildConditionalValuesSection()
                buildDangerSection()
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) { saveAndDismiss() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert(String(localized: "Delete Parameter"), isPresented: $showDeleteAlert) {
                Button(String(localized: "Delete"), role: .destructive) {
                    onDelete(item.name)
                    dismiss()
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete \"\(item.name)\"? This cannot be undone.")
            }
        }
    }

    private func buildIdentitySection() -> some View {
        Section {
            LabeledContent(String(localized: "Name")) {
                TextField(String(localized: "parameter_name"), text: $name)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            LabeledContent(String(localized: "Description")) {
                TextField(String(localized: "Optional description"), text: $description)
                    .multilineTextAlignment(.trailing)
            }

            Picker(String(localized: "Data Type"), selection: $valueType) {
                ForEach(RemoteConfigParameter.ValueType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
        } header: {
            Text("Identity")
        }
    }

    private func buildDefaultValueSection() -> some View {
        Section {
            Toggle(String(localized: "Use In-App Default"), isOn: $useInAppDefault)

            if !useInAppDefault {
                LabeledContent(String(localized: "Default Value")) {
                    buildValueField(value: $defaultValue, type: valueType)
                }
            }
        } header: {
            Text("Default Value")
        } footer: {
            if useInAppDefault {
                Text("The app's compiled-in default value will be used.")
            }
        }
    }

    private func buildConditionalValuesSection() -> some View {
        Section {
            ForEach($conditionalValues) { $entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.conditionName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    buildValueField(value: $entry.value, type: valueType)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete { indexSet in
                conditionalValues.remove(atOffsets: indexSet)
            }

            let available = conditions.filter { c in
                !conditionalValues.contains(where: { $0.conditionName == c.name })
            }

            if !available.isEmpty {
                Menu {
                    ForEach(available) { condition in
                        Button(condition.name) {
                            conditionalValues.append(ConditionalEntry(conditionName: condition.name, value: ""))
                        }
                    }
                } label: {
                    Label(String(localized: "Add Condition Value"), systemImage: "plus.circle")
                }
            }
        } header: {
            Text("Condition Values")
        } footer: {
            Text("Condition values override the default when the condition is matched.")
        }
    }

    private func buildDangerSection() -> some View {
        Section {
            Button(role: .destructive) {
                showDeleteAlert = true
            } label: {
                Label(String(localized: "Delete Parameter"), systemImage: "trash")
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func buildValueField(value: Binding<String>, type: RemoteConfigParameter.ValueType) -> some View {
        switch type {
        case .boolean:
            Picker("", selection: value) {
                Text("true").tag("true")
                Text("false").tag("false")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 120)
        case .number:
            TextField("0", text: value)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
        case .json:
            TextField("{}", text: value)
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .font(.system(.caption, design: .monospaced))
        case .string:
            TextField(String(localized: "value"), text: value)
                .multilineTextAlignment(.trailing)
        }
    }

    private func saveAndDismiss() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let defaultVal: RemoteConfigParameterValue = useInAppDefault
            ? RemoteConfigParameterValue(useInAppDefault: true)
            : RemoteConfigParameterValue(value: defaultValue)

        var condValues: [String: RemoteConfigParameterValue] = [:]
        for entry in conditionalValues {
            condValues[entry.conditionName] = RemoteConfigParameterValue(value: entry.value)
        }

        let param = RemoteConfigParameter(
            defaultValue: defaultVal,
            conditionalValues: condValues.isEmpty ? nil : condValues,
            description: description.isEmpty ? nil : description,
            valueType: valueType
        )

        onSave(trimmedName, param)
        dismiss()
    }
}

// MARK: - Create Parameter Sheet

struct RemoteConfigCreateParameterSheet: View {

    let conditions: [RemoteConfigCondition]
    let existingNames: Set<String>
    let onCreate: (String, RemoteConfigParameter) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var description = ""
    @State private var valueType: RemoteConfigParameter.ValueType = .string
    @State private var defaultValue = ""
    @State private var useInAppDefault = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent(String(localized: "Name")) {
                        TextField(String(localized: "parameter_name"), text: $name)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    LabeledContent(String(localized: "Description")) {
                        TextField(String(localized: "Optional"), text: $description)
                            .multilineTextAlignment(.trailing)
                    }

                    Picker(String(localized: "Data Type"), selection: $valueType) {
                        ForEach(RemoteConfigParameter.ValueType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                } header: {
                    Text("Parameter")
                }

                Section {
                    Toggle(String(localized: "Use In-App Default"), isOn: $useInAppDefault)

                    if !useInAppDefault {
                        LabeledContent(String(localized: "Default Value")) {
                            buildValueField()
                        }
                    }
                } header: {
                    Text("Default Value")
                }
            }
            .navigationTitle(String(localized: "New Parameter"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Create")) { createAndClose() }
                        .disabled(!isValid)
                }
            }
        }
    }

    @ViewBuilder
    private func buildValueField() -> some View {
        switch valueType {
        case .boolean:
            Picker("", selection: $defaultValue) {
                Text("true").tag("true")
                Text("false").tag("false")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 120)
        case .number:
            TextField("0", text: $defaultValue)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
        case .json:
            TextField("{}", text: $defaultValue)
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .font(.system(.caption, design: .monospaced))
        case .string:
            TextField(String(localized: "value"), text: $defaultValue)
                .multilineTextAlignment(.trailing)
        }
    }

    private var isValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && !existingNames.contains(trimmed)
    }

    private func createAndClose() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let defaultVal: RemoteConfigParameterValue = useInAppDefault
            ? RemoteConfigParameterValue(useInAppDefault: true)
            : RemoteConfigParameterValue(value: defaultValue)

        let param = RemoteConfigParameter(
            defaultValue: defaultVal,
            description: description.isEmpty ? nil : description,
            valueType: valueType
        )

        onCreate(trimmedName, param)
    }
}

// MARK: - Add / Edit Condition Sheet

struct RemoteConfigAddConditionSheet: View {

    let editingCondition: RemoteConfigCondition?
    let onSave: (RemoteConfigCondition) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var expression: String
    @State private var tagColor: RemoteConfigCondition.TagColor
    @State private var condDescription: String

    init(
        editingCondition: RemoteConfigCondition? = nil,
        onSave: @escaping (RemoteConfigCondition) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.editingCondition = editingCondition
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: editingCondition?.name ?? "")
        _expression = State(initialValue: editingCondition?.expression ?? "")
        _tagColor = State(initialValue: editingCondition?.tagColor ?? .blue)
        _condDescription = State(initialValue: editingCondition?.description ?? "")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent(String(localized: "Name")) {
                        TextField(String(localized: "condition_name"), text: $name)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    LabeledContent(String(localized: "Expression")) {
                        TextField("device.os == 'ios'", text: $expression)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.system(.caption, design: .monospaced))
                    }

                    LabeledContent(String(localized: "Description")) {
                        TextField(String(localized: "Optional"), text: $condDescription)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Condition")
                }

                Section {
                    Picker(String(localized: "Color"), selection: $tagColor) {
                        ForEach(RemoteConfigCondition.TagColor.allCases.filter { $0 != .unspecified }, id: \.self) { color in
                            HStack {
                                Circle()
                                    .fill(color.swiftUIColor)
                                    .frame(width: 12, height: 12)
                                Text(color.displayName)
                            }
                            .tag(color)
                        }
                    }
                } header: {
                    Text("Display")
                }
            }
            .navigationTitle(editingCondition == nil ? String(localized: "New Condition") : String(localized: "Edit Condition"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingCondition == nil ? String(localized: "Add") : String(localized: "Save")) {
                        let condition = RemoteConfigCondition(
                            name: name.trimmingCharacters(in: .whitespaces),
                            expression: expression.isEmpty ? nil : expression,
                            tagColor: tagColor,
                            description: condDescription.isEmpty ? nil : condDescription
                        )
                        onSave(condition)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Extensions

extension RemoteConfigParameter.ValueType {
    var displayName: String {
        switch self {
        case .string: return "String"
        case .number: return "Number"
        case .boolean: return "Boolean"
        case .json: return "JSON"
        }
    }

    var iconName: String {
        switch self {
        case .string: return "textformat"
        case .number: return "number"
        case .boolean: return "togglepower"
        case .json: return "curlybraces"
        }
    }

    var color: Color {
        switch self {
        case .string: return .blue
        case .number: return .orange
        case .boolean: return .green
        case .json: return .purple
        }
    }
}

extension Optional where Wrapped == RemoteConfigCondition.TagColor {
    var swiftUIColor: Color {
        self?.swiftUIColor ?? .gray
    }
}

extension RemoteConfigCondition.TagColor {
    var swiftUIColor: Color {
        switch self {
        case .unspecified: return .gray
        case .blue: return .blue
        case .brown: return .brown
        case .cyan: return .cyan
        case .deepOrange: return Color(red: 1, green: 0.34, blue: 0.13)
        case .green: return .green
        case .indigo: return .indigo
        case .lime: return Color(red: 0.80, green: 0.96, blue: 0.28)
        case .orange: return .orange
        case .pink: return .pink
        case .purple: return .purple
        case .teal: return .teal
        }
    }

    var displayName: String {
        switch self {
        case .unspecified: return "Default"
        case .blue: return "Blue"
        case .brown: return "Brown"
        case .cyan: return "Cyan"
        case .deepOrange: return "Deep Orange"
        case .green: return "Green"
        case .indigo: return "Indigo"
        case .lime: return "Lime"
        case .orange: return "Orange"
        case .pink: return "Pink"
        case .purple: return "Purple"
        case .teal: return "Teal"
        }
    }
}

extension String {
    var formattedPublishDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
            "yyyy-MM-dd'T'HH:mm:ss'Z'"
        ]

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: self) {
                let display = DateFormatter()
                display.dateStyle = .medium
                display.timeStyle = .short
                return display.string(from: date)
            }
        }
        return self
    }
}

