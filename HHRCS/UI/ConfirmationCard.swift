import SwiftUI

struct ConfirmationCard: View {
    let title:        String
    var message:      String?  = nil
    let confirmLabel: String
    var cancelLabel:  String   = "CANCEL"
    var destructive:  Bool     = true
    let onConfirm:    () -> Void
    let onCancel:     () -> Void

    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ZStack {
            Color.black.opacity(0.30)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text(title)
                        .font(Theme.label(size: 11))
                        .foregroundStyle(Theme.text1)
                        .tracking(Theme.labelTracking)
                    if let msg = message {
                        Text(msg)
                            .font(Theme.body(size: 11))
                            .foregroundStyle(Theme.text3)
                    }
                }
                HStack(spacing: 0) {
                    Button { onCancel() } label: {
                        Text(cancelLabel)
                            .font(Theme.label(size: 11))
                            .tracking(Theme.labelTracking)
                            .foregroundStyle(Theme.text2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    Button { onConfirm() } label: {
                        Text(confirmLabel)
                            .font(Theme.label(size: 11))
                            .tracking(Theme.labelTracking)
                            .foregroundStyle(destructive ? Theme.danger : settings.activeColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .background(Theme.surface)
            .cornerRadius(Theme.cardRadius)
            .padding(.horizontal, 32)
        }
    }
}
