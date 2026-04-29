import Combine
import Foundation
import SwiftUI

@MainActor
final class ToastCenter: ObservableObject {
    @Published var message: String?
    @Published var icon: String = "checkmark.circle.fill"
    private var task: Task<Void, Never>?

    func show(_ message: String, icon: String = "checkmark.circle.fill", duration: TimeInterval = 2) {
        self.message = message
        self.icon = icon
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }
}

struct ToastView: View {
    @ObservedObject var toast: ToastCenter

    var body: some View {
        if let message = toast.message {
            HStack(spacing: 8) {
                Image(systemName: toast.icon)
                Text(message)
                    .font(.callout)
                    .lineLimit(2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThickMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.secondary.opacity(0.2), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
