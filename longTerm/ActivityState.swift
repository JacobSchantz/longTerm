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
    @Published var statusMessage: String = "Not capturing"
    @Published var isCapturing: Bool = false
    
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
        setupStatusItem()
    }
    
    func setupStatusItem() {
        let statusBar = NSStatusBar.system
        statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItemIcon(isOnTask: false) // Default to off task
        
        let menu = NSMenu()
        let askAIItem = NSMenuItem(title: "Ask AI", action: #selector(checkWithAI), keyEquivalent: "")
        askAIItem.target = self
        menu.addItem(askAIItem)
        menu.addItem(NSMenuItem.separator())
        let openAppItem = NSMenuItem(title: "Open App", action: #selector(openApp), keyEquivalent: "")
        openAppItem.target = self
        menu.addItem(openAppItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }
    
    @objc func openApp() {
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func updateStatusItemIcon(isOnTask: Bool) {
        if let button = statusItem?.button {
            let iconName = isOnTask ? "checkmark.circle.fill" : "xmark.circle.fill"
            if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: isOnTask ? "On Task" : "Off Task") {
                image.isTemplate = true
                button.image = image
                button.imageScaling = .scaleProportionallyDown
            } else {
                button.title = isOnTask ? "On Task" : "Off Task"
            }
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
            DispatchQueue.main.async { [weak self] in
                self?.detectedText = text
                self?.statusMessage = "Last capture: \(Date().formatted(date: .omitted, time: .standard))"
            }
        }
    }

    
    @objc func checkWithAI() {
        if let currentActivity = activities.first(where: { $0.id == selectedActivityId }) {
            Task {
                do {
                    // Switch between local and external AI based on a configuration
                    // For now, we'll default to external AI. Change to true for local AI.
                    let useLocalAI = true;
                    let response = try await useLocalAI ? Repo.sendTextToLocalAI(detectedText, activityDescription: currentActivity.description) : Repo.sendTextToAI(detectedText, activityDescription: currentActivity.description)
                    await MainActor.run {
                        self.aiResponse = response
                        self.errorMessage = ""
                        let responseLower = response.lowercased()
                        let responseWithoutPunctuation = responseLower.trimmingCharacters(in: .punctuationCharacters)
                        let isOnTask = responseWithoutPunctuation.hasSuffix("on task")
                        updateStatusItemIcon(isOnTask: isOnTask)
                    }
                } catch {
                    await MainActor.run {
                        self.aiResponse = ""
                        self.errorMessage = error.localizedDescription
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
