//
//  ContentView.swift
//  CozyPixels
//
//  Created by Michał Repeć on 19/06/2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                HomePlaceholderView()
            }
            .tabItem {
                Label("Home", systemImage: "square.grid.2x2")
            }

            NavigationStack {
                GalleryPlaceholderView()
            }
            .tabItem {
                Label("Gallery", systemImage: "photo.on.rectangle")
            }
        }
    }
}

private struct HomePlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "No Paintings Yet",
            systemImage: "paintpalette",
            description: Text("Imported paintings will appear here.")
        )
        .navigationTitle("Home")
    }
}

private struct GalleryPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "Gallery Coming Soon",
            systemImage: "sparkles.rectangle.stack",
            description: Text("Bundled pixel art examples will appear here.")
        )
        .navigationTitle("Gallery")
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
