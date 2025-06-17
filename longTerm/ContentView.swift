import SwiftUI
import ScreenCaptureKit
import Vision
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@main
struct PeriodicScreenTextViewerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

struct ContentView: View {
    @StateObject private var textRecognizer = TextRecognizer()
    @State private var aiResponse: String = ""
    @State private var apiUrl: String = ""
    @State private var errorMessage: String = ""

    @State private var lastApiUrl: String = ""
// Reminder: Do not commit openai_api_key.txt to git. It is gitignored.
    func sendTextToAI(_ text: String, activityDescription: String) async throws -> String {
        let apiUrl = "https://api.openai.com/v1/chat/completions"
        let apiKey = try getAPIKey()
        let urlSession = URLSession.shared
        
        guard let url = URL(string: apiUrl) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL: \(apiUrl)"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        lastApiUrl = """
        \(request.httpMethod ?? "POST") \(url.absoluteString)
        Headers: \(request.allHTTPHeaderFields ?? [:])
        Body: \(String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "")
        """
        
        let systemMessage1 = """
    You are helping a friend stay on task. They will tell you what task they're working on and then they will provide information about what they're doing, and you should respond by telling them if it is on task or off task.
    """
        
        let systemMessage2 = """
    The task this user is working on is related to: \(activityDescription). Anything related to that should be considered on task, anything else should be considered off task.
    """
        
        let userMessage = """
    I am currently looking at: \(text)
    Is this on task or off task? Respond with 'on task' or 'off task'.
    """
        
        let requestBody: [String: Any] = [
            "model": "gpt-4-turbo",
            "messages": [
                ["role": "user", "content": "test message are you there?"]
            ]
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        request.httpBody = jsonData
        
        do {
            print("Sending request to OpenAI API with model: gpt-3.5-turbo-0125")
            let (data, response) = try await urlSession.data(for: request)
            print("Received response from OpenAI API")
            if let httpResponse = response as? HTTPURLResponse {
                print("Response status code: \(httpResponse.statusCode)")
                if httpResponse.statusCode == 200 {
                    if let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let choices = jsonResponse["choices"] as? [[String: Any]],
                       let firstChoice = choices.first,
                       let message = firstChoice["message"] as? [String: Any],
                       let content = message["content"] as? String {
                        print("Successfully parsed API response: \(content)")
                        return content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    } else {
                        print("Error: Invalid response format from API")
                        throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format from API"])
                    }
                } else {
                    // Log the error
                    if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        print("Error response data: \(errorData)")
                        if let error = errorData["error"] as? [String: Any],
                           let message = error["message"] as? String {
                            print("OpenAI endpoint error: \(message)")
                        } else {
                            print("OpenAI endpoint failed with status code: \(httpResponse.statusCode), but no specific error message found")
                        }
                    } else {
                        if let responseText = String(data: data, encoding: .utf8) {
                            print("Raw error response: \(responseText)")
                        } else {
                            print("Failed to decode response data as UTF-8")
                        }
                    }
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "OpenAI endpoint failed with status code: \(httpResponse.statusCode)"])
                }
            } else {
                print("Error: Unknown response type received")
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown response type from API"])
            }
        } catch {
            print("Error sending text to AI: \(error.localizedDescription)")
            if let nsError = error as NSError?, nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCannotFindHost {
                // Show the URL in the UI by throwing an error that includes it
                throw NSError(domain: nsError.domain, code: nsError.code, userInfo: [NSLocalizedDescriptionKey: "Cannot find host for URL: \(apiUrl)\nCopy this URL and try it in your browser or terminal."])
            }
            throw error
        }
    }
        
        func getAPIKey() throws -> String {
    // Reads the API key from a file that's gitignored and not committed to source control
    let fileURL = URL(fileURLWithPath: "longTerm/openai_api_key.txt")
    let apiKey = try String(contentsOf: fileURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    if apiKey.isEmpty {
        throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "API key file is empty"])
    }
    return apiKey
}       
        
        var body: some View {
            VStack {
                Text("Detected Screen Text")
                    .font(.title)
                    .padding()
                
                ScrollView {
                    Text(textRecognizer.detectedText)
                        .padding()
                }
                
                ActivitySelectorView()
                
                HStack {
                    Button(textRecognizer.isCapturing ? "Stop Capture" : "Start Capture") {
                        if textRecognizer.isCapturing {
                            textRecognizer.stopCapture()
                        } else {
                            textRecognizer.startCapture()
                        }
                    }
                    .padding()
                    
                    Button("Check with AI") {
                    if let currentActivity = ActivityManager.shared.currentActivity {
                        Task {
                            do {
                                let response = try await sendTextToAI(textRecognizer.detectedText, activityDescription: currentActivity.description)
                                aiResponse = response
                                errorMessage = ""
                            } catch {
                                aiResponse = ""
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                }
                if !lastApiUrl.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Full API Request URL:")
                            .font(.caption)
                        Text(lastApiUrl)
                            .font(.caption)
                            .textSelection(.enabled)
                            .foregroundColor(.blue)
                            .padding(4)
                            .background(.green)
                            .cornerRadius(4)
                    }
                    .padding(.top)
                }
                }
                .padding()
                
                Text(textRecognizer.statusMessage)
                    .foregroundColor(textRecognizer.isCapturing ? .green : .red)
                
                if !apiUrl.isEmpty {
                    Text("API Request URL: \(apiUrl)")
                        .font(.caption)
                        .padding()
                }
                
                if !errorMessage.isEmpty {
                    Text("Error: \(errorMessage)")
                        .foregroundColor(.red)
                        .padding()
                        .textSelection(.enabled) // Makes error message copyable
                }
                
                Text("AI Response: \(aiResponse)")
                    .padding()
            }
            .frame(minWidth: 400, minHeight: 300)
            .onAppear {
                textRecognizer.checkPermission()
            }
        }
}

struct ActivitySelectorView: View {
    @State private var selectedActivity: String?
    @State private var activities: [Activity] = []
    @State private var isEditing: Bool = false
    @State private var isCreatingNew: Bool = false
    @State private var newActivityTitle: String = ""
    @State private var newActivityDesc: String = ""
    
    private let activitiesKey = "savedActivities"
    private let defaultActivities = [Activity(title: "Off the Rails", description: "Default no protection")]
    
    init() {
        if let data = UserDefaults.standard.data(forKey: activitiesKey),
           let savedActivities = try? JSONDecoder().decode([Activity].self, from: data) {
            var mergedActivities = defaultActivities
            for activity in savedActivities {
                if activity.title != "Off the Rails" {
                    mergedActivities.append(activity)
                }
            }
            _activities = State(initialValue: mergedActivities)
            _selectedActivity = State(initialValue: mergedActivities.first?.id)
            if let initialActivity = mergedActivities.first {
                ActivityManager.shared.currentActivity = initialActivity
            }
        } else {
            _activities = State(initialValue: defaultActivities)
            _selectedActivity = State(initialValue: defaultActivities.first?.id)
            if let initialActivity = defaultActivities.first {
                ActivityManager.shared.currentActivity = initialActivity
            }
        }
    }
    
    private func saveActivities() {
        let activitiesToSave = activities.filter { $0.title != "Off the Rails" }
        if let data = try? JSONEncoder().encode(activitiesToSave) {
            UserDefaults.standard.set(data, forKey: activitiesKey)
        }
    }
    
    private func deleteActivity() {
        if let selectedId = selectedActivity,
           let index = activities.firstIndex(where: { $0.id == selectedId && $0.title != "Off the Rails" }) {
            activities.remove(at: index)
            if let firstActivity = activities.first {
                selectedActivity = firstActivity.id
                ActivityManager.shared.currentActivity = firstActivity
            } else {
                selectedActivity = nil
                ActivityManager.shared.currentActivity = nil
            }
            saveActivities()
        }
    }
    
    var body: some View {
        // Activity Selection and Editing
        VStack {
            HStack {
                Text("Select Activity:")
                    .font(.headline)
                Picker("Activity", selection: $selectedActivity) {
                    ForEach(activities) { activity in
                        Text(activity.title).tag(activity.id as String?)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .onChange(of: selectedActivity) { newValue in
                    if let newId = newValue,
                       let newActivity = activities.first(where: { $0.id == newId }) {
                        ActivityManager.shared.currentActivity = newActivity
                    }
                }
                
                Button(isEditing ? "Save" : "Edit") {
                    isEditing.toggle()
                    if !isEditing {
                        saveActivities()
                        if let currentId = selectedActivity,
                           let currentActivity = activities.first(where: { $0.id == currentId }) {
                            ActivityManager.shared.currentActivity = currentActivity
                        }
                    }
                }
                .padding(.leading, 10)
                
                Button("New") {
                    isCreatingNew = true
                    newActivityTitle = ""
                    newActivityDesc = ""
                }
                .padding(.leading, 10)
                
                Button("Delete") {
                    deleteActivity()
                }
                .padding(.leading, 10)
                .disabled(selectedActivity == activities.first(where: { $0.title == "Off the Rails" })?.id)
            }
            .padding(.top, 10)
            
            if isEditing {
                if let selectedId = selectedActivity,
                   let activity = activities.first(where: { $0.id == selectedId }) {
                    if activity.title == "Off the Rails" {
                        Text("This activity cannot be edited.")
                            .foregroundColor(.red)
                            .padding(.horizontal)
                            .padding(.bottom, 10)
                    } else {
                        if let index = activities.firstIndex(where: { $0.id == selectedId }) {
                            TextField("Activity Title", text: Binding(
                                get: { activities[index].title },
                                set: { newTitle in activities[index].title = newTitle }
                            ))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding(.horizontal)
                            
                            TextField("Activity Description", text: Binding(
                                get: { activities[index].description },
                                set: { newDesc in activities[index].description = newDesc }
                            ))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding(.horizontal)
                            .padding(.bottom, 10)
                        }
                    }
                }
            } else if isCreatingNew {
                TextField("New Activity Title", text: $newActivityTitle)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                
                TextField("New Activity Description", text: $newActivityDesc)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                
                HStack {
                    Button("Cancel") {
                        isCreatingNew = false
                    }
                    .padding(.leading, 10)
                    
                    Button("Create") {
                        if !newActivityTitle.isEmpty && !activities.contains(where: { $0.title == newActivityTitle }) {
                            let newActivity = Activity(title: newActivityTitle, description: newActivityDesc)
                            activities.append(newActivity)
                            selectedActivity = newActivity.id
                            ActivityManager.shared.currentActivity = newActivity
                            isCreatingNew = false
                            saveActivities()
                        }
                    }
                    .padding(.leading, 10)
                }
                .padding(.bottom, 10)
            } else {
                if let selectedId = selectedActivity,
                   let activity = activities.first(where: { $0.id == selectedId }) {
                    Text(activity.description)
                        .padding(.horizontal)
                        .padding(.bottom, 10)
                }
            }
        }
        .background(.gray)
        .cornerRadius(10)
        .padding()
    }
}

struct Activity: Identifiable, Codable {
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

class ActivityManager: ObservableObject {
    static let shared = ActivityManager()
    @Published var currentActivity: Activity?
    
    private init() {}
}

class TextRecognizer: ObservableObject {
    @Published var detectedText: String = "No text detected yet."
    @Published var statusMessage: String = "Not capturing"
    @Published var isCapturing: Bool = false
    
    private var timer: Timer?
    
    func checkPermission() {
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
    
    func startCapture() {
        guard !isCapturing else { return }
        
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.captureAndRecognizeText()
        }
        
        captureAndRecognizeText()
        
        isCapturing = true
        statusMessage = "Capturing every 5 seconds"
    }
    
    func stopCapture() {
        guard isCapturing else { return }
        
        timer?.invalidate()
        timer = nil
        isCapturing = false
        statusMessage = "Not capturing"
        detectedText = "No text detected yet."
    }
    
    func recognizeTextFromScreen() async -> String {
        do {
            // Get shareable content
            let content = try await SCShareableContent.current
            guard let display = content.displays.first else {
                return "No display available"
            }
            
            // Configure capture
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = 1920
            configuration.height = 1080
            
            // Capture a single screenshot
            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            
            // Create a new image-request handler
            let requestHandler = VNImageRequestHandler(cgImage: cgImage)
            
            // Create a new request to recognize text
            let request = VNRecognizeTextRequest { request, error in }
            request.recognitionLevel = .accurate
            
            // Perform the text-recognition request
            try requestHandler.perform([request])
            
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                return "No text detected"
            }
            
            let recognizedText = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }.joined(separator: "\n")
            
            return recognizedText.isEmpty ? "No text detected" : recognizedText
        } catch {
            return "Text recognition failed: \(error.localizedDescription)"
        }
    }
    
    private func captureAndRecognizeText() {
        Task {
            let text = await recognizeTextFromScreen()
            DispatchQueue.main.async { [weak self] in
                self?.detectedText = text
                self?.statusMessage = "Last capture: \(Date().formatted(date: .omitted, time: .standard))"
            }
        }
    }
}
