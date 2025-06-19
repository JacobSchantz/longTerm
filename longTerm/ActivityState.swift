import Foundation
import SwiftUI
import ScreenCaptureKit
import Vision

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

    
    func checkWithChatGPT() {
        if let currentActivity = activities.first(where: { $0.id == selectedActivityId }) {
            Task {
                do {
                    let response = try await Repo.sendTextToAI(detectedText, activityDescription: currentActivity.description, useGrok: false)
                    await MainActor.run {
                        self.aiResponse = response
                        self.errorMessage = ""
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
    
    func checkWithGrok() {
        if let currentActivity = activities.first(where: { $0.id == selectedActivityId }) {
            Task {
                do {
                    let response = try await Repo.sendTextToAI(detectedText, activityDescription: currentActivity.description, useGrok: true)
                    await MainActor.run {
                        self.aiResponse = response
                        self.errorMessage = ""
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
}
