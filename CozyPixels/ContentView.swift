//
//  ContentView.swift
//  CozyPixels
//
//  Created by Michał Repeć on 19/06/2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedTab = AppTab.home
    @State private var homePath = NavigationPath()

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $homePath) {
                HomeScreen()
                    .navigationDestination(for: Painting.self) { painting in
                        PaintingEditorScreen(painting: painting)
                    }
            }
            .tabItem {
                Label("Home", systemImage: "square.grid.2x2")
            }
            .tag(AppTab.home)

            NavigationStack {
                GalleryScreen { painting in
                    selectedTab = .home
                    homePath = NavigationPath()
                    homePath.append(painting)
                }
            }
            .tabItem {
                Label("Gallery", systemImage: "photo.on.rectangle")
            }
            .tag(AppTab.gallery)
        }
    }
}

private enum AppTab: Hashable {
    case home
    case gallery
}

#Preview {
    ContentView()
        .modelContainer(for: Painting.self, inMemory: true)
}
