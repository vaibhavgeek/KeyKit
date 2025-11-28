//
//  HomeScreen.swift
//  KeyboardKit
//
//  Created by Daniel Saidi on 2021-02-11.
//  Copyright © 2021-2025 Daniel Saidi. All rights reserved.
//

import KeyboardKit
import SwiftUI

/// This is the main demo app screen.
///
/// This view uses a KeyboardKit Pro `HomeScreen` to present
/// keyboard status and settings links with some adjustments.
///
/// See ``DemoApp`` for important, demo-specific information
/// on why the in-app keyboard settings aren't synced to the
/// keyboards by default, and how you can enable this.
struct HomeScreen: View {

    let app = KeyboardApp.keyboardKitDemo

    @State var text = ""
    @State var textEmail = ""
    @State var textURL = ""
    @State var textWebSearch = ""

    @Environment(\.openURL) var openURL
    
    @EnvironmentObject var keyboardContext: KeyboardContext

    var body: some View {
              NavigationView {
                  Form {
                      Section {
                          Image(.icon)
                              .resizable()
                              .aspectRatio(contentMode: .fit)
                              .frame(width: 120, height: 120)
                              .cornerRadius(20)
                              .frame(maxWidth: .infinity)
                      }
                      .listRowBackground(Color.clear)
                      

                      Section("Text Fields") {
                          TextField("Plain Text", text: $text)
                              .keyboardType(.default)
                          TextField("Email", text: $textEmail)
                              .keyboardType(.emailAddress)
                          TextField("URL", text: $textURL)
                              .keyboardType(.URL)
                          TextField("Web Search", text: $textWebSearch)
                              .keyboardType(.webSearch)
                      }
                  }
                  .navigationTitle(app.name)
              }
              .navigationViewStyle(.stack)
          }
}
