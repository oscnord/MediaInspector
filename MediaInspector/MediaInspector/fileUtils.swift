//
//  fileUtils.swift
//  MediaInspector
//
//  Created by Oscar Nord on 2025-02-15.
//

import Foundation
import AppKit
import UniformTypeIdentifiers

func openFileDialog(completion: @escaping (String?) -> Void) {
    let dialog = NSOpenPanel()
    dialog.title = "Choose a media file"
    dialog.allowedContentTypes = [UTType.mpeg4Movie, UTType.quickTimeMovie, UTType.avi, UTType.mpeg, UTType.movie]
    dialog.allowsMultipleSelection = false
    dialog.canChooseFiles = true
    dialog.canChooseDirectories = false
    dialog.contentMinSize = NSSize(width: 800, height: 600)
    
    if dialog.runModal() == .OK, let url = dialog.url {
        completion(url.path)
    } else {
        completion(nil)
    }
}
