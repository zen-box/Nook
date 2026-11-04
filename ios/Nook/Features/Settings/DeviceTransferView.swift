import SwiftUI
import CoreImage.CIFilterBuiltins
@preconcurrency import AVFoundation
import NookCore

@MainActor
struct DeviceTransferView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var transfer: DeviceTransfer?
    @State private var scanner = false
    @State private var pastedCode = ""
    @State private var includeS3 = true
    @State private var confirmImport = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Keep both phones on the same Wi-Fi or a mutually reachable hotspot, and leave Nook open until the new phone confirms the import.")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
                if let transfer {
                    if transfer.phase == "idle" || transfer.phase == "failed" {
                        PrimaryButton(title: "New Phone: Receive Data", symbol: "qrcode") { transfer.receive() }
                        if store.syncCoordinator.configuration != nil {
                            Toggle("Include S3 connection and library key", isOn: $includeS3)
                        }
                        PrimaryButton(title: "Old Phone: Scan New Phone", symbol: "qrcode.viewfinder") {
                            transfer.includeS3 = includeS3; scanner = true
                        }
                        DisclosureGroup("Enter a Pairing Code") {
                            TextField("Pairing Code", text: $pastedCode, axis: .vertical).font(.caption).textInputAutocapitalization(.never).autocorrectionDisabled()
                            Button("Connect to New Phone") { transfer.includeS3 = includeS3; transfer.connect(code: pastedCode) }.disabled(pastedCode.isEmpty)
                        }
                    }
                    if let code = transfer.pairingCode {
                        VStack(spacing: 12) {
                            if let qr = qrImage(code) { Image(uiImage: qr).interpolation(.none).resizable().scaledToFit().frame(maxWidth: 260).padding(12).background(.white, in: RoundedRectangle(cornerRadius: 12)) }
                            Text("Scan this code with Nook on your old phone. It expires in 10 minutes.").font(.footnote)
                            Button("Copy Pairing Code") { Clipboard.copySecret(code) }
                        }.frame(maxWidth: .infinity)
                    }
                    if let code = transfer.verificationCode, transfer.phase == "verify" || transfer.phase == "awaitingApproval" {
                        VStack(spacing: 16) {
                            Text("Compare Both Screens").font(.headline)
                            Text(verbatim: code).font(.system(size: 42, weight: .bold, design: .monospaced))
                            Text("Continue only if the six digits match on both phones.").font(.footnote)
                            Button("The Codes Match") { transfer.approve() }.buttonStyle(.borderedProminent).disabled(transfer.phase != "verify")
                        }.frame(maxWidth: .infinity).card()
                    }
                    if ["starting", "connecting", "preparing", "receiving", "sending", "awaitingApproval", "awaitingImport"].contains(transfer.phase) {
                        ProgressView(value: transfer.progress)
                        Text(phaseLabel(transfer.phase)).font(.subheadline)
                    }
                    if let staged = transfer.staged, transfer.phase == "readyToImport" {
                        Text("Ready: \(staged.dataset.values.count) records and \(staged.refs.count) attachments.").font(.headline)
                        PrimaryButton(title: "Import on This Phone", symbol: "square.and.arrow.down") { confirmImport = true }
                    }
                    if transfer.phase == "completed" {
                        Label("Transfer Complete", systemImage: "checkmark.circle.fill").font(.title3).foregroundStyle(Theme.accent)
                        Text("The old phone's data is kept. Verify notes, photos, recordings and the vault on the new phone before erasing the old phone.")
                    }
                    if let error = transfer.error { Text(verbatim: error).font(.footnote).foregroundStyle(Pastel.rose.strong) }
                    if transfer.phase != "idle" && transfer.phase != "completed" { Button("Cancel Transfer", role: .destructive) { transfer.cancel() } }
                }
            }.padding(Metrics.screenPadding)
        }
        .background(Theme.background).navigationTitle("Device Migration")
        .onAppear { if transfer == nil { transfer = DeviceTransfer(store: store) } }
        .onDisappear { transfer?.cancel() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { transfer?.cancel() } }
        .sheet(isPresented: $scanner) {
            QRScannerView { value in scanner = false; transfer?.connect(code: value) }.modifier(AppAppearance())
        }
        .confirmationDialog("Import and replace local data?", isPresented: $confirmImport, titleVisibility: .visible) {
            Button("Import Data", role: .destructive) { transfer?.install() }
        } message: { Text("This replaces local records and the encrypted vault with the old phone's data. The vault still needs its original master password. The old phone is not erased.") }
    }
    private func phaseLabel(_ phase: String) -> LocalizedStringKey {
        switch phase {
        case "starting": "Starting local transfer…"
        case "connecting": "Connecting to the new phone…"
        case "preparing": "Preparing encrypted data…"
        case "sending": "Sending encrypted data…"
        case "receiving": "Receiving encrypted data…"
        case "awaitingApproval": "Waiting for confirmation on the other phone…"
        default: "Waiting for the new phone to confirm its import…"
        }
    }
    private func qrImage(_ code: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(code.utf8)
        guard let output = filter.outputImage, let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

@MainActor
private struct QRScannerView: View {
    let onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var authorized = false
    @State private var denied = false
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                if authorized { CameraScanner(onCode: onCode) }
                if denied { Text("Allow camera access in Settings, or enter the pairing code manually.").foregroundStyle(.white).padding() }
            }.ignoresSafeArea(edges: .bottom)
            .navigationTitle("Scan New Phone").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { authorized = await AVCaptureDevice.requestAccess(for: .video); denied = !authorized }
        }
    }
}
@MainActor
private struct CameraScanner: UIViewRepresentable {
    let onCode: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }
    func makeUIView(context: Context) -> CameraPreview {
        let view = CameraPreview(); context.coordinator.start(view); return view
    }
    func updateUIView(_ uiView: CameraPreview, context: Context) { }
    static func dismantleUIView(_ uiView: CameraPreview, coordinator: Coordinator) { coordinator.stop() }

    @MainActor final class Coordinator: NSObject, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
        let onCode: (String) -> Void
        private let camera = CameraSession()
        private var handled = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }
        func start(_ view: CameraPreview) {
            guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device), camera.session.canAddInput(input) else { return }
            camera.session.addInput(input)
            let output = AVCaptureMetadataOutput(); guard camera.session.canAddOutput(output) else { return }
            camera.session.addOutput(output); output.setMetadataObjectsDelegate(self, queue: .main); output.metadataObjectTypes = [.qr]
            view.preview.session = camera.session; view.preview.videoGravity = .resizeAspectFill
            camera.start()
        }
        func stop() { camera.stop() }
        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !handled, let value = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue,
                  value.hasPrefix("nook-transfer://pair/") else { return }
            handled = true; camera.stop(); onCode(value)
        }
    }
}
private final class CameraSession: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.nook.personal.camera")
    func start() { queue.async { [self] in session.startRunning() } }
    func stop() { queue.async { [self] in if session.isRunning { session.stopRunning() } } }
}
private final class CameraPreview: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
