import SwiftUI
import TrackdoKit

/// The optional sync server's URL and token. Settings are saved only after
/// the server accepted them; the banner at the top reports the outcome.
struct SettingsView: View {
    @Bindable var editor: SettingsEditor
    @FocusState private var focus: Field?
    @State private var savedURL: String?
    @State private var isConfirmingRemoval = false
    @State private var tokenWasEmpty = false

    private enum Field {
        case url
        case token
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sync server")
                        .dadsFont(.std24B150)
                        .foregroundStyle(DadsColor.gray900)
                        .accessibilityAddTraits(.isHeader)
                    Text("Optional. trackdo works on this device without a server. To use your tasks on other devices too, connect them all to your trackdo-server.")
                        .dadsFont(.std16N170)
                        .foregroundStyle(DadsColor.gray800)
                }
                banner
                urlField
                tokenField
                actions
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .background(DadsColor.white)
        .navigationTitle("Sync")
        .onChange(of: editor.url) { savedURL = nil }
        .onChange(of: editor.token) { savedURL = nil }
        .onChange(of: editor.issue) { _, issue in
            if let issue {
                AccessibilityNotification.Announcement(String(localized: issue.title)).post()
            }
        }
    }

    @ViewBuilder private var banner: some View {
        if let issue = editor.issue {
            DadsNotificationBanner(kind: .error, title: issue.title, description: issue.description)
        } else if let savedURL {
            DadsNotificationBanner(
                kind: .success,
                title: "Saved",
                description: "Your edits now sync through \(savedURL)."
            )
        }
    }

    private var urlField: some View {
        DadsInputText(
            label: "Server URL",
            isRequired: true,
            support: "For example https://sync.example.com. http:// works only for a server on this device or your local network.",
            error: editor.urlIssue?.message,
            isFocused: focus == .url
        ) {
            TextField("", text: $editor.url)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focus, equals: .url)
                .onSubmit { focus = .token }
        }
    }

    private var tokenField: some View {
        DadsInputText(
            label: "Token",
            isRequired: !editor.hasSavedToken,
            support: editor.hasSavedToken
                ? "A token is saved. Leave this empty to keep it, or enter a new one."
                : "One of the tokens set up on the server.",
            error: editor.tokenIssue?.message(tokenWasEmpty: tokenWasEmpty),
            isFocused: focus == .token
        ) {
            SecureField("", text: $editor.token)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focus, equals: .token)
                .onSubmit(save)
        }
    }

    /// Stacked for mobile: the primary action first.
    private var actions: some View {
        VStack(spacing: 16) {
            Button(action: save) {
                HStack(spacing: 4) {
                    if editor.isChecking {
                        // DADS shows partial progress with a still hourglass.
                        Image(systemName: "hourglass")
                            .accessibilityHidden(true)
                        Text("Checking the server…")
                    } else {
                        Text("Check and Save")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.dads(.solidFill))

            if editor.hasSavedToken {
                Button {
                    isConfirmingRemoval = true
                } label: {
                    Text("Remove Token").frame(maxWidth: .infinity)
                }
                .buttonStyle(.dads(.outline))
                .confirmationDialog("Remove the token?", isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
                    Button("Remove Token", role: .destructive) {
                        Task { await editor.removeToken() }
                    }
                } message: {
                    Text("Syncing stops until you enter a token again. Your edits stay on this device.")
                }
            }
        }
    }

    private func save() {
        focus = nil
        tokenWasEmpty = editor.token.isEmpty
        Task {
            if await editor.save() {
                savedURL = editor.url
            }
        }
    }
}
