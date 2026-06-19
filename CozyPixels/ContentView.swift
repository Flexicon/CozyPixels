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
                HomeScreen()
            }
            .tabItem {
                Label("Home", systemImage: "square.grid.2x2")
            }

            NavigationStack {
                GalleryScreen()
            }
            .tabItem {
                Label("Gallery", systemImage: "photo.on.rectangle")
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Painting.self, inMemory: true)
}
