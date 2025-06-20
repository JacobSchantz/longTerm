import SwiftUI
import ScreenCaptureKit
import Vision
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// UI code only. State logic is now in ActivityState.swift.

@main
struct MainView: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(AppState())
        }
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
            // Activity selector at the top
            List {
                ForEach(state.activities) { activity in
                    ActivityTileView(activity: activity, isSelected: state.selectedActivityId == activity.id)
                        .environmentObject(state)
                }
            }
            .frame(height: 120)
            .padding(.horizontal, 8)
            
            // Display the on-task percentage with large text
            VStack(spacing: 0) {
                Text("On-Task")
                    .font(.headline)
                    .textSelection(.enabled)
                Text("\(state.onTaskPercentage)%")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(state.onTaskPercentage >= 70 ? .green : .red)
                    .textSelection(.enabled)
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
                
                Spacer()
                
                // Add Activity button at the bottom right
                Button("Add Activity") {
                    state.isCreatingNew = true
                    state.newActivityTitle = ""
                    state.newActivityDesc = ""
                }
                .padding(.horizontal, 8)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            
            // New activity form
            if state.isCreatingNew {
                VStack {
                    TextField("New Activity Title", text: $state.newActivityTitle)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.horizontal)
                    TextField("New Activity Description", text: $state.newActivityDesc)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.horizontal)
                    HStack {
                        Button("Cancel") {
                            state.isCreatingNew = false
                        }
                        .padding(.leading, 10)
                        Button("Create") {
                            state.createActivity()
                        }
                        .padding(.leading, 10)
                    }
                    .padding(.bottom, 10)
                }
                .padding(.horizontal)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .onAppear {
            state.checkPermissionOnAppear()
            state.updateMenuBar(onTaskPercentage: 0.0)
        }
    }
}

// ActivitySelectorView has been integrated directly into ContentView

struct ActivityTileView: View {
    let activity: Activity
    let isSelected: Bool
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(alignment: .center) {
            if isSelected {
                VStack(alignment: .leading) {
                    TextField("Title", text: Binding(
                        get: { activity.title },
                        set: { newTitle in
                            if let index = state.activities.firstIndex(where: { $0.id == activity.id }) {
                                state.activities[index].title = newTitle
                                state.saveActivities()
                            }
                        }
                    ))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(height: 30)
                    TextField("Description", text: Binding(
                        get: { activity.description },
                        set: { newDesc in
                            if let index = state.activities.firstIndex(where: { $0.id == activity.id }) {
                                state.activities[index].description = newDesc
                                state.saveActivities()
                            }
                        }
                    ))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(height: 30)
                }
            } else {
                VStack(alignment: .leading) {
                    Text(activity.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(activity.description)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { state.selectedActivityId == activity.id },
                set: { isOn in
                    if isOn {
                        state.selectedActivityId = activity.id
                    }
                }
            ))
            .labelsHidden()
            .padding(.trailing, 5)
            Button("Delete") {
                state.deleteActivity(activity.id)
            }
            .disabled(activity.title == "Off the Rails")
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(isSelected ? Color.blue.opacity(0.2) : Color.clear)
        .cornerRadius(8)
    }
}
