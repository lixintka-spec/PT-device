import SwiftUI
import AVFoundation

/// Clinic mode (device only): the PT films the movement with the rear camera while
/// CameraCaptureAccessory shows the patient their own screen on the outer display —
/// live encouragement and a tap-to-rate pain scale. The Simulator has no camera.
struct CameraAssessmentView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var camera = AssessmentCamera()
    @State private var patientScreenEnabled = true
    @State private var patientScreenAvailable = false
    @State private var pain: Int?

    var body: some View {
        NavigationStack {
            ZStack {
                RangeTheme.backdrop
                VStack(spacing: 18) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24).fill(.black)
                        if camera.isRunning {
                            CameraPreview(session: camera.session)
                                .clipShape(.rect(cornerRadius: 24))
                        } else {
                            ContentUnavailableView("Camera unavailable",
                                                   systemImage: "camera.metering.unknown",
                                                   description: Text("Run on iPhone Duo to film the assessment. The Simulator has no camera."))
                        }
                    }
                    HStack {
                        Label(patientScreenAvailable ? "Patient screen live on outer display" : "Patient screen appears when capturing full screen",
                              systemImage: "rectangle.portrait.on.rectangle.portrait")
                            .font(.subheadline)
                            .foregroundStyle(patientScreenAvailable ? RangeTheme.mint : RangeTheme.secondaryText)
                        Spacer()
                        if let pain {
                            Chip(text: "Patient pain \(pain)/10", systemImage: "hand.tap.fill", tint: RangeTheme.amber)
                        }
                    }
                }
                .padding(24)
            }
            .navigationTitle("Camera Assessment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Label("Close", systemImage: "xmark") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Toggle(isOn: $patientScreenEnabled) {
                        Label("Patient Screen", systemImage: "person.crop.rectangle")
                    }
                    .disabled(!patientScreenAvailable)
                }
            }
            .sceneAccessory {
                CameraCaptureAccessory(isEnabled: $patientScreenEnabled) {
                    PatientFacingView(pain: $pain)
                }
                .onAvailabilityChange { patientScreenAvailable = $0 }
            }
        }
        .task { await camera.start() }
        .onDisappear { camera.stop() }
    }
}

/// What the patient sees on the outer display while being filmed. Interactive.
struct PatientFacingView: View {
    @Binding var pain: Int?
    var body: some View {
        ZStack {
            RangeTheme.backdrop
            VStack(spacing: 16) {
                Text("You're doing great").font(.title.bold())
                Text("Slow bend… and hold.").font(.title3).foregroundStyle(RangeTheme.secondaryText)
                Text("How does it feel?").font(.headline).padding(.top, 12)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(0...10, id: \.self) { value in
                        Button {
                            pain = value
                        } label: {
                            Text("\(value)")
                                .font(RangeTheme.numeral(22, weight: .bold))
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background((pain == value ? RangeTheme.amber : Color.white.opacity(0.08)), in: .rect(cornerRadius: 12))
                                .foregroundStyle(pain == value ? .black : .white)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .padding()
        }
    }
}

@MainActor
@Observable
final class AssessmentCamera {
    let session = AVCaptureSession()
    private(set) var isRunning = false

    func start() async {
        guard await AVCaptureDevice.requestAccess(for: .video),
              let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }
        session.commitConfiguration()
        let s = session
        await Task.detached { s.startRunning() }.value
        isRunning = session.isRunning
    }

    func stop() {
        let s = session
        Task.detached { s.stopRunning() }
        isRunning = false
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
