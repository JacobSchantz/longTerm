import Foundation
import SwiftUI
import ScreenCaptureKit
import Vision
import AppKit

struct Activity: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var description: String
    
    init(title: String, description: String) {
        self.title = title
        self.description = description
        self.id = title == "Off the Rails" ? "default" : UUID().uuidString
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
    @Published var onTaskPercentage: Int = 0
    
    private var timer: Timer?
    private var statusItem: NSStatusItem?
    
    @Published var activities: [Activity] = []
    @Published var selectedActivityId: String?
    @Published var isEditing: Bool = false
    @Published var isCreatingNew: Bool = false
    @Published var newActivityTitle: String = ""
    @Published var newActivityDesc: String = ""
    
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
    let defaultActivities = [Activity(title: "Off the Rails", description: "Default no protection")]
    
    init() {
        if let data = UserDefaults.standard.data(forKey: activitiesKey),
           let decoded = try? JSONDecoder().decode([Activity].self, from: data) {
            activities = decoded + defaultActivities
        } else {
            activities = defaultActivities
        }
        selectedActivityId = activities.first?.id
        updateMenuBar(onTaskPercentage: 0.0)
    }
    
    func updateMenuBar(onTaskPercentage: Double) {
        let statusBar = NSStatusBar.system
        statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        let isOnTask = onTaskPercentage >= 70
        
        if let button = statusItem?.button {
            // Always show the percentage in the menu bar
            let percentageText = String(format: "%.0f%%", onTaskPercentage)
            
            // Create an attributed string with color based on on-task status
            let textColor = isOnTask ? NSColor.systemGreen : NSColor.systemRed
            let font = NSFont.systemFont(ofSize: 12, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: textColor,
                .font: font
            ]
            let attributedString = NSAttributedString(string: percentageText, attributes: attributes)
            
            // Set the title with the attributed string
            button.attributedTitle = attributedString
            
            // Remove any existing image
            button.image = nil
        }
        
        let menu = NSMenu()

        // First menu item shows status (checking or on-task percentage)
        if isCheckingWithAI {
            let checkingItem = NSMenuItem(title: "Checking with AI...", action: nil, keyEquivalent: "")
            checkingItem.isEnabled = false
            menu.addItem(checkingItem)
        } else {
            let statusItem = NSMenuItem(title: "On task: \(onTaskPercentage)%", action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            menu.addItem(statusItem)
        }
        
        // Add AI check action
        let checkWithAIItem = NSMenuItem(title: "Check with AI", action: #selector(checkWithAI), keyEquivalent: "")
        checkWithAIItem.target = self
        menu.addItem(checkWithAIItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }
    
    @objc func openApp() {
        NSApp.activate(ignoringOtherApps: true)
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
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
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
        
        // Set checking state on the main thread
        self.isCheckingWithAI = true
        
        // Update the menu bar to show checking indicator
        updateMenuBar(onTaskPercentage: Double(self.onTaskPercentage))
        
        if let currentActivity = activities.first(where: { $0.id == selectedActivityId }) {
            // If the activity is the default "Off the Rails" (id = "default"), always return 100%
            if currentActivity.id == "default" {
                self.aiResponse = "You're on the default activity 'Off the Rails', so you're always 100% on task."
                self.errorMessage = ""
                self.onTaskPercentage = 100
                updateMenuBar(onTaskPercentage: 100.0)
                self.isCheckingWithAI = false
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
                        self.onTaskPercentage = percentage
                        
                        updateMenuBar(onTaskPercentage: Double(percentage))
                        
                        // Set the checking indicator back to false after completing the AI check
                        self.isCheckingWithAI = false
                    }
                } catch {
                    await MainActor.run {
                        self.aiResponse = ""
                        self.errorMessage = error.localizedDescription
                        
                        // Set the checking indicator back to false if there's an error
                        self.isCheckingWithAI = false
                    }
                }
            }
            self.isCheckingWithAI = false
        }
    }
    
    func saveActivities() {
        let toSave = activities.filter { $0.title != "Off the Rails" }
        if let data = try? JSONEncoder().encode(toSave) {
            UserDefaults.standard.set(data, forKey: activitiesKey)
        }
    }
    
    func createActivity() {
        if !newActivityTitle.isEmpty && !activities.contains(where: { $0.title == newActivityTitle }) {
            let newActivity = Activity(title: newActivityTitle, description: newActivityDesc)
            activities.append(newActivity)
            selectedActivityId = newActivity.id
            newActivityTitle = ""
            newActivityDesc = ""
            isCreatingNew = false
            saveActivities()
        }
    }
    
    func deleteActivity(_ id: String?) {
        guard let activityId = id,
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
