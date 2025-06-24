import SwiftUI
import AppKit

// Window controller to manage the overlay window with background processing capabilities
class OverlayWindowController: NSWindowController {
    private var backgroundTask: DispatchWorkItem?
    
    convenience init(contentView: NSView, size: CGSize) {
        let screenWidth = NSScreen.main?.frame.width ?? 300
        let screenHeight = NSScreen.main?.frame.height ?? 100
        let window = OverlayWindow(contentRect: NSRect(x: 0, y: 0, width: screenWidth, height: screenHeight))
        window.contentView = contentView
        self.init(window: window)
        
        window.setFrameOrigin(NSPoint(x: 0, y: 0))
        
        // Start background task to ensure window stays visible
        startBackgroundTask()
    }
    
    deinit {
        backgroundTask?.cancel()
    }
    
    override func showWindow(_ sender: Any?) {
        window?.orderFront(nil)
        
        // Ensure window stays visible across spaces and app switches
        if let window = window {
            NSApp.activate(ignoringOtherApps: true)
            window.orderFrontRegardless()
        }
    }
    
    private func startBackgroundTask() {
        // Cancel any existing task
        backgroundTask?.cancel()
        
        // Create a new background task
        let task = DispatchWorkItem { [weak self] in
            while !Thread.current.isCancelled {
                // Periodically ensure window is visible
                DispatchQueue.main.async {
                    if let window = self?.window {
                        window.orderFrontRegardless()
                    }
                }
                
                // Sleep for a short period
                Thread.sleep(forTimeInterval: 5.0)
            }
        }
        
        // Store the task and start it on a background queue
        self.backgroundTask = task
        DispatchQueue.global(qos: .background).async(execute: task)
    }
}
