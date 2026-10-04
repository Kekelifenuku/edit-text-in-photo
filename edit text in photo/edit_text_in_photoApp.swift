//
//  edit_text_in_photoApp.swift
//  edit text in photo
//
//  Created by Fenuku kekeli on 9/26/26.
//

import SwiftUI

@main
struct edit_text_in_photoApp: App {
    init() {
        RevenueCatAccess.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(RevenueCatAccess.shared)
        }
    }
}
