import SwiftUI

struct ConfirmationCard: View {
    let title:        String
    var message:      String?  = nil
    let confirmLabel: String
    var cancelLabel:  String   = "CANCEL"
    var destructive:  Bool     = true
    let onConfirm:    () -> Void
    let onCancel:     () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.30)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                        .tracking(Theme.labelTracking)
                    if let msg = message {
                        Text(msg)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(Theme.tertiary)
                    }
                }
                HStack(spacing: 0) {
                    Button { onCancel() } label: {
                        Text(cancelLabel)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .tracking(Theme.labelTracking)
                            .foregroundStyle(Theme.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    Button { onConfirm() } label: {
                        Text(confirmLabel)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .tracking(Theme.labelTracking)
                            .foregroundStyle(destructive ? Theme.recordingRed : Theme.accentColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .background(Theme.cardBackground)
            .cornerRadius(Theme.cardRadius)
            .padding(.horizontal, 32)
        }
    }
}
