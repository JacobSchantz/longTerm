import SwiftUI
import ScreenCaptureKit
import Vision
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import CoreML

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

	static func sendTextToOnlineAI(_ text: String, activityDescription: String) async throws -> String {
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
            "temperature": 0.1
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
    
    static func sendTextToLocalAI(_ text: String, activity: Activity) async throws -> String {
        // Use Ollama API running on localhost
        let apiUrl = "http://localhost:11434/api/generate"
        let urlSession = URLSession.shared
        
        // Format the prompt for the model
        let prompt = """
        You are helping a friend stay on task. Analyze the screen text and determine if they are working on their intended task.
        
        Screen text: \(text)
        
        Intended task title: \(activity.title)
        Intended task description: \(activity.description)
        
        Please analyze the following screen text and respond with:
        1. The task the user is supposed to be working on.
        2. Your guess as to what the user is working on, based on the screen content
        3. Based on the first two answers, give me a percentage of how similar the two are.
        """
        
        // Create the request body
        let requestBody: [String: Any] = [
            "model": "llama3.2:latest", // Updated to use your 1B model
            "prompt": prompt,
            "stream": false,
            "temperature": 0.01
        ]
        
        // Convert the request body to JSON data
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to serialize request body"])
        }
        
        // Create the URL request
        var request = URLRequest(url: URL(string: apiUrl)!)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Send the request and get the response
        let (data, response) = try await urlSession.data(for: request)
        
        // Check the HTTP status code
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get a valid response from Ollama"])
        }
        
        // Parse the response
        guard let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseText = jsonResponse["response"] as? String else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse response from Ollama"])
        }

        return responseText
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
