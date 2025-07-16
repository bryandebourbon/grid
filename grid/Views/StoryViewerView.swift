import SwiftUI

struct StoryViewerView: View {
    @ObservedObject var viewModel: GridViewModel
    let deviceID: String
    @Environment(\.dismiss) var dismiss
    @State private var stories: [Story] = []
    @State private var isLoading = true
    
    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()
                .onTapGesture {
                    // Tap anywhere to close for now
                    dismiss()
                }
            
            // Simple centered close button for debugging
            VStack {
                HStack {
                    Spacer()
                    Button("✕ Close") {
                        print("StoryViewerView: Emergency close button tapped")
                        dismiss()
                    }
                    .font(.title)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(10)
                    .padding(.top, 50)
                    .padding(.trailing, 20)
                }
                
                Spacer()
                
                // Debugging info
                VStack(spacing: 10) {
                    Text("Story Viewer Debug")
                        .font(.title2)
                        .foregroundColor(.white)
                    
                    Text("Device ID: \(deviceID)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text("Stories loaded: \(stories.count)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text("Loading: \(isLoading ? "Yes" : "No")")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    
                    if !stories.isEmpty {
                        Text("First story ID: \(stories[0].id)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(10)
                
                Spacer()
            }
        }
        .navigationBarHidden(true)
        .statusBarHidden(true)
        .onAppear {
            print("StoryViewerView: onAppear called for deviceID: \(deviceID)")
            Task {
                await loadStories()
            }
        }
    }
    
    private func loadStories() async {
        print("StoryViewerView: Loading stories for deviceID: \(deviceID)")
        isLoading = true
        let result = await viewModel.getStoriesForDevice(deviceID)
        
        await MainActor.run {
            print("StoryViewerView: Fetched \(result.stories.count) stories for device \(deviceID)")
            self.stories = result.stories.sorted { $0.timestamp > $1.timestamp }
            self.isLoading = false
            
            if stories.isEmpty {
                print("StoryViewerView: No stories to display")
            } else {
                print("StoryViewerView: Stories loaded successfully")
            }
        }
    }
 
}


struct StoryViewerView_Previews: PreviewProvider {
    static var previews: some View {
        StoryViewerView(viewModel: GridViewModel(), deviceID: "sample-device")
    }
} 