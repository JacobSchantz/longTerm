import SwiftUI
import ScreenCaptureKit
import Vision
import Foundation
import CoreServices
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// UI code only. State logic is now in ActivityState.swift.

import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register for relaunch at login
        let launchAtLogin = true
        if launchAtLogin {
            if let bundleID = Bundle.main.bundleIdentifier {
                LSSharedFileListInsertItemURL(
                    LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeUnretainedValue(), nil).takeRetainedValue(),
                    kLSSharedFileListItemLast.takeUnretainedValue(),
                    nil,
                    nil,
                    NSURL.fileURL(withPath: Bundle.main.bundlePath) as CFURL,
                    [kLSSharedFileListItemHidden: false] as CFDictionary,
                    nil
                )
            }
        }
        
        // Prevent app from appearing in dock
        NSApp.setActivationPolicy(.accessory)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Prevent app from terminating when all windows are closed
        return false
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Perform cleanup if needed before termination
    }
}

@main
struct MainView: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        
        // Add an empty WindowGroup for the overlay
        WindowGroup(id: "overlay") { EmptyView() }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView().environmentObject(AppState())
    }
}

struct ContentView: View {
    @EnvironmentObject var state: AppState
    
    var body: some View {
        VStack {
            // Horizontal activity selector at the top
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 15) {
                    ForEach(state.activities) { activity in
                        ActivityItem(activity: activity)
                            .environmentObject(state)
                    }
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
            }
            .frame(height: 150)
            .padding(.horizontal, 8)
            
            // Display the on-task percentage with large text
            VStack(spacing: 0) {
                HStack {
                    Text("On-Task")
                        .font(.headline)
                        .textSelection(.enabled)
                    
                    // AI checking indicator
                    if state.isCheckingWithAI {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.7)
                            .padding(.leading, 4)
                    }
                }
                
                Text("\(state.onTaskPercentage)%")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(state.onTaskPercentage >= 70 ? .green : .red)
                    .textSelection(.enabled)
                    .opacity(state.isCheckingWithAI ? 0.5 : 1.0) // Dim the percentage when checking
            }
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(state.onTaskPercentage >= 70 ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal, 8)

            Text(state.statusMessage)
                .foregroundColor(state.isCapturing ? .green : .red)
                .textSelection(.enabled)
            
            if !state.apiUrl.isEmpty {
                Text("API Request URL: \(state.apiUrl)")
                    .font(.caption)
                    .padding()
                    .textSelection(.enabled)
            }
            if !state.errorMessage.isEmpty {
                Text("Error: \(state.errorMessage)")
                    .foregroundColor(.red)
                    .padding()
                    .textSelection(.enabled) // Makes error message copyable
            }
            
            // Side-by-side scrollable views for captured text and AI response
            HStack(spacing: 4) {
                // Left side: Captured text
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recognized Text:")
                        .font(.caption)
                        .padding(.bottom, 2)
                    
                    ScrollView {
                        Text(state.detectedText)
                            .textSelection(.enabled) // Makes text copyable
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(4)
                    }
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
                }
                .frame(maxWidth: .infinity)
                
                // Right side: AI response
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Response:")
                        .font(.caption)
                        .padding(.bottom, 2)
                    
                    ScrollView {
                        Text(state.aiResponse)
                            .textSelection(.enabled) // Makes text copyable
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(4)
                    }
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 150)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            
            // Control buttons at the bottom
            HStack {
                Button(state.isCapturing ? "Stop Capture" : "Start Capture") {
                    state.toggleCaptureOnPressed()
                }
                .padding(.horizontal, 8)
                
                Button("Ask AI") {
                    state.checkWithAI()
                }
                .padding(.horizontal, 8)
                
                Button(action: {
                    state.showInfoPopup = true
                }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 18))
                        .foregroundColor(.blue)
                }
                .padding(.horizontal, 4)
                
                Spacer()
                
                // Add Activity button at the bottom right
                Button("Add Activity") {
                    state.addActivity()
                }
                .padding(.horizontal, 8)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            
        }
        .frame(minWidth: 400, minHeight: 300)
        .background(
            // Invisible view to handle overlay window
            OverlayWindowView(isVisible: $state.isOverlayVisible, contentView: AnyView(OverlayContentView().environmentObject(state)), size: CGSize(width: 180, height: 80))
        )
        .alert("Off Task Alert", isPresented: $state.showZeroPercentAlert) {
            Button("OK") {
                state.showZeroPercentAlert = false
            }
        } message: {
            Text("You are completely off task! The AI detected 0% similarity to your selected activity.")
        }
        .sheet(isPresented: $state.showInfoPopup) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Activity Information")
                    .font(.title)
                    .bold()
                    .padding(.bottom, 8)
                
                VStack(alignment: .leading, spacing: 12) {
                    if let activity = state.selectedActivity {
                        Text("Current Activity: \(activity.title)")
                            .font(.headline)
                        
                        Text("Description: \(activity.description)")
                            .font(.body)
                        
                        Text("On-Task Percentage: \(state.onTaskPercentage)%")
                            .font(.body)
                            .foregroundColor(state.onTaskPercentage >= 70 ? .green : .red)
                        
                        Text("AI Source: \(state.useLocalAI ? "Local Ollama" : "External API")")
                            .font(.body)
                        
                        Text("Status: \(state.isCapturing ? "Capturing" : "Not Capturing")")
                            .font(.body)
                    } else {
                        Text("No activity selected")
                            .font(.headline)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                
                Spacer()
                
                HStack {
                    Spacer()
                    Button("Close") {
                        state.showInfoPopup = false
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
            .padding()
            .frame(width: 400, height: 400)
        }
    }
}


struct ActivityItem: View {
    let activity: Activity
    @EnvironmentObject var state: AppState

    var body: some View {
        let isSelected = state.selectedActivityId == activity.id
        VStack(alignment: .leading, spacing: 8) {
            // Activity title
            TextField("Title", text: Binding(
                get: { activity.title },
                set: { value in
                    var newActivity = activity
                    newActivity.title = value
                    state.updateActivity(activity: newActivity)
                }
            ))
            .font(.headline)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .padding(.horizontal, 4)
            // Activity description
            TextField("Description", text: Binding(
                get: { activity.description },
                set: { value in
                    var newActivity = activity
                    newActivity.description = value
                    state.updateActivity(activity: activity)
                }
            ))
            .font(.subheadline)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .padding(.horizontal, 4)
            
            Spacer()
            
            // Activity controls
            ActivityControlsView(
                activity: activity,
                isSelected: isSelected,
            )
        }
        .frame(maxWidth: .infinity)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            state.selectedActivityId = activity.id
        }
    }
}


struct DeleteButton: View {
    let activityId: String
    @EnvironmentObject var state: AppState
    
    var body: some View {
        Button(action: {
            state.deleteActivity(id: activityId)
        }) {
            Image(systemName: "trash")
                .font(.caption)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.red.opacity(0.8))
                .foregroundColor(.white)
                .cornerRadius(4)
        }
    }
}


struct ActivityControlsView: View {
    let activity: Activity
    let isSelected: Bool
    
    var body: some View {
        HStack {
            Spacer()
            if activity.title != "Off the Rails" {
                DeleteButton(activityId: activity.id)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }
}
