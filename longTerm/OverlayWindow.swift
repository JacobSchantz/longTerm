import SwiftUI
import AppKit

// Custom NSWindow subclass for creating a floating overlay
class OverlayWindow: NSWindow {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        // Configure window properties for overlay
        self.level = .floating + 1 // Higher level to ensure it stays on top
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = false // Prevent hiding when app is not active
    }
    
    // Prevent the window from becoming key window
    override var canBecomeKey: Bool {
        return true
    }
    
    // Prevent the window from becoming main window
    override var canBecomeMain: Bool {
        return true
    }
}

// Window controller to manage the overlay window
class OverlayWindowController: NSWindowController {
    convenience init(contentView: NSView, size: CGSize) {
        let screenWidth = NSScreen.main?.frame.width ?? 300
        let screenHeight = NSScreen.main?.frame.height ?? 100
        let window = OverlayWindow(contentRect: NSRect(x: 0, y: 0, width: screenWidth, height: screenHeight))
        window.contentView = contentView
        self.init(window: window)
        
        window.setFrameOrigin(NSPoint(x: 0, y: 0))
    }
    
    override func showWindow(_ sender: Any?) {
        window?.orderFront(nil) // Use orderFront instead of makeKeyAndOrderFront
        
        // Ensure window stays visible across spaces and app switches
        if let window = window {
            NSApp.activate(ignoringOtherApps: true)
            window.orderFrontRegardless()
        }
    }
}

// SwiftUI wrapper for the overlay window
struct OverlayWindowView: NSViewRepresentable {
    @Binding var isVisible: Bool
    var contentView: AnyView
    var size: CGSize
    
    // Coordinator to manage window controller state
    class Coordinator: NSObject {
        var windowController: OverlayWindowController?
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator()
    }
    
    func makeNSView(context: Context) -> NSView {
        let containerView = NSView()
        return containerView
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if isVisible && context.coordinator.windowController == nil {
            // Create and show the overlay window
            let hostingView = NSHostingView(rootView: contentView)
            context.coordinator.windowController = OverlayWindowController(contentView: hostingView, size: size)
            context.coordinator.windowController?.showWindow(nil)
        } else if !isVisible && context.coordinator.windowController != nil {
            // Hide the overlay window
            context.coordinator.windowController?.close()
            context.coordinator.windowController = nil
        }
    }
}

// Content view for the overlay
struct OverlayContentView: View {
    @EnvironmentObject var state: AppState
    
    var body: some View {
        let notOnTask = state.onTaskPercentage == 0
        VStack(alignment: .center) {
                        Spacer()

            HStack {
                Spacer()
                Text("On Task:")
                    .font(.system(size: 12, weight: .medium))
                Text("\(state.onTaskPercentage)%")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(state.onTaskPercentage >= 70 ? .green : .red)
                if state.isCheckingWithAI {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                }
            }
            Spacer()
            if let activity = state.selectedActivity {
                Text(activity.title)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
                        Spacer()
        }
        .background(
            Rectangle()
                .fill(notOnTask ? Color.red.opacity(0.1) : Color.black.opacity(0.1))
        )
        // Add subtle animation when changing colors
        .animation(.easeInOut(duration: 0.3), value: state.onTaskPercentage == 0)
    }
}

// Extension to AppState to manage overlay visibility
extension AppState {
//    func toggleOverlay() {
//        isOverlayVisible.toggle()
//        UserDefaults.standard.set(isOverlayVisible, forKey: "isOverlayVisible")
//    }
}
