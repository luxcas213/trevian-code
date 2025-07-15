import SwiftUI
import RealityKit
struct ContentView: View {
    
    @State private var session: ObjectCaptureSession?
    @State private var rootImageFolder: URL?
    @State private var modelFolderPath: URL?
    
    @State private var photogrammetrySession: PhotogrammetrySession?
    @State private var isProgressing = false
    @State private var quickLookIsPresented = false
    
    @State private var passCount: Int = 0
    private let maxPasses = 2
    
    var modelPath: URL? {
        return modelFolderPath?.appending(path: "model.usdz")
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack {
                // Estado inicial: botón “Iniciar Escaneo”
                if session == nil && !isProgressing && !quickLookIsPresented {
                    Spacer()
                    Button("Iniciar Escaneo") {
                        startNewScanWorkflow()
                    }
                    .font(.title2.bold())
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    Spacer()
                }
                // Sesión activa: mostrar cámara y controles
                else if session != nil {
                    ObjectCaptureView(session: session!)
                        .edgesIgnoringSafeArea(.all)
                    
                    VStack(spacing: 16) {
                        if session!.state == .ready || session!.state == .detecting {
                            CreateButton(session: session!)
                        }
                        
                        Text("Pasada \(passCount) de \(maxPasses) — Estado: \(session!.state.label)")
                            .bold()
                            .foregroundColor(.yellow)
                            .padding(.bottom, 8)
                        
                        Button("Reiniciar Escaneo") {
                            resetAll()
                        }
                        .font(.subheadline)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(Color.red.opacity(0.8))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .padding(.top, 8)
                    }
                    .background(Color.black.opacity(0.5))
                }
                // Fotogrametría en progreso → nada más (overlay lo cubre)
                else if isProgressing {
                    Spacer(minLength: 0)
                    Spacer(minLength: 0)
                }
            }
            
            // Overlay de progreso
            if isProgressing {
                Color.black.opacity(0.4)
                    .edgesIgnoringSafeArea(.all)
                    .overlay {
                        VStack(spacing: 16) {
                            ProgressView("Reconstruyendo modelo…")
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .foregroundColor(.white)
                                .padding()
                            Text("Por favor, espera mientras se genera el modelo en 3D.")
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                        .background(Color.black.opacity(1))
                        .cornerRadius(12)
                        .padding(32)
                    }
            }
        }
        // Hoja de QuickLook
        .sheet(isPresented: $quickLookIsPresented) {
            if let modelPath {
                ARQuickLookView(modelFile: modelPath) {
                    resetAll()
                }
            }
        }
        // Cada vez que userCompletedScanPass == true
        .onChange(of: session?.userCompletedScanPass) { _, newValue in
            guard let passed = newValue, passed else { return }
            
            passCount += 1
            print("📸 Pasada \(passCount) completada.")
            
            if passCount < maxPasses {
                // En iOS 17+ continuamos la misma sesión sin reiniciar
                if #available(iOS 17.0, *) {
                    print("➡️ Avanzando a la siguiente pasada con beginNewScanPass()")
                    session?.beginNewScanPass()
                } else {
                    print("⚠️ iOS < 17: no es posible continuar la misma sesión sin reiniciar.")
                    // Si quieres soportar iOS 16 aquí tendrías que reiniciar la sesión manualmente
                }
            } else {
                // Ultima pasada → terminar captura
                print("✅ Todas las pasadas completadas. Llamando a session.finish()")
                session?.finish()
            }
        }
        // Cuando session.state llegue a .completed → lanzar Photogrammetry
        .onChange(of: session?.state) { _, newState in
            if newState == .completed {
                print("🔄 session.state llegó a .completed → arrancando Photogrammetry")
                Task { await startReconstruction() }
            }
        }
    }
    
    // MARK: Funciones Auxiliares
    
    func startNewScanWorkflow() {
        passCount = 0
        
        // 1.1) Crear carpeta raíz Scans/<timestamp>/
        guard let baseScanDir = createTimestampedScanFolder() else {
            print("❌ No pude crear la carpeta raíz de escaneo.")
            return
        }
        
        // 1.2) Definir carpeta de imágenes y de modelos
        rootImageFolder = baseScanDir.appendingPathComponent("Images/", isDirectory: true)
        modelFolderPath   = baseScanDir.appendingPathComponent("Models/",  isDirectory: true)
        
        // 1.3) Crear físicamente esas carpetas
        do {
            try FileManager.default.createDirectory(
                at: rootImageFolder!,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: modelFolderPath!,
                withIntermediateDirectories: true
            )
        } catch {
            print("❌ Error creando carpetas raíz: \(error)")
            return
        }
        
        // 1.4) Inicializar y arrancar la sesión de Object Capture
        session = ObjectCaptureSession()
        session?.start(imagesDirectory: rootImageFolder!)
    }
    
    private func createTimestampedScanFolder() -> URL? {
        guard let documents = try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        
        let scansRoot = documents.appendingPathComponent("Scans/", isDirectory: true)
        if !FileManager.default.fileExists(atPath: scansRoot.path) {
            do {
                try FileManager.default.createDirectory(
                    at: scansRoot,
                    withIntermediateDirectories: true
                )
            } catch {
                print("❌ Error creando carpeta Scans/: \(error)")
                return nil
            }
        }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())
        
        let newScanDir = scansRoot.appendingPathComponent(timestamp, isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: newScanDir,
                withIntermediateDirectories: true
            )
            return newScanDir
        } catch {
            print("❌ Error creando carpeta con timestamp: \(error)")
            return nil
        }
    }
    
    private func startReconstruction() async {
        guard let allImagesFolder = rootImageFolder,
              let modelDir = modelFolderPath else {
            print("❌ No tengo rutas para Photogrammetry.")
            return
        }
        
        // 4.2) Mostrar overlay de progreso
        isProgressing = true
        
        do {
            var config = PhotogrammetrySession.Configuration()
            config.featureSensitivity = .high
            config.sampleOrdering    = .sequential
            
            let session = try PhotogrammetrySession(
                input: allImagesFolder,   // <-- Uso directo de Images/
                configuration: config
            )
            photogrammetrySession = session
            
            let request = PhotogrammetrySession.Request
                .modelFile(
                    url: modelDir.appendingPathComponent("model.usdz"),
                    detail: .reduced
                )
            
            try session.process(requests: [request])
            
            for try await output in session.outputs {
                switch output {
                case .requestError(let err):
                    print("📛 Error en Photogrammetry: \(err)")
                    isProgressing = false
                    photogrammetrySession = nil
                    return
                case .processingCancelled:
                    print("⚠️ Photogrammetry cancelada.")
                    isProgressing = false
                    photogrammetrySession = nil
                    return
                case .processingComplete:
                    print("✅ Photogrammetry completada. Mostrando QuickLook.")
                    isProgressing = false
                    photogrammetrySession = nil
                    quickLookIsPresented = true
                default:
                    break
                }
            }
        } catch {
            print("❌ Al lanzar PhotogrammetrySession: \(error)")
            isProgressing = false
            photogrammetrySession = nil
        }
    }
    
    func resetAll() {
        session = nil
        photogrammetrySession = nil
        isProgressing = false
        quickLookIsPresented = false
        passCount = 0
        
        if let documents = try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true) {
            let scansRoot = documents.appendingPathComponent("Scans/", isDirectory: true)
            if FileManager.default.fileExists(atPath: scansRoot.path) {
                do {
                    try FileManager.default.removeItem(at: scansRoot)
                    print("🗑️ Carpeta Scans/ borrada.")
                } catch {
                    print("⚠️ Error borrando Scans/: \(error)")
                }
            }
        }
        
        rootImageFolder = nil
        modelFolderPath = nil
    }
}


