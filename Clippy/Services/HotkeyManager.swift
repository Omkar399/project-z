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
    
    func startListening(
        onTrigger: @escaping () -> Void,
        onVisionTrigger: @escaping () -> Void,
        onTextCaptureTrigger: @escaping () -> Void,
        onVoiceCaptureTrigger: @escaping () -> Void,
        onSpotlightTrigger: @escaping () -> Void,
        onPrivacyModeTrigger: @escaping () -> Void
    ) {
        self.onTrigger = onTrigger
        self.onVisionTrigger = onVisionTrigger
        self.onTextCaptureTrigger = onTextCaptureTrigger
        self.onVoiceCaptureTrigger = onVoiceCaptureTrigger
        self.onSpotlightTrigger = onSpotlightTrigger
        self.onPrivacyModeTrigger = onPrivacyModeTrigger
        
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                
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
