//
//  UserAvatarView.swift
//  ScriptureScribe
//
//  Circular avatar used throughout the Community tab.
//  Shows the user's profile photo if available;
//  otherwise falls back to their initial letter on a tinted circle.
//

import SwiftUI

struct UserAvatarView: View {

    let displayName: String
    let photoURL:    String?
    let size:        CGFloat

    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        if let urlString = photoURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    letterCircle
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            letterCircle
        }
    }

    private var letterCircle: some View {
        Circle()
            .fill(themeManager.currentTheme.primary.opacity(0.2))
            .frame(width: size, height: size)
            .overlay(
                Text(displayName.prefix(1).uppercased())
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(themeManager.currentTheme.primary)
            )
    }
}
