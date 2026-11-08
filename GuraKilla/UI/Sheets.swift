import SwiftUI

// MARK: - Authorization review

struct AuthorizationSheet: View {
    @Environment(AppModel.self) private var model
    let request: PendingAuthorization

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield").font(.system(size: 28)).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.title).font(.headline)
                    Text("Administrator authorization required").font(.callout).foregroundStyle(.secondary)
                }
            }
            Text(request.explanation).fixedSize(horizontal: false, vertical: true)
            Text("The following commands will run as root:").font(.callout.weight(.medium))
            ScrollView {
                Text(request.script)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(minHeight: 90, maxHeight: 220)
            .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 10))
            Text("macOS will ask for your password. GuraKilla never sees or stores it, and the action is recorded in the audit log.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.cancelPendingAuthorization() }
                    .keyboardShortcut(.cancelAction)
                Button("Continue…") { model.runPendingAuthorization() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
            }
        }
        .padding(20)
        .frame(width: 540)
        .interactiveDismissDisabled()
    }
}

// MARK: - Startup manager

struct StartupManagerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var desired: [String: Bool] = [:]
    @State private var unloadNow = false

    private var scope: [DetectedProduct] {
        let sel = model.selectedProducts.filter { !$0.launchJobs.isEmpty }
        return sel.isEmpty ? model.products.filter { !$0.launchJobs.isEmpty } : sel
    }

    private var changedCount: Int {
        scope.flatMap(\.launchJobs).filter { desired[$0.id] != nil && desired[$0.id] != $0.autoStarts }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Manage Startup").font(.title3.weight(.semibold))
                Text("Choose which launchd jobs start automatically at login or boot. This is different from quitting: turning auto-start off prevents **future** launches but doesn't stop anything running now — unless you also unload the job below.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)

            List {
                ForEach(scope) { product in
                    Section(product.definition.name) {
                        ForEach(product.launchJobs) { job in
                            Toggle(isOn: binding(job)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(job.label).font(.callout.monospaced())
                                    Text(verbatim: [job.domain.displayName,
                                                   job.domain.requiresAdmin ? String(localized: "needs administrator") : nil,
                                                   job.isLoaded ? (job.isRunning ? String(localized: "loaded, running") : String(localized: "loaded"))
                                                                : String(localized: "not loaded")].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.switch)
                        }
                    }
                }
            }
            .frame(minHeight: 260)

            HStack {
                Toggle("Also unload disabled jobs now (stops them immediately)", isOn: $unloadNow)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(changedCount == 0 ? "Apply" : changedCount == 1 ? "Apply 1 Change" : LocalizedStringKey("Apply \(changedCount) Changes")) {
                    model.applyStartup(desired, unloadNow: unloadNow)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)
                .disabled(changedCount == 0)
            }
            .padding(16)
        }
        .frame(width: 620, height: 520)
    }

    private func binding(_ job: LaunchJob) -> Binding<Bool> {
        Binding(get: { desired[job.id] ?? job.autoStarts }, set: { desired[job.id] = $0 })
    }
}

// MARK: - Restore

struct RestoreSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var records: [ChangeRecord] { model.changes.sorted { $0.date > $1.date } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Restore Settings").font(.title3.weight(.semibold))
                Text("Every change GuraKilla made is listed here. Auto-start changes are re-enabled in launchd; removed files are moved back from the Trash.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(20)

            if records.isEmpty {
                ContentUnavailableView("No Changes", systemImage: "clock.arrow.circlepath",
                                       description: Text("GuraKilla hasn't changed anything yet."))
                    .frame(minHeight: 260)
            } else {
                List(records) { r in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.localizedSummary).font(.callout).lineLimit(2).truncationMode(.middle)
                            Text(verbatim: "\(r.product) · \(r.date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let at = r.restoredAt {
                            Text("Restored \(at.formatted(date: .numeric, time: .omitted))").font(.caption).foregroundStyle(.green)
                        } else if r.isReversible {
                            Button("Restore") { model.restore([r]) }.controlSize(.small)
                        } else {
                            Text("Not reversible").font(.caption).foregroundStyle(.tertiary)
                                .help("Package receipts can only be recreated by reinstalling the software.")
                        }
                    }
                }
                .frame(minHeight: 260)
            }

            HStack {
                Button("Open Trash") { NSWorkspace.shared.open(URL(fileURLWithPath: Paths.expand("~/.Trash"))) }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Restore All") { model.restore(model.pendingRestores) }
                    .buttonStyle(.glassProminent)
                    .disabled(model.pendingRestores.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 620, height: 480)
    }
}

// MARK: - Audit log

struct AuditLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = AuditLog.read()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Audit Log").font(.title3.weight(.semibold))
                Spacer()
                Text(AuditLog.url.path).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            .padding(16)
            ScrollView {
                Text(text.isEmpty ? String(localized: "No entries yet.") : text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(.quaternary.opacity(0.4))
            HStack {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([AuditLog.url]) }
                Button("Reload") { text = AuditLog.read() }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 720, height: 480)
    }
}

// MARK: - Uninstall

struct UninstallSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let product: DetectedProduct
    @State private var plan: RemovalPlan?
    @State private var selected = Set<String>()
    @State private var confirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ProductIcon(product: product).scaleEffect(1.5).frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Uninstall \(product.definition.name)").font(.title3.weight(.semibold))
                    Text(product.definition.localizedPublisher).foregroundStyle(.secondary)
                }
            }

            if !product.uninstallers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Recommended: use the vendor's uninstaller", systemImage: "checkmark.seal")
                        .font(.callout.weight(.semibold))
                    Text("It knows about every component, including kernel extensions and browser add-ons, and asks for authorization itself.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(product.uninstallers, id: \.self) { path in
                        Button("Open \((path as NSString).lastPathComponent)") {
                            model.openVendorUninstaller(path, product: product.definition.name)
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 12))
            }

            Text(product.uninstallers.isEmpty ? LocalizedStringKey("Removal plan") : "Or remove manually")
                .font(.headline)
            Text("Review each item. Files are moved to your Trash, not deleted, and can be put back from Restore Settings. Items also used by other installed software are unchecked.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let plan {
                List {
                    Section("Will be removed") {
                        ForEach(plan.items) { item in
                            Toggle(isOn: Binding(get: { selected.contains(item.id) },
                                                 set: { if $0 { selected.insert(item.id) } else { selected.remove(item.id) } })) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.displayPath).font(.caption.monospaced()).lineLimit(2).truncationMode(.middle)
                                    HStack(spacing: 6) {
                                        Text(item.kind.localizedName)
                                        if item.requiresAdmin { Text("· administrator") }
                                        if item.kind == .receipt { Text("· not reversible") }
                                        if item.kind == .certificate { Text("· backed up, restorable") }
                                        if !item.sharedWith.isEmpty {
                                            Text("· also used by \(item.sharedWith.joined(separator: ", "))").foregroundStyle(.orange)
                                        }
                                    }
                                    .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if !plan.excluded.isEmpty {
                        Section("Not touched") {
                            ForEach(plan.excluded) { e in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.path).font(.caption.monospaced())
                                    Text(Bundle.main.localizedString(forKey: e.reason, value: e.reason, table: nil)).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if !product.launchJobs.isEmpty || product.isRunning {
                        Section("Before removal") {
                            Text("\(product.launchJobs.filter(\.isLoaded).count) launchd job(s) will be unloaded and \(product.processes.count) process(es) asked to quit.")
                                .font(.caption)
                        }
                    }
                }
                .frame(minHeight: 220)
            } else {
                ProgressView("Building removal plan…").frame(maxWidth: .infinity, minHeight: 220)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(selected.count == 1 ? "Move 1 Item to Trash…" : LocalizedStringKey("Move \(selected.count) Items to Trash…"), role: .destructive) { confirm = true }
                    .disabled(selected.isEmpty || plan == nil)
            }
        }
        .padding(20)
        .frame(width: 640, height: 600)
        .task {
            let all = model.products, p = product
            let built = await Task.detached { Uninstaller.plan(for: p, among: all) }.value
            plan = built
            selected = built.defaultSelection
        }
        .confirmationDialog("Remove \(product.definition.name)?", isPresented: $confirm) {
            Button("Move to Trash", role: .destructive) {
                if let plan { model.executeRemoval(plan, selected: selected) }
            }
        } message: {
            Text("\(selected.count) item(s) will be moved to the Trash after stopping the software. Package receipts that are forgotten cannot be restored.")
        }
    }
}

// MARK: - Localized removal labels (engine strings stay English for the CLI and audit log)

extension RemovalItem.Kind {
    var localizedName: String {
        switch self {
        case .installLocation: String(localized: "Install location")
        case .launchdPlist: String(localized: "Launchd plist")
        case .receiptFile: String(localized: "Package file")
        case .extraFile: String(localized: "Installed file")
        case .receipt: String(localized: "Package receipt")
        case .certificate: String(localized: "Trusted certificate")
        }
    }
}

extension RemovalItem {
    var displayPath: String {
        guard let c = certificate else { return path }
        let keychain = c.inSystemKeychain ? String(localized: "System keychain") : String(localized: "login keychain")
        return "\(c.commonName) — \(keychain), \(c.trustLabel)"
    }
}
