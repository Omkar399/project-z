import Foundation
import AppKit
import Carbon

@MainActor
class RizzSessionManager: ObservableObject {
    @Published var isActive: Bool = false
    @Published var currentOptions: [String] = []
    @Published var currentIndex: Int = 0
    
    private var hotkeyManager: HotkeyManager?
    private weak var clipboardMonitor: ClipboardMonitor?
    
    func setup(hotkeyManager: HotkeyManager, clipboardMonitor: ClipboardMonitor) {
        self.hotkeyManager = hotkeyManager
        self.clipboardMonitor = clipboardMonitor
    }
    
    func startSession(options: [String]) {
        guard !options.isEmpty else { return }
        
        print("🚀 [RizzSessionManager] Starting session with \(options.count) options")
        self.currentOptions = options
        self.currentIndex = 0
        self.isActive = true
        
        // Immediately type the first option
        pasteTextAtomic(options[0])
        
        // Notify HotkeyManager (it observes us via container or binding)
        hotkeyManager?.setRizzMode(active: true)
    }
    
    func cycleNext() {
        guard isActive, !currentOptions.isEmpty else { return }
        
        currentIndex = (currentIndex + 1) % currentOptions.count
        let nextOption = currentOptions[currentIndex]
        
        print("🔄 [RizzSessionManager] Cycling Next -> \(nextOption)")
        replaceCurrentText(with: nextOption)
    }
    
    func cyclePrevious() {
        guard isActive, !currentOptions.isEmpty else { return }
        
        currentIndex = (currentIndex - 1 + currentOptions.count) % currentOptions.count
        let prevOption = currentOptions[currentIndex]
        
        print("🔄 [RizzSessionManager] Cycling Prev -> \(prevOption)")
        replaceCurrentText(with: prevOption)
    }
    
    func commit() {
        print("✅ [RizzSessionManager] Committing selection")
        endSession()
    }
    
    func cancel() {
        print("❌ [RizzSessionManager] Cancelling session")
        // Optional: Delete the current text? Or leave it?
        // User probably expects it to stay if they just cancel modal mode, 
        // but typically "Cancel" might mean revert. 
        // For now, let's leave it (non-destructive).
        endSession()
    }
    
    private func endSession() {
        isActive = false
        currentOptions = []
        currentIndex = 0
        hotkeyManager?.setRizzMode(active: false)
    }
    
    // MARK: - Text Manipulation
    
    private func replaceCurrentText(with newText: String) {
        // 1. Select All (Cmd + A)
        simulateCmdA()
        
        // Short delay to allow selection
        usleep(50_000) // 50ms
        
        // 2. Paste/Type new text (Cmd+V is cleaner than typing for replacing)
        pasteTextAtomic(newText)
    }
    
    private func simulateCmdA() {
        let source = CGEventSource(stateID: .hidSystemState)
        let aKeyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x00, keyDown: true) // 0x00 is 'A'
        let aKeyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x00, keyDown: false)
        
        aKeyDown?.flags = .maskCommand
        aKeyUp?.flags = .maskCommand
        
        aKeyDown?.post(tap: .cghidEventTap)
        aKeyUp?.post(tap: .cghidEventTap)
    }
    
    private func pasteTextAtomic(_ text: String) {
        // Pause monitoring to prevent saving Rizz options to history
        Task { @MainActor in clipboardMonitor?.pause() }
        
        let pasteboard = NSPasteboard.general
        let oldContent = pasteboard.string(forType: .string)
        
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // Simulate Cmd+V
        let source = CGEventSource(stateID: .hidSystemState)
        let vKeyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // 0x09 is 'V'
        let vKeyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        
        vKeyDown?.flags = .maskCommand
        vKeyUp?.flags = .maskCommand
        
        vKeyDown?.post(tap: .cghidEventTap)
        vKeyUp?.post(tap: .cghidEventTap)
        
        // Restore clipboard after short delay
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if let old = oldContent {
                let p = NSPasteboard.general
                p.clearContents()
                p.setString(old, forType: .string)
            }
            // Resume monitoring
            Task { @MainActor in self?.clipboardMonitor?.resume() }
        }
    }
}

