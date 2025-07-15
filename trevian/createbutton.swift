//
    //  CreateButton.swift
    //  SuperSimpleObjectCapture
    //
    import SwiftUI
    import RealityKit
    @MainActor
    struct CreateButton: View {
        let session: ObjectCaptureSession
        
        var body: some View {
            Button(action: {
                performAction()
            }, label: {
                Text(label)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
            })
        }
        
        private var label: LocalizedStringKey {
            switch session.state {
            case .ready:
                return "Start detecting"
            case .detecting:
                return "Start capturing"
            default:
                return "…"
            }
        }
        
        private func performAction() {
            switch session.state {
            case .ready:
                let ok = session.startDetecting()
                print(ok ? "▶️ Start detecting" : "😨 Could not start detecting")
            case .detecting:
                session.startCapturing()
            default:
                print("Estado no válido para acción")
            }
        }
    }


