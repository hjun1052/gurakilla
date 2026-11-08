import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var showInspector = true

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            DashboardView()
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)
            productTable
        }
        .background(.background)
        .inspector(isPresented: $showInspector) {
            Group {
                if let product = model.selectedProducts.first {
                    ProductDetailView(product: product)
                } else {
                    ContentUnavailableView("No Selection", systemImage: "sidebar.right",
                                           description: Text("Select software to see processes, startup jobs and files."))
                }
            }
            .inspectorColumnWidth(min: 300, ideal: 360, max: 520)
        }
        .toolbar { toolbar }
        .navigationTitle("GuraKilla")
        .navigationSubtitle(subtitle)
        .sheet(item: $model.pendingAuthorization) { AuthorizationSheet(request: $0) }
        .sheet(isPresented: $model.showStartupManager) { StartupManagerSheet() }
        .sheet(isPresented: $model.showRestore) { RestoreSheet() }
        .sheet(isPresented: $model.showAuditLog) { AuditLogSheet() }
        .sheet(item: $model.uninstallTarget) { UninstallSheet(product: $0) }
        .alert(model.notice?.title ?? "", isPresented: Binding(
            get: { model.notice != nil }, set: { if !$0 { model.notice = nil } }),
               presenting: model.notice) { notice in
            ForEach(notice.actions) { action in
                Button(action.title, role: action.destructive ? .destructive : nil) { action.run() }
            }
            Button(notice.actions.isEmpty ? "OK" : "Close", role: .cancel) {}
        } message: { Text($0.message) }
    }

    private var subtitle: String {
        if model.isScanning { return "Scanning…" }
        guard let t = model.lastScan else { return "" }
        return "Scanned " + t.formatted(date: .omitted, time: .shortened)
    }

    @ViewBuilder private var productTable: some View {
        @Bindable var model = model
        if model.products.isEmpty {
            if model.isScanning {
                ProgressView("Scanning…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("Nothing Detected", systemImage: "checkmark.shield",
                                       description: Text("No known banking or government security software was found on this Mac."))
            }
        } else {
            Table(model.products, selection: $model.selection) {
                TableColumn("Software") { p in
                    HStack(spacing: 8) {
                        ProductIcon(product: p)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.definition.name).fontWeight(.medium)
                            Text(p.definition.publisher).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .width(min: 180, ideal: 230)
                TableColumn("Status") { p in RunningBadge(product: p) }
                    .width(min: 90, ideal: 110)
                TableColumn("Auto-start") { p in StartupBadge(state: p.startupState) }
                    .width(min: 90, ideal: 110)
                TableColumn("Trusted CAs") { p in
                    let n = p.trustedCertificates.count
                    Text(n == 0 ? "—" : "\(n)").foregroundStyle(n == 0 ? Color.secondary : Color.orange).monospacedDigit()
                }
                .width(min: 60, ideal: 80)
                TableColumn("PID") { p in
                    Text(p.processes.map { String($0.pid) }.joined(separator: ", "))
                        .monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                }
                .width(min: 50, ideal: 80)
                TableColumn("CPU") { p in
                    Text(p.isRunning ? String(format: "%.1f%%", p.totalCPU) : "—").monospacedDigit()
                }
                .width(min: 44, ideal: 56)
                TableColumn("Memory") { p in
                    Text(p.isRunning ? Format.memory(p.totalMemoryKB) : "—").monospacedDigit()
                }
                .width(min: 60, ideal: 76)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                let items = model.products.filter { ids.contains($0.id) }
                Button("Quit") { model.quit(items) }.disabled(!items.contains(where: \.isRunning))
                Button("Manage Startup…") { model.selection = ids; model.showStartupManager = true }
                if items.count == 1, let p = items.first {
                    Button("Uninstall…") { model.uninstallTarget = p }
                    Divider()
                    if let path = p.installPaths.first {
                        Button("Show in Finder") { NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "") }
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { Task { await model.scan() } } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                .disabled(model.isScanning)
                .help("Scan again")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.quitSelected() } label: { Label("Quit Selected", systemImage: "stop.circle") }
                .disabled(!model.selectedProducts.contains(where: \.isRunning))
                .help("Ask the selected software to quit")
            Button { model.quitAll() } label: { Label("Quit All Detected", systemImage: "stop.circle.fill") }
                .disabled(model.processCount == 0)
                .help("Ask every detected program to quit")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.showStartupManager = true } label: { Label("Manage Startup", systemImage: "power") }
                .disabled(model.products.allSatisfy { $0.launchJobs.isEmpty })
                .help("Choose what launches automatically")
            Button { model.uninstallTarget = model.selectedProducts.first } label: { Label("Uninstall", systemImage: "trash") }
                .disabled(model.selectedProducts.count != 1)
                .help("Uninstall the selected software")
            Button { model.showRestore = true } label: { Label("Restore Settings", systemImage: "arrow.uturn.backward.circle") }
                .badge(model.pendingRestores.count)
                .help("Undo changes made by GuraKilla")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.showAuditLog = true } label: { Label("Audit Log", systemImage: "list.bullet.rectangle") }
                .help("Show every change GuraKilla made")
            Button { showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.right") }
        }
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                StatTile(title: "Detected", value: "\(model.products.count)", symbol: "shield.lefthalf.filled",
                         tint: .accentColor)
                StatTile(title: "Running", value: "\(model.runningCount)",
                         detail: "\(model.processCount) process\(model.processCount == 1 ? "" : "es")",
                         symbol: "bolt.fill", tint: model.runningCount > 0 ? .orange : .secondary)
                StatTile(title: "Auto-start", value: "\(model.autoStartJobCount)", detail: "launchd jobs",
                         symbol: "power", tint: model.autoStartJobCount > 0 ? .pink : .green)
                StatTile(title: "Trusted roots", value: "\(model.trustedCertificateCount)", detail: "vendor certs",
                         symbol: "checkmark.seal", tint: model.trustedCertificateCount > 0 ? .orange : .green)
                StatTile(title: "CPU", value: String(format: "%.1f%%", model.totalCPU), symbol: "cpu", tint: .blue)
                StatTile(title: "Memory", value: Format.memory(model.totalMemoryKB), symbol: "memorychip", tint: .purple)
            }
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var detail: String? = nil
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value).font(.system(.title3, design: .rounded, weight: .semibold)).monospacedDigit()
                        .contentTransition(.numericText())
                    if let detail { Text(detail).font(.caption2).foregroundStyle(.tertiary).lineLimit(1) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}

// MARK: - Small components

struct ProductIcon: View {
    let product: DetectedProduct
    var body: some View {
        if let path = product.bundles.first?.path {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable().frame(width: 24, height: 24)
        } else {
            Image(systemName: product.isLeftover ? "shippingbox" : "lock.shield")
                .font(.system(size: 15)).foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
        }
    }
}

struct RunningBadge: View {
    let product: DetectedProduct
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(product.isRunning ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 7, height: 7)
            Text(product.isRunning ? "Running" : (product.isLeftover ? "Leftover" : "Stopped"))
                .foregroundStyle(product.isRunning ? .primary : .secondary)
        }
    }
}

struct StartupBadge: View {
    let state: StartupState
    var body: some View {
        switch state {
        case .none:
            Text("—").foregroundStyle(.tertiary)
        case .enabled(let n):
            Label(n == 1 ? "On" : "On (\(n))", systemImage: "power")
                .labelStyle(.titleAndIcon).foregroundStyle(.pink)
        case .disabled:
            Label("Off", systemImage: "power").foregroundStyle(.secondary)
        }
    }
}

enum Format {
    static func memory(_ kb: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(kb) * 1024, countStyle: .memory)
    }
}
