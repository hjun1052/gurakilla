import SwiftUI

struct ProductDetailView: View {
    @Environment(AppModel.self) private var model
    let product: DetectedProduct

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let notes = product.definition.notes {
                    Label(notes, systemImage: "info.circle")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                actions
                processes
                launchJobs
                certificates
                extensions
                files
                receipts
            }
            .padding(16)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ProductIcon(product: product).scaleEffect(1.6).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(product.definition.name).font(.title3.weight(.semibold))
                Text([product.definition.publisher, product.definition.category].compactMap { $0 }.joined(separator: " · "))
                    .font(.callout).foregroundStyle(.secondary)
                if !product.observedTeams.isEmpty {
                    Label("Signed by team " + product.observedTeams.joined(separator: ", "), systemImage: "checkmark.seal")
                        .font(.caption).foregroundStyle(.green)
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button("Quit") { model.quit([product]) }
                .disabled(!product.isRunning)
            Button("Startup…") { model.selection = [product.id]; model.showStartupManager = true }
                .disabled(product.launchJobs.isEmpty)
            Button("Uninstall…", role: .destructive) { model.uninstallTarget = product }
        }
        .buttonStyle(.glass)
        .controlSize(.small)
    }

    @ViewBuilder private var processes: some View {
        Section {
            if product.processes.isEmpty {
                Text("Not running").foregroundStyle(.secondary).font(.callout)
            }
            ForEach(product.processes) { p in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(p.name).fontWeight(.medium)
                        Spacer()
                        Text(String(format: "%.1f%%", p.cpu)).monospacedDigit()
                        Text(Format.memory(p.rssKB)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    Text("PID \(p.pid) · \(p.owner) · \(CodeSigning.info(path: p.path).label)")
                        .font(.caption).foregroundStyle(.secondary)
                    PathText(path: p.path)
                }
                .padding(10)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
            }
        } header: { SectionHeader("Processes", symbol: "bolt") }
    }

    @ViewBuilder private var launchJobs: some View {
        if !product.launchJobs.isEmpty {
            Section {
                ForEach(product.launchJobs) { job in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(job.label).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(job.autoStarts ? "Auto-start on" : "Auto-start off")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(job.autoStarts ? .pink : .secondary)
                        }
                        Text("\(job.domain.displayName) · \(job.isLoaded ? (job.state ?? "loaded") : "not loaded")\(job.keepAlive ? " · KeepAlive" : "")\(job.pid.map { " · PID \($0)" } ?? "")")
                            .font(.caption).foregroundStyle(.secondary)
                        PathText(path: job.plistPath)
                    }
                    .padding(10)
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
                }
            } header: { SectionHeader("Startup (launchd)", symbol: "power") }
        }
    }

    @ViewBuilder private var certificates: some View {
        if !product.certificates.isEmpty {
            Section {
                ForEach(product.certificates) { c in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(c.commonName).fontWeight(.medium).lineLimit(1)
                            Spacer()
                            Text(c.isSelfSigned ? "Root CA" : "Leaf").font(.caption).foregroundStyle(.secondary)
                        }
                        Text("\(c.trustLabel) · \(c.inSystemKeychain ? "System" : "login") keychain · expires \(c.notAfter)")
                            .font(.caption).foregroundStyle(c.isTrusted ? .orange : .secondary)
                        Text("SHA-256 \(c.sha256)").font(.caption2.monospaced()).foregroundStyle(.tertiary)
                            .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    }
                    .padding(10)
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
                }
                Text("A trusted root lets anything signed with its key appear secure to your browsers. It stays trusted after the software is gone unless removed.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } header: { SectionHeader("Certificates", symbol: "checkmark.seal") }
        }
    }

    @ViewBuilder private var extensions: some View {
        if !product.systemExtensions.isEmpty || !product.kernelExtensions.isEmpty {
            Section {
                ForEach(product.systemExtensions) { e in
                    PathRow(path: e.bundleID, symbol: "puzzlepiece.extension", detail: "System extension · team \(e.teamID) · \(e.state)")
                }
                ForEach(product.kernelExtensions, id: \.self) { PathRow(path: $0, symbol: "cpu", detail: "Kernel extension · never removed by GuraKilla") }
            } header: { SectionHeader("Extensions", symbol: "puzzlepiece.extension") }
        }
    }

    @ViewBuilder private var files: some View {
        if !product.installPaths.isEmpty || !product.bundles.isEmpty || !product.uninstallers.isEmpty || !product.extraPaths.isEmpty {
            Section {
                ForEach(product.installPaths, id: \.self) { PathRow(path: $0, symbol: "folder") }
                ForEach(product.bundles) { b in
                    PathRow(path: b.path, symbol: "app", detail: [b.bundleID, b.version.map { "v\($0)" }, b.signing.label].compactMap { $0 }.joined(separator: " · "))
                }
                ForEach(product.extraPaths, id: \.self) { PathRow(path: $0, symbol: "doc", detail: "Installed by the product's scripts") }
                ForEach(product.uninstallers, id: \.self) { PathRow(path: $0, symbol: "trash", detail: "Vendor uninstaller") }
            } header: { SectionHeader("Files", symbol: "folder") }
        }
    }

    @ViewBuilder private var receipts: some View {
        if !product.receipts.isEmpty {
            Section {
                ForEach(product.receipts, id: \.self) { r in
                    Text(r).font(.caption.monospaced()).textSelection(.enabled)
                }
            } header: { SectionHeader("Package receipts", symbol: "shippingbox") }
        }
    }
}

struct SectionHeader: View {
    let title: String
    let symbol: String
    init(_ title: String, symbol: String) { self.title = title; self.symbol = symbol }
    var body: some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }
}

struct PathText: View {
    let path: String
    var body: some View {
        Text(path).font(.caption.monospaced()).foregroundStyle(.tertiary)
            .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
    }
}

struct PathRow: View {
    let path: String
    let symbol: String
    var detail: String? = nil
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                PathText(path: path)
                if let detail { Text(detail).font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            Button { NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "") } label: {
                Image(systemName: "arrow.right.circle")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
        }
    }
}
