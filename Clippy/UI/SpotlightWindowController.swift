import Cocoa
import SwiftUI
import SwiftData

// Custom panel that can become key window and accept keyboard input
class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        // Pass keyboard events to the content view
        super.keyDown(with: event)
    }
}

class SpotlightWindowController: NSWindowController {
    private var panel: KeyablePanel!
    private var hostingView: NSHostingView<AnyView>!
    private var container: AppDependencyContainer
    
    init(container: AppDependencyContainer) {
        self.container = container
        super.init(window: nil)
        setupPanel()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupPanel() {
        // Create a keyable panel that accepts keyboard input WITHOUT activating app
        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 600),
            styleMask: [.borderless, .fullSizeContentView, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        // Panel configuration for Spotlight-like behavior (appears over fullscreen apps!)
        // screenSaver level (1000) ensures it's above everything including fullscreen apps
        panel.level = .screenSaver
        panel.backgroundColor = NSColor.clear
        panel.isOpaque = false
        panel.hasShadow = false  // SwiftUI handles shadow
        // moveToActiveSpace: moves window to current space (including fullscreen spaces!)
        // fullScreenAuxiliary: can coexist with fullscreen apps
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .utilityWindow
        panel.isMovableByWindowBackground = true  // Make it draggable!
        panel.acceptsMouseMovedEvents = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        
        // Make window fully transparent - let SwiftUI handle all visuals
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        if let contentView = panel.contentView {
            contentView.wantsLayer = true
            contentView.layer?.backgroundColor = NSColor.clear.cgColor
            contentView.layer?.isOpaque = false
        }
        
        // Create SwiftUI view
        let spotlightView = AnyView(
            SpotlightView()
                .environmentObject(container)
        )
        
        hostingView = NSHostingView(rootView: spotlightView)
        hostingView.autoresizingMask = [.width, .height]
        
        panel.contentView = hostingView
        
        // Center panel on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.frame
            let panelFrame = panel.frame
            let x = screenFrame.midX - panelFrame.width / 2
            let y = screenFrame.midY - panelFrame.height / 2 + 100 // Slightly above center
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        
        // Monitor for Escape key to dismiss
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            
            if event.keyCode == 53 && self.panel.isVisible { // 53 = Escape key
                self.hide()
                return nil // Consume the event
            }
            
            return event
        }
        
        // Click outside to dismiss
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self else { return }
            
            if self.panel.isVisible {
                let mouseLocation = NSEvent.mouseLocation
                let panelFrame = self.panel.frame
                
                if !panelFrame.contains(mouseLocation) {
                    self.hide()
                }
            }
        }
        
        self.window = panel
    }
    
    func inject(modelContext: ModelContext) {
        print("💉 [SpotlightWindowController] Injecting ModelContext...")
        let spotlightView = AnyView(
            SpotlightView()
                .environmentObject(container)
                .modelContext(modelContext)
        )
        hostingView.rootView = spotlightView
    }
    
    // MARK: - Public Methods
    
    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }
    
    func show() {
        guard !panel.isVisible else { return }
        
        // Position on the CURRENT screen (works for fullscreen spaces too)
        if let currentScreen = NSScreen.main ?? NSScreen.screens.first {
            let screenFrame = currentScreen.visibleFrame
            let panelFrame = panel.frame
            let x = screenFrame.midX - panelFrame.width / 2
            let y = screenFrame.midY - panelFrame.height / 2 + 100
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        // Animate appearance
        panel.alphaValue = 0.0
        
        // Order front WITHOUT activating the app (prevents space switch!)
        panel.orderFrontRegardless()
        
        // Make key for keyboard input, but DON'T activate app
        panel.makeKey()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        } completionHandler: { [weak self] in
            guard let self = self else { return }
            // Force keyboard focus WITHOUT activating app (stays in fullscreen space)
            self.panel.makeKey()
            self.panel.makeFirstResponder(self.hostingView)
            print("✨ [SpotlightController] Window shown over fullscreen, keyboard ready")
        }
    }
    
    func showWithNudge(message: String) {
        // Show the window with a pre-filled nudge message
        print("🚨 [SpotlightController] Showing nudge: \(message)")
        
        // Notify the view to display nudge mode
        NotificationCenter.default.post(
            name: NSNotification.Name("ShowGuardianNudge"),
            object: nil,
            userInfo: ["message": message]
        )
        
        // Show the window
        show()
    }
    
    func hide() {
        guard panel.isVisible else { return }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
        })
    }
}

