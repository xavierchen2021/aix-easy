import Cocoa
import SwiftUI

class WelcomeWindow: NSPanel {
    init() {
        let contentView = WelcomeView()
        let hostingView = NSHostingView(rootView: contentView)
        
        let windowRect = NSRect(x: 0, y: 0, width: 500, height: 400)
        super.init(
            contentRect: windowRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.isMovableByWindowBackground = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        self.becomesKeyOnlyIfNeeded = false
        self.worksWhenModal = false
        self.acceptsMouseMovedEvents = true
        
        self.isOpaque = false
        self.backgroundColor = .clear
        self.contentView = hostingView
        
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        if let superview = hostingView.superview {
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: superview.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: superview.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: superview.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: superview.bottomAnchor)
            ])
        }
    }
    
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
}

struct WelcomeView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text(L10n.tr("welcome.title"))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.primary)
                
                Text(L10n.tr("welcome.subtitle"))
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "hand.tap", title: L10n.tr("welcome.quickActions"), description: L10n.tr("welcome.quickActionsDesc"))
                FeatureRow(icon: "window.shade.closed", title: L10n.tr("welcome.windowControl"), description: L10n.tr("welcome.windowControlDesc"))
                FeatureRow(icon: "note.text", title: L10n.tr("welcome.smartNotes"), description: L10n.tr("welcome.smartNotesDesc"))
                FeatureRow(icon: "doc.on.clipboard", title: L10n.tr("welcome.clipboardHistory"), description: L10n.tr("welcome.clipboardHistoryDesc"))
            }
            .padding(.horizontal, 20)
            
            Button(action: {
                NotificationCenter.default.post(name: Notification.Name("WelcomeWindowDismissed"), object: nil)
            }) {
                Text(L10n.tr("welcome.getStarted"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 20)
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
        )
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.blue)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}
