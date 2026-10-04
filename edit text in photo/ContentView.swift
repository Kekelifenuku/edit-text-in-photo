//
//  ContentView.swift
//  edit text in photo
//
//  Created by Fenuku kekeli on 9/26/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        PhotoPickerView()
    }
}

#Preview {
    ContentView()
        .environment(RevenueCatAccess.shared)
}
