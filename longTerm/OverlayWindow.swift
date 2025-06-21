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
        self.level = .floating
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]
        self.isReleasedWhenClosed = false
    }
    
    // Prevent the window from becoming key window
    override var canBecomeKey: Bool {
        return false
    }
    
    // Prevent the window from becoming main window
    override var canBecomeMain: Bool {
        return false
    }
}

// Window controller to manage the overlay window
class OverlayWindowController: NSWindowController {
    convenience init(contentView: NSView, size: CGSize) {
        let window = OverlayWindow(contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height))
        window.contentView = contentView
        self.init(window: window)
        
        // Position the window in the top-right corner
        if let screenFrame = NSScreen.main?.visibleFrame {
            let xPos = screenFrame.maxX - size.width - 20
            let yPos = screenFrame.maxY - size.height - 20
            window.setFrameOrigin(NSPoint(x: xPos, y: yPos))
        }
    }
    
    override func showWindow(_ sender: Any?) {
        window?.orderFront(nil) // Use orderFront instead of makeKeyAndOrderFront
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
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
            
            if let activity = state.selectedActivity {
                Text(activity.title)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
}

// Extension to AppState to manage overlay visibility
extension AppState {
//    func toggleOverlay() {
//        isOverlayVisible.toggle()
//        UserDefaults.standard.set(isOverlayVisible, forKey: "isOverlayVisible")
//    }
}
