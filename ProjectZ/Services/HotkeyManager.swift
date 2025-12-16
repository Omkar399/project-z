import Foundation
import AppKit
import Carbon

@MainActor
class HotkeyManager: ObservableObject {
    @Published var isListening = false
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var onTrigger: (() -> Void)?
    private var onVisionTrigger: (() -> Void)?
    private var onTextCaptureTrigger: (() -> Void)?
    private var onVoiceCaptureTrigger: (() -> Void)?
    private var onSpotlightTrigger: (() -> Void)?
    private var onPrivacyModeTrigger: (() -> Void)?
    private var onRizzTrigger: (() -> Void)?
    
    // Rizz Mode Integration
    weak var rizzSessionManager: RizzSessionManager?
    private var isRizzModeActive: Bool = false
    
    func setRizzMode(active: Bool) {
        self.isRizzModeActive = active
        print("🎹 [HotkeyManager] Rizz Mode Active: \(active)")
    }
    
    func startListening(
        onTrigger: @escaping () -> Void,
        onVisionTrigger: @escaping () -> Void,
        onTextCaptureTrigger: @escaping () -> Void,
        onVoiceCaptureTrigger: @escaping () -> Void,
        onSpotlightTrigger: @escaping () -> Void,
        onPrivacyModeTrigger: @escaping () -> Void,
        onRizzTrigger: @escaping () -> Void
    ) {
        self.onTrigger = onTrigger
        self.onVisionTrigger = onVisionTrigger
        self.onTextCaptureTrigger = onTextCaptureTrigger
        self.onVoiceCaptureTrigger = onVoiceCaptureTrigger
        self.onSpotlightTrigger = onSpotlightTrigger
        self.onPrivacyModeTrigger = onPrivacyModeTrigger
        self.onRizzTrigger = onRizzTrigger
        
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                
                // -------------------------------------------------------------
                // EXCLUSIVE RIZZ MODE INTERCEPTION
                // -------------------------------------------------------------
                if manager.isRizzModeActive {
                    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                    
                    // Up Arrow (126)
                    if keyCode == 126 {
                        print("⬆️ [HotkeyManager] Rizz Up Arrow Intercepted")
                        DispatchQueue.main.async { manager.rizzSessionManager?.cyclePrevious() }
                        return nil // Consume event
                    }
                    
                    // Down Arrow (125)
                    if keyCode == 125 {
                        print("⬇️ [HotkeyManager] Rizz Down Arrow Intercepted")
                        DispatchQueue.main.async { manager.rizzSessionManager?.cycleNext() }
                        return nil // Consume event
                    }
                    
                    // Return/Enter (36) - Commit
                    if keyCode == 36 {
                        print("✅ [HotkeyManager] Rizz Commit (Enter)")
                        // We let Enter go through so it sends the message, but we stop the session
                        DispatchQueue.main.async { manager.rizzSessionManager?.commit() }
                        // Allow event to pass through to send message
                        return Unmanaged.passUnretained(event)
                    }
                    
                    // Escape (53) - Cancel
                    if keyCode == 53 {
                        print("❌ [HotkeyManager] Rizz Cancel (Esc)")
                        DispatchQueue.main.async { manager.rizzSessionManager?.cancel() }
                        return nil // Consume event
                    }
                    
                    // Any other key triggers implicit commit/exit (User is editing manually)
                    // We shouldn't block their typing.
                    // Option: Stop session on any other key? Or stay active?
                    // Let's stay active for arrows, but if they type letters, we pass them through.
                }
                
                // -------------------------------------------------------------
                // STANDARD HOTKEYS
                // -------------------------------------------------------------
                
                // Check for Option+X (text capture trigger)
                if event.flags.contains(.maskAlternate) && event.getIntegerValueField(.keyboardEventKeycode) == 7 { // 7 = X
                    print("⌨️ [HotkeyManager] Option+X detected!")
                    DispatchQueue.main.async {
                        manager.onTextCaptureTrigger?()
                    }
                    return nil // Consume event
                }
                
                // Check for Option+Space (voice capture trigger)
                if event.flags.contains(.maskAlternate) && event.getIntegerValueField(.keyboardEventKeycode) == 49 { // 49 = Space
                    print("🎙️ [HotkeyManager] Option+Space detected!")
                    DispatchQueue.main.async {
                        manager.onVoiceCaptureTrigger?()
                    }
                    return nil // Consume event
                }
                
                // Check for Option+V (vision parsing)
                if event.flags.contains(.maskAlternate) && event.getIntegerValueField(.keyboardEventKeycode) == 9 { // 9 = V
                    print("⌨️ [HotkeyManager] Option+V detected!")
                    DispatchQueue.main.async {
                        manager.onVisionTrigger?()
                    }
                    return nil // Consume event
                }
                
                // Check for Control+Return (Rizz Mode)
                if event.flags.contains(.maskControl) && event.getIntegerValueField(.keyboardEventKeycode) == 36 { // 36 = Return
                    print("😎 [HotkeyManager] Control+Return detected (Rizz Mode)!")
                    
                    // Consume event IMMEDIATELY
                    DispatchQueue.main.async {
                        manager.onRizzTrigger?()
                    }
                    return nil // Return nil to block the event propagation
                }
                
                // Check for Cmd+Shift+K (Spotlight mode)
                let hasCmd = event.flags.contains(.maskCommand)
                let hasShift = event.flags.contains(.maskShift)
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                
                if hasCmd && hasShift && keyCode == 40 { // 40 = K
                    print("✨ [HotkeyManager] Cmd+Shift+K detected (Spotlight)!")
                    DispatchQueue.main.async {
                        manager.onSpotlightTrigger?()
                    }
                    return nil // Consume event
                }
                
                // Check for Shift+Esc (Privacy Mode Toggle)
                if event.flags.contains(.maskShift) && event.getIntegerValueField(.keyboardEventKeycode) == 53 { // 53 = Esc
                    print("🕵️‍♂️ [HotkeyManager] Shift+Esc detected (Privacy Mode)!")
                    DispatchQueue.main.async {
                        manager.onPrivacyModeTrigger?()
                    }
                    // Do NOT consume Shift+Esc as it might be used by system, 
                    // but for global toggle we usually want to. 
                    // Let's consume it to prevent accidental cancels.
                    return nil
                }
                
                // Check for Option+S (legacy suggestions - kept for compatibility)
                if event.flags.contains(.maskAlternate) && event.getIntegerValueField(.keyboardEventKeycode) == 1 { // 1 = S
                    print("⌨️ [HotkeyManager] Option+S detected!")
                    DispatchQueue.main.async {
                        manager.onTrigger?()
                    }
                    return nil // Consume event
                }
                
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("❌ [HotkeyManager] Failed to create event tap. Check Accessibility permissions.")
            return
        }
        
        self.eventTap = eventTap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        isListening = true
    }
    
    func stopListening() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        
        eventTap = nil
        runLoopSource = nil
        isListening = false
    }
}
