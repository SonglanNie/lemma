import SwiftUI
import AppKit
import LemmaCore

/// Toasts at the bottom right and the notification center above the bell, as VS Code shows them.
struct NotificationsOverlay: View {
    @Bindable var store: StudyStore
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Spacer(minLength: 0)
            if store.showNotificationCenter {
                NotificationCenterView(store: store)
            } else {
                ForEach(store.visibleToasts.reversed()) { notification in
                    NotificationToast(store: store, notification: notification)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .padding(.trailing, 10).padding(.bottom, 8)
        .animation(.easeOut(duration: 0.18), value: store.visibleToasts.map(\.id))
        .animation(.easeOut(duration: 0.18), value: store.showNotificationCenter)
    }
}

private struct NotificationToast: View {
    @Bindable var store: StudyStore
    @Environment(\.theme) private var theme
    let notification: LemmaNotification

    var body: some View {
        NotificationRow(store: store, notification: notification, closeIcon: "close") { store.hideToast(notification.id) }
            .frame(width: 450)
            .background(RoundedRectangle(cornerRadius: 4).fill(theme[.notificationsBackground]))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.border(.notificationToastBorder), lineWidth: 1))
            .vsWidgetShadow(theme)
            .onHover { inside in
                if inside { store.hoveredToast = notification.id } else if store.hoveredToast == notification.id { store.hoveredToast = nil }
            }
    }
}

struct NotificationRow: View {
    @Bindable var store: StudyStore
    @Environment(\.theme) private var theme
    let notification: LemmaNotification
    var closeIcon = "close"
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Codicon(notification.severity.icon, size: 16).foregroundStyle(theme[notification.severity.color])
                Text(notification.message).font(.ui(13)).foregroundStyle(theme[.notificationsForeground])
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                Spacer(minLength: 4)
                VSIconButton(icon: closeIcon, help: "Clear Notification", size: 14, action: close)
            }
            if notification.progress != nil || !notification.actions.isEmpty {
                HStack(spacing: 8) {
                    Text("Source: \(notification.source)").font(.ui(12)).foregroundStyle(theme[.descriptionForeground])
                    Spacer(minLength: 6)
                    ForEach(Array(notification.actions.enumerated()), id: \.offset) { _, action in
                        Button(action.title) { action.perform(); close() }
                            .buttonStyle(VSButtonStyle(kind: action.primary ? .primary : .secondary, compact: true))
                    }
                }
            }
            if let progress = notification.progress { VSProgressLine(value: progress) }
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .accessibilityElement(children: .contain)
    }
}

private struct NotificationCenterView: View {
    @Bindable var store: StudyStore
    @Environment(\.theme) private var theme
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(store.notifications.isEmpty ? "NO NEW NOTIFICATIONS" : "NOTIFICATIONS").font(.ui(11)).foregroundStyle(theme[.notificationCenterHeaderForeground])
                Spacer()
                VSIconButton(icon: "clear-all", help: "Clear All Notifications", enabled: !store.notifications.isEmpty) { store.clearNotifications() }
                VSIconButton(icon: "chevron-down", help: "Hide Notifications") { store.showNotificationCenter = false }
            }
            .padding(.leading, 10).padding(.trailing, 6).frame(height: 35)
            .background(theme[.notificationCenterHeaderBackground])
            if !store.notifications.isEmpty {
                // As tall as its notifications, scrolling beyond 360 pt (a scroll view alone takes all the height offered).
                ScrollView {
                    rows.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(contentHeight, 360))
            }
        }
        .frame(width: 450)
        .background(RoundedRectangle(cornerRadius: 4).fill(theme[.notificationsBackground]))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.border(.notificationCenterBorder), lineWidth: 1))
        .vsWidgetShadow(theme)
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(store.notifications) { notification in
                NotificationRow(store: store, notification: notification) { store.dismissNotification(notification.id) }
                Rectangle().fill(theme.border(.notificationsBorder)).frame(height: 1)
            }
        }
    }
}
