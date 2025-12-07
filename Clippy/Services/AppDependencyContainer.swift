import Foundation
import SwiftData

@MainActor
class AppDependencyContainer: ObservableObject {
    // Core Services
    let clippy: ProjectZ
    let clipboardMonitor: ClipboardMonitor
    let contextEngine: ContextEngine
    let visionParser: VisionScreenParser
    let hotkeyManager: HotkeyManager
    let textCaptureService: TextCaptureService
    let clippyController: ProjectZWindowController
    var spotlightController: SpotlightWindowController!
    let guardianService: GuardianService
    let conversationManager: ConversationManager
    let slashCommandHandler: SlashCommandHandler
    let rizzSessionManager: RizzSessionManager // New Service
    
    // AI Services
    let grokService: GrokService
    let audioRecorder: AudioRecorder
    let calendarService: CalendarService
    let mem0Service: Mem0Service
    
    /// Unified AI service access - returns the single cloud AI service
    var aiService: any AIServiceProtocol {
        return grokService
    }
    
    // Data Layer
    var repository: ClipboardRepository?
    
    init() {
        print("🏗️ [AppDependencyContainer] Initializing services...")
        
        // 1. Initialize Independent Services
        self.clippy = ProjectZ()
        self.contextEngine = ContextEngine()
        self.visionParser = VisionScreenParser()
        self.hotkeyManager = HotkeyManager()
        self.clippyController = ProjectZWindowController()
        self.audioRecorder = AudioRecorder()
        self.grokService = GrokService(apiKey: UserDefaults.standard.string(forKey: "Grok_API_Key") ?? "")
        self.calendarService = CalendarService()
        self.textCaptureService = TextCaptureService()
        self.guardianService = GuardianService()
        self.conversationManager = ConversationManager()
        self.slashCommandHandler = SlashCommandHandler()
        self.mem0Service = Mem0Service()
        self.rizzSessionManager = RizzSessionManager() // Initialize RizzManager
        
        // 2. Initialize Dependent Services
        self.clipboardMonitor = ClipboardMonitor()
        
        print("✅ [AppDependencyContainer] Services initialized.")
        
        // 3. Initialize services that need self reference (after all stored properties are set)
        self.spotlightController = SpotlightWindowController(container: self)
        
        // 4. Wire up calendar service to Grok
        self.grokService.setCalendarService(calendarService)
        
        // 5. Wire up RizzSessionManager
        self.rizzSessionManager.setup(hotkeyManager: self.hotkeyManager)
        self.hotkeyManager.rizzSessionManager = self.rizzSessionManager
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
                grokService: grokService
            )
        }
        
        // Inject dependencies into TextCaptureService
        textCaptureService.setDependencies(
            clippyController: clippyController,
            clipboardMonitor: clipboardMonitor
        )
        
        // Inject dependencies into SpotlightWindowController
        spotlightController.inject(modelContext: modelContext)
        
        // Inject dependencies into GuardianService and start monitoring
        guardianService.setDependencies(
            contextEngine: contextEngine,
            spotlightController: spotlightController,
            grokService: grokService,
            mem0Service: mem0Service
        )
        guardianService.startMonitoring()
        
        // Inject dependencies into SlashCommandHandler
        slashCommandHandler.conversationManager = conversationManager
        slashCommandHandler.guardianService = guardianService
        slashCommandHandler.mem0Service = mem0Service
        
        print("✅ [AppDependencyContainer] All dependencies injected. Guardian mode active.")
    }
}
