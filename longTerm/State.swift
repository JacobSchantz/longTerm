import Foundation
import SwiftUI
import ScreenCaptureKit
import Vision
import AppKit
import Combine
import CoreAudio

struct Activity: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var description: String
    
    init(id: String, title: String, description: String) {
        self.title = title
        self.description = description
        self.id = id
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
    }
}

class AppState: ObservableObject {
    @Published var aiResponse: String = ""
    @Published var apiUrl: String = ""
    @Published var errorMessage: String = ""
    @Published var lastApiUrl: String = ""
    @Published var detectedText: String = "No text detected yet."
    @Published var useLocalAI: Bool = true // Default to using local AI (Ollama)
    @Published var statusMessage: String = "Not capturing"
    @Published var isCapturing: Bool = false
    @Published var isCheckingWithAI: Bool = false // Indicator for when AI check is in progress
    @Published var onTaskPercentage: Double = 0
    @Published var isOverlayVisible: Bool = true
    
    // Previous system volume before muting
    private var previousVolume: Float = 1.0
    // Flag to track if audio is currently muted
    private var isAudioMuted: Bool = false
    
    // Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    private var timer: Timer?
    private var statusItem: NSStatusItem?
    
    @Published var activities: [Activity] = []
    @Published var selectedActivityId: String?
    
    var selectedActivity: Activity? {
        get { activities.first(where: { $0.id == selectedActivityId }) }
        set {
            if let newValue = newValue {
                selectedActivityId = newValue.id
            } else {
                selectedActivityId = nil
            }
        }
    }
    let activitiesKey = "savedActivities"
    let defaultActivity = Activity(id: "default", title: "Off the Rails", description: "Default no protection")
    
    init() {
        // Load saved activities
        var tempActivities = [Activity]()
        if let data = UserDefaults.standard.data(forKey: activitiesKey),
           let savedActivities = try? JSONDecoder().decode([Activity].self, from: data) {
            tempActivities = savedActivities
        }
        
        if (!tempActivities.contains(where: { $0.id == "default" })) {
            tempActivities.append(defaultActivity)
        }

                    self.activities = tempActivities


        
        // Load overlay visibility preference
        // self.isOverlayVisible = UserDefaults.standard.bool(forKey: "isOverlayVisible")
        
        selectedActivityId = activities.first?.id
        updateMenuBar(onTaskPercentage: 0)
        
        // Store initial system volume
        previousVolume = getSystemVolume()
        
        // Setup app when launched
        setupAppOnLaunch()
        updateOverlayWindow()
        startCapture()
    }
    
    // Setup method to be called when app launches
    func setupAppOnLaunch() {
        // Check screen recording permission
        checkPermissionOnAppear()
        
        // Update menu bar with initial values
        updateMenuBar(onTaskPercentage: 0)
        
        // Setup notification observers
        setupNotificationObservers()
        
        // Setup overlay window
//        setupOverlayWindow()
    }

    func addActivity() {
        let newActivity = Activity(id: UUID().uuidString, title: "New Activity", description: "Description")
        activities.append(newActivity)
        saveActivities()
    }
    
    // Published property for zero percentage alert
    @Published var showZeroPercentAlert: Bool = false
    @Published var showInfoPopup: Bool = false
    
    // Setup notification observers
    func setupNotificationObservers() {
        // Add observer for on-task percentage changes
        $onTaskPercentage
            .receive(on: RunLoop.main)
            .sink { [weak self] newValue in
                guard let self = self else { return }
                if newValue == 0 && !self.isCheckingWithAI {
                    self.showZeroPercentAlert = true
                }
            }
            .store(in: &cancellables)
    }
    
    // Show info popup
    @objc func showInfo() {
        showInfoPopup = true
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: Notification.Name("ShowInfoPopup"), object: nil)
    }
    
    // Overlay window controller
    private var overlayWindowController: OverlayWindowController?
    
    // Method to update the overlay window based on state
    func updateOverlayWindow() {
        if isOverlayVisible {
            if overlayWindowController == nil {
                // Create the overlay content
                let hostingView = NSHostingView(rootView: OverlayContentView().environmentObject(self))
                
                // Create and show the overlay window
                overlayWindowController = OverlayWindowController(contentView: hostingView, size: CGSize(width: 180, height: 80))
                overlayWindowController?.showWindow(nil)
                
                // Register for workspace notifications to keep overlay visible
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(applicationActivated),
                    name: NSWorkspace.didActivateApplicationNotification,
                    object: nil
                )
                
                // Block audio when overlay is visible
                muteSystemAudio()
            } else {
                // Ensure window is still visible
                overlayWindowController?.showWindow(nil)
                
                // Ensure audio remains blocked
                muteSystemAudio()
            }
        } else {
            // Close and remove the overlay window
            overlayWindowController?.close()
            overlayWindowController = nil
            
            // Remove workspace notification observer
            NotificationCenter.default.removeObserver(
                self,
                name: NSWorkspace.didActivateApplicationNotification,
                object: nil
            )
            
            // Restore audio when overlay is hidden
            restoreSystemAudio()
        }
    }
    
    // Called when another application is activated
    @objc func applicationActivated(_ notification: Notification) {
        // Ensure our overlay stays on top when switching apps
        if overlayWindowController != nil {
            // Small delay to let the app switch complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.overlayWindowController?.showWindow(nil)
            }
        }
    }

    func updateActivity(activity: Activity) {
        if let index = activities.firstIndex(where: { $0.id == activity.id }) {
            activities[index] = activity
        }
        saveActivities()
    }
    
    func updateMenuBar(onTaskPercentage: Double) {
        // Create the status item only once if it doesn't exist
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }
        
        let isOnTask = onTaskPercentage >= 70
        
        if let button = statusItem?.button {
            // Always show the percentage in the menu bar
            let percentageText = String(format: "%.0f%%", onTaskPercentage)
            
            // Create an attributed string with color based on on-task status
            let textColor = isOnTask ? NSColor.systemGreen : NSColor.systemRed
            
            // Dim the text if AI is thinking
            let alpha: CGFloat = isCheckingWithAI ? 0.6 : 1.0
            let colorWithAlpha = textColor.withAlphaComponent(alpha)
            
            let font = NSFont.systemFont(ofSize: 12, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: colorWithAlpha,
                .font: font
            ]
            let attributedString = NSAttributedString(string: percentageText, attributes: attributes)
            
            // Set the title with the attributed string
            button.attributedTitle = attributedString
            
            // Add a thinking indicator if AI is checking
            if isCheckingWithAI {
                let image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "AI is thinking")
                image?.size = NSSize(width: 16, height: 16)
                button.image = image
                button.imagePosition = .imageLeading
            } else {
                button.image = nil
            }
        }
        
        let menu = NSMenu()

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }
    
    @objc func openApp() {
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func toggleOverlay() {
        // Toggle overlay visibility
        isOverlayVisible.toggle()
        
        // Save preference
        UserDefaults.standard.set(isOverlayVisible, forKey: "isOverlayVisible")
        
        // Update menu bar to reflect new state
        updateMenuBar(onTaskPercentage: Double(onTaskPercentage))
        
        // Update overlay window (which will handle audio blocking/restoring)
        updateOverlayWindow()
        
        // Notify about overlay toggle
        NotificationCenter.default.post(name: Notification.Name("OverlayToggled"), object: nil)
    }
    
    
    // Get the current system volume
    private func getSystemVolume() -> Float {
        var volume: Float = 1.0
        let command = "osascript -e 'output volume of (get volume settings)'" 
        
        if let output = try? shellCommand(command), let volumeValue = Float(output) {
            volume = volumeValue / 100.0 // Convert from percentage (0-100) to float (0.0-1.0)
        }
        
        return volume
    }
    
    // Execute shell command and return output
    private func shellCommand(_ command: String) throws -> String {
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        
        try task.run()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        return output
    }
    
    // Mute system audio when overlay is visible
    private func muteSystemAudio() {
            // Store current volume before muting
            previousVolume = getSystemVolume()
            
            // Set system volume to 0
            let command = "osascript -e 'set volume output volume 0'"
            try? shellCommand(command)
            
            isAudioMuted = true
            print("Audio muted. Previous volume: \(previousVolume)")
    }
    
    // Restore system audio when overlay is hidden
    private func restoreSystemAudio() {
        if isAudioMuted {
            // Convert back to percentage (0-100)
            let volumePercentage = Int(previousVolume * 100)
            
            // Restore previous system volume
            let command = "osascript -e 'set volume output volume \(volumePercentage)'"
            try? shellCommand(command)
            
            isAudioMuted = false
            print("Audio restored to previous volume: \(previousVolume)")
        }
    }
    
    func checkPermissionOnAppear() {
        Task {
            do {
                _ = try await SCShareableContent.current
                DispatchQueue.main.async { [weak self] in
                    self?.statusMessage = "Ready to capture"
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.statusMessage = "Screen recording permission denied. Please enable in System Settings."
                }
            }
        }
    }
    
    func toggleCaptureOnPressed() {
        if isCapturing {
            stopCapture()
        } else {
            startCapture()
        }
    }
    
    func startCapture() {
        guard !isCapturing else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 7.0, repeats: true) { [weak self] _ in
            self?.captureAndRecognizeText()
        }
        captureAndRecognizeText()
        isCapturing = true
        statusMessage = "Capturing..."
    }
    
    func stopCapture() {
        guard isCapturing else { return }
        timer?.invalidate()
        timer = nil
        isCapturing = false
        statusMessage = "Not capturing"
        detectedText = "No text detected yet."
    }
    
    private func captureAndRecognizeText() {
        Task {
            let text = await Repo().recognizeTextFromScreen()
            
            // Ensure all UI updates happen on the main thread
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                
                self.detectedText = text
                self.statusMessage = "Last capture: \(Date().formatted(date: .omitted, time: .standard))"
                
                // Automatically run checkWithAI if useLocalAI is true
                if self.useLocalAI {
                    // checkWithAI already has main thread check
                    self.checkWithAI()
                }
            }
        }
    }

    
    func extractPercentageFromResponse(_ response: String) -> Int {
        // Regular expression to find percentage patterns like "85%" or "85 percent" or "similarity is 85"
        let percentageRegex = try? NSRegularExpression(pattern: "(\\d+)\\s*%|\\b(\\d+)\\s*percent\\b|similarity\\s*(is|of)\\s*(\\d+)|\\b(\\d+)\\s*similarity", options: [.caseInsensitive])
        
        if let matches = percentageRegex?.matches(in: response, options: [], range: NSRange(response.startIndex..., in: response)), let match = matches.first {
            // Check each capture group for a valid number
            for i in 1..<match.numberOfRanges {
                if let range = Range(match.range(at: i), in: response), !range.isEmpty {
                    let captured = String(response[range])
                    if let percentage = Int(captured), percentage >= 0 && percentage <= 100 {
                        return percentage
                    }
                }
            }
        }
        
        // If no percentage is found, default to 0
        return 0
    }

    func updatePercentage(_ percentage: Double) {
        self.onTaskPercentage = percentage
        updateMenuBar(onTaskPercentage: percentage)
        self.isCheckingWithAI = false
        
        // Control audio based on task percentage
        if percentage == 0 {
            // User is off task and overlay is visible - mute audio
            muteSystemAudio()
        }
    }
    
    @objc func checkWithAI() {
        // Ensure we're on the main thread for all UI updates
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.checkWithAI()
            }
            return
        }
        
        // Prevent multiple simultaneous checks
        if isCheckingWithAI {
            return
        }

        if (detectedText.count <= 20) {
            self.errorMessage = ""
                            self.aiResponse = "No text detected. Must be off task!"
                updatePercentage(0.0)
                return;
        }

        
        // Set checking state on the main thread
        self.isCheckingWithAI = true
        
        // Update the menu bar to show checking indicator
        updateMenuBar(onTaskPercentage: Double(self.onTaskPercentage))
        
        if let currentActivity = activities.first(where: { $0.id == selectedActivityId }) {
            // If the activity is the default "Off the Rails" (id = "default"), always return 100%
            if currentActivity.id == "default" {
                self.aiResponse = "You're on the default activity 'Off the Rails', so you're always 100% on task."
                self.errorMessage = ""
                updatePercentage(100.0)
                return
            }
            
            Task {
                do {
                    // Use the class property to determine whether to use local or external AI
                    let response = try await self.useLocalAI ? Repo.sendTextToLocalAI(detectedText, activity: currentActivity) : Repo.sendTextToOnlineAI(detectedText, activityDescription: currentActivity.description)
                    await MainActor.run {
                        self.aiResponse = response
                        self.errorMessage = ""
                        
                        // Extract percentage from the response
                        let percentage = extractPercentageFromResponse(response)                        
                        updatePercentage(Double(percentage))
                    }
                } catch {
                    await MainActor.run {
                        self.aiResponse = ""
                        self.errorMessage = error.localizedDescription
                        updatePercentage(0.0)
                        
                        // Set the checking indicator back to false if there's an error
                        self.isCheckingWithAI = false
                    }
                }
            }
        }
    }
    
    func saveActivities() {
        let toSave = activities.filter { $0.title != "Off the Rails" }
        if let data = try? JSONEncoder().encode(toSave) {
            UserDefaults.standard.set(data, forKey: activitiesKey)
        }
    }
    
    func deleteActivity(id activityId: String?) {
        guard let activityId = activityId,
              let index = activities.firstIndex(where: { $0.id == activityId && $0.title != "Off the Rails" }) else {
            return
        }
        activities.remove(at: index)
        if selectedActivityId == activityId {
            selectedActivityId = activities.first?.id
        }
        saveActivities()
    }
    
    private func getSelectedActivity() -> Activity? {
        return activities.first(where: { $0.id == selectedActivityId })
    }
}
