import Foundation
import SwiftData

@MainActor
class AppDependencyContainer: ObservableObject {
    // Core Services
    let clippy: Clippy
    let clipboardMonitor: ClipboardMonitor
    let contextEngine: ContextEngine
    let visionParser: VisionScreenParser
    let hotkeyManager: HotkeyManager
    let textCaptureService: TextCaptureService
    let clippyController: ClippyWindowController
    var spotlightController: SpotlightWindowController!
    let guardianService: GuardianService
    let conversationManager: ConversationManager
    let slashCommandHandler: SlashCommandHandler
    
    // AI Services
    let localAIService: LocalAIService
    let grokService: GrokService
    let audioRecorder: AudioRecorder
    let calendarService: CalendarService
    let mem0Service: Mem0Service
    
    /// Currently selected AI service (persisted in UserDefaults)
    @Published var selectedAIServiceType: AIServiceType = .local {
        didSet {
            UserDefaults.standard.set(selectedAIServiceType.rawValue, forKey: "SelectedAIService")
        }
    }
    
    /// Unified AI service access - returns the currently selected service
    var aiService: any AIServiceProtocol {
        switch selectedAIServiceType {
        case .local: return localAIService
        case .grok: return grokService
        }
    }
    
    // Data Layer
    var repository: ClipboardRepository?
    
    init() {
        print("🏗️ [AppDependencyContainer] Initializing services...")
        
        // 1. Initialize Independent Services
        self.clippy = Clippy()
        self.contextEngine = ContextEngine()
        self.visionParser = VisionScreenParser()
        self.hotkeyManager = HotkeyManager()
        self.clippyController = ClippyWindowController()
        self.audioRecorder = AudioRecorder()
        self.localAIService = LocalAIService()
        self.grokService = GrokService(apiKey: UserDefaults.standard.string(forKey: "Grok_API_Key") ?? "")
        self.calendarService = CalendarService()
        self.textCaptureService = TextCaptureService()
        self.guardianService = GuardianService()
        self.conversationManager = ConversationManager()
        self.slashCommandHandler = SlashCommandHandler()
        self.mem0Service = Mem0Service()
        
        // 2. Initialize Dependent Services
        self.clipboardMonitor = ClipboardMonitor()
        
        print("✅ [AppDependencyContainer] Services initialized.")
        
        // 3. Initialize services that need self reference (after all stored properties are set)
        self.spotlightController = SpotlightWindowController(container: self)
        
        // 4. Wire up calendar service to Grok
        self.grokService.setCalendarService(calendarService)
    }
    
    func inject(modelContext: ModelContext) {
        print("💉 [AppDependencyContainer] Injecting ModelContext and Cross-Service Dependencies...")
        
        // Initialize Repository
        self.repository = SwiftDataClipboardRepository(modelContext: modelContext, vectorService: clippy)
        
        // Inject dependencies into ClipboardMonitor
        if let repo = self.repository {
            clipboardMonitor.startMonitoring(
                repository: repo,
                contextEngine: contextEngine,
                grokService: grokService,
                localAIService: localAIService
            )
        }
        
        // Inject dependencies into TextCaptureService
        textCaptureService.setDependencies(
            clippyController: clippyController,
            clipboardMonitor: clipboardMonitor
        )
        
        // Inject dependencies into GuardianService and start monitoring
        guardianService.setDependencies(
            contextEngine: contextEngine,
            spotlightController: spotlightController
        )
        guardianService.startMonitoring()
        
        // Inject dependencies into SlashCommandHandler
        slashCommandHandler.conversationManager = conversationManager
        slashCommandHandler.guardianService = guardianService
        slashCommandHandler.mem0Service = mem0Service
        
        print("✅ [AppDependencyContainer] All dependencies injected. Guardian mode active.")
    }
}
