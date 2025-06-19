import SwiftUI
import ScreenCaptureKit
import Vision
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif


class Repo {

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
    

    static let activitiesKey = "activities"
    
    static func deleteActivity(_ id: String) {
        var storedActivities = getActivityList()
        if let index = storedActivities.firstIndex(where: { $0.id == id }) {
            storedActivities.remove(at: index)
            putActivityList(list: storedActivities)
        }
    }
    
    static func putActivity(activity: Activity) {
        var temp = getActivityList()
        if let index = temp.firstIndex(where: { $0.id == activity.id }) {
            temp[index] = activity
        }
        putActivityList(list: temp)
    }

    static func putActivityList(list: [Activity]) {
        guard let data = try? JSONEncoder().encode(list) else {
            return
        }
        UserDefaults.standard.set(data, forKey: activitiesKey)
    }
    
    private static func getActivityList() -> [Activity] {
        if let data = UserDefaults.standard.data(forKey: activitiesKey),
           let decodedActivities = try? JSONDecoder().decode([Activity].self, from: data) {
            return decodedActivities
        }
        return []
    }

	static func sendTextToAI(_ text: String, activityDescription: String) async throws -> String {
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
        let lastApiUrl = """
        \(request.httpMethod ?? "POST") \(url.absoluteString)
        Headers: \(request.allHTTPHeaderFields ?? [:])
        Body: \(String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "")
        """

        let systemMessage1 = """
    You are helping a friend stay on task. They will provide information about what they're doing on their screen, and you should analyze it to determine what task they are actually working on. You will also be given the task they are supposed to be working on for comparison.
    """
        
        let systemMessage2 = """
        Please analyze the following screen text and respond with:
        1. The task the user is supposed to be working on.
        2. The task the user is actually working on based on the screen text.
        3. Whether the user is on task or not (respond with 'on task' or 'off task').
        Be concise and specific in your response.
        """

        let messages: [[String: String]] = [
            ["role": "system", "content": systemMessage1],
            ["role": "system", "content": systemMessage2],
            ["role": "user", "content": "Screen text: \(text)\nIntended task: \(activityDescription)"]
        ]
        let requestBody: [String: Any] = [
            "model": "gpt-4-turbo",
            "messages": messages,
            "stream": false,
            "temperature": 0.7
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        request.httpBody = jsonData
        
        do {
            print("Sending request to OpenAI API with model: gpt-4-turbo")
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
    
    static func sendTextToLocalAI(_ text: String, activityDescription: String) async throws -> String {
        // Path to the Python script for local AI inference
        let scriptPath = "/Users/jakeschantz/Dropbox/Mac/Desktop/longTerm/longTerm/local_ai_inference.py"
        let process = Process()
        let pipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [scriptPath, text, activityDescription]
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            if process.terminationStatus == 0 {
                return output.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                throw NSError(domain: "", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Local AI script failed with error: \(output)"])
            }
        } else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to decode output from local AI script"])
        }
    }

	 static func getAPIKey() throws -> String {
    let fm = FileManager.default
    let devPath = "longTerm/longTerm/secrets.txt"
    let bundlePath = Bundle.main.path(forResource: "secrets", ofType: "txt")
    let fileURL: URL

    if fm.fileExists(atPath: devPath) {
        fileURL = URL(fileURLWithPath: devPath)
    } else if let bundlePath = bundlePath {
        fileURL = URL(fileURLWithPath: bundlePath)
    } else {
        throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "API key file not found"])
    }

    let apiKey = try String(contentsOf: fileURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    if apiKey.isEmpty {
        throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "API key file is empty"])
    }
    return apiKey
}
}
