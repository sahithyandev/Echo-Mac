//
//  AppNavigationState.swift
//  Echo
//
//  Created by Sahithyan Kandathasan on 2026-06-18.
//

import Foundation
import Combine

@MainActor
class AppNavigationState : ObservableObject {
    @Published var currentPage: Page = Page.home
}
