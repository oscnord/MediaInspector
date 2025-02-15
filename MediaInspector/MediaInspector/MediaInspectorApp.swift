//
//  MediaInspectorApp.swift
//  MediaInspector
//
//  Created by Oscar Nord on 2025-02-15.
//

import SwiftUI

@main
struct mediainspectorApp: App {
    var body: some Scene {
        WindowGroup {
            MediaInspector()
        }
        .windowStyle(HiddenTitleBarWindowStyle())
    }
}
