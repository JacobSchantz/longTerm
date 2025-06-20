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
            ActivitySelectorView()
            Text(state.statusMessage)
                .foregroundColor(state.isCapturing ? .green : .red)
            if !state.apiUrl.isEmpty {
                Text("API Request URL: \(state.apiUrl)")
                    .font(.caption)
                    .padding()
            }
            if !state.errorMessage.isEmpty {
                Text("Error: \(state.errorMessage)")
                    .foregroundColor(.red)
                    .padding()
                    .textSelection(.enabled) // Makes error message copyable
            }
            Text("Recognized Text: \(state.detectedText)")
                .padding()
                .textSelection(.enabled) // Makes recognized text copyable
            Text("AI Response: \(state.aiResponse)")
                .padding()
        }
        .frame(minWidth: 400, minHeight: 300)
        .onAppear {
            state.checkPermissionOnAppear()
            state.setupStatusItem()
        }
    }
}

struct ActivitySelectorView: View {
    @EnvironmentObject var state: AppState
    
    var body: some View {
        VStack {
            HStack {
                Button(state.isCapturing ? "Stop Capture" : "Start Capture") {
                    state.toggleCaptureOnPressed()
                }
                .padding()
                Button("Ask ChatGPT") {
                    state.checkWithAI()
                }
                .padding(.leading, 10)
                Button("New Activity") {
                    state.isCreatingNew = true
                    state.newActivityTitle = ""
                    state.newActivityDesc = ""
                }
                .padding(.leading, 10)
            }
            .padding(.top, 10)
            
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
            }
            
            List {
                ForEach(state.activities) { activity in
                    ActivityTileView(activity: activity, isSelected: state.selectedActivityId == activity.id)
                        .environmentObject(state)
                }
            }
            .padding(.horizontal)
        }
        .cornerRadius(10)
    }
}

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
