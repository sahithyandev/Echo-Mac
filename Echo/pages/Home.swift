//
//  Home.swift
//  Echo
//
//  Created by Sahithyan Kandathasan on 2026-06-16.
//

import SwiftUI

struct Home: View {
    @StateObject private var viewModel = FileListViewModel()
    
    var body: some View {
        List(viewModel.files, id: \.self) { url in
            Text(url.lastPathComponent)
        }
        .onAppear {
            viewModel.loadFiles(at: URL(fileURLWithPath: "/Users/sahithyan/Music"))
        }
    }
}

#Preview {
    Home()
}
