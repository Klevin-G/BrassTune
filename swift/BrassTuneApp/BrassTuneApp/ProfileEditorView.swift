import PhotosUI
import SwiftUI
import UIKit
import ImageIO

/// Account-profile editing deliberately keeps the avatar independent of the
/// required name fields: an image-service outage must never strand a person
/// who has otherwise finished creating an account.
struct ProfileEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let requiresCompletion: Bool

    @State private var username: String
    @State private var displayName: String
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var localAvatar: UIImage?
    @State private var stagedAvatarData: Data?
    @State private var avatarRemovalRequested = false
    @State private var errorMessage: String?
    @State private var saveSucceeded = false
    @AccessibilityFocusState private var errorFocused: Bool

    init(requiresCompletion: Bool) {
        self.requiresCompletion = requiresCompletion
        _username = State(initialValue: "")
        _displayName = State(initialValue: "")
    }

    private var normalizedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var normalizedDisplayName: String {
        displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
    }

    /// Mirrors the server's public username contract before a profile save is
    /// attempted. The server remains authoritative, but a required setup sheet
    /// must not make people discover basic syntax errors through a generic 422.
    static func isValidUsername(_ value: String) -> Bool {
        let scalars = value.unicodeScalars
        guard (3...32).contains(scalars.count) else { return false }
        return scalars.allSatisfy { scalar in
            switch scalar.value {
            case 45, 48...57, 65...90, 95, 97...122:
                return true
            default:
                return false
            }
        }
    }

    static func isValidDisplayName(_ value: String) -> Bool {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        return !normalized.isEmpty && normalized.unicodeScalars.count <= 80
    }

    private var usernameIsValid: Bool {
        Self.isValidUsername(normalizedUsername)
    }

    private var displayNameIsValid: Bool {
        Self.isValidDisplayName(displayName)
    }

    private var canSave: Bool {
        usernameIsValid && displayNameIsValid && !model.profileOperationInProgress
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    avatarPicker
                } header: {
                    Text("Profile photo")
                } footer: {
                    Text("Optional. BrassTune re-encodes your selected photo before upload, so its original photo metadata is not sent.")
                }

                Section {
                    requiredNameField {
                        TextField("Username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityHint(Text(verbatim: NativeLocalization.string(
                                "Enter a username with 3–32 letters, numbers, underscores, or hyphens."
                            )))
                            .accessibilityIdentifier("profile.username")
                    }
                    requiredNameField {
                        TextField("Display name", text: $displayName)
                            .textContentType(.name)
                            .accessibilityHint(Text(verbatim: NativeLocalization.string(
                                "Enter a display name of 80 characters or fewer to save your profile."
                            )))
                            .accessibilityIdentifier("profile.displayName")
                    }
                } header: {
                    Text("Your name")
                }

                if !normalizedUsername.isEmpty && !usernameIsValid {
                    Section {
                        Label {
                            Text("Enter a username with 3–32 letters, numbers, underscores, or hyphens.")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .foregroundStyle(BTTheme.danger)
                        .accessibilityIdentifier("profile.usernameValidation")
                    }
                }

                if normalizedDisplayName.unicodeScalars.count > 80 {
                    Section {
                        Label {
                            Text("Enter a display name of 80 characters or fewer to save your profile.")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .foregroundStyle(BTTheme.danger)
                        .accessibilityIdentifier("profile.displayNameValidation")
                    }
                }

                if let errorMessage {
                    Section {
                        Label {
                            Text(verbatim: errorMessage)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                            .foregroundStyle(BTTheme.danger)
                            .accessibilityElement(children: .combine)
                            .accessibilityFocused($errorFocused)
                            .accessibilityIdentifier("profile.error")
                    }
                }

                if model.profileOperationInProgress {
                    Section {
                        ProgressView("Saving profile…")
                            .accessibilityIdentifier("profile.loading")
                    }
                }

                if requiresCompletion {
                    Section {
                        if model.profileRefreshUnavailable {
                            Text(verbatim: NativeLocalization.string(
                                "Your sign-in session is still active, but your BrassTune profile is temporarily unavailable. Retry or sign out."
                            ))
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Retry profile") {
                                Task {
                                    guard await model.refreshCurrentProfile() else { return }
                                    if model.userProfile?.profileComplete == true {
                                        model.completeRequiredProfile()
                                    }
                                }
                            }
                            .disabled(model.profileOperationInProgress)
                            .accessibilityIdentifier("profile.retry")
                        }

                        Button("Sign out", role: .destructive) {
                            Task { await model.signOut() }
                        }
                        .disabled(model.profileOperationInProgress)
                        .accessibilityIdentifier("profile.signOutRecovery")
                    } header: {
                        Text("Profile")
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !requiresCompletion {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .accessibilityIdentifier("profile.cancel")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveProfile() }
                        .disabled(!canSave)
                        .accessibilityIdentifier("profile.save")
                }
            }
        }
        .accessibilityIdentifier("screen.profileEditor")
        .task { populateFromCurrentProfile() }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task { await prepareSelectedAvatar(item) }
        }
        .onChange(of: errorMessage) { _, value in
            errorFocused = value != nil
        }
        .onChange(of: model.userProfile) { _, _ in
            guard !saveSucceeded else { return }
            populateFromCurrentProfile()
        }
    }

    @ViewBuilder
    private var avatarPicker: some View {
        HStack(spacing: BTSpacing.lg) {
            avatarImage
                .frame(width: 72, height: 72)
                .clipShape(Circle())
                .overlay(Circle().stroke(BTTheme.panelLine, lineWidth: 1))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BTSpacing.sm) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Choose photo", systemImage: "photo")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(BTSecondaryButtonStyle())
                .disabled(model.profileOperationInProgress)
                .accessibilityHint("Selects an optional profile photo")
                .accessibilityIdentifier("profile.choosePhoto")

                if localAvatar != nil || model.profileAvatarData != nil {
                    Button(role: .destructive, action: removeAvatar) {
                        Label("Remove photo", systemImage: "trash")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.profileOperationInProgress)
                    .btMinimumInteractiveSize(alignment: .leading)
                    .accessibilityIdentifier("profile.removePhoto")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Profile photo")
    }

    @ViewBuilder
    private var avatarImage: some View {
        if let localAvatar {
            Image(uiImage: localAvatar).resizable().scaledToFill()
        } else if let data = model.profileAvatarData, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(BTTheme.muted)
        }
    }

    private func populateFromCurrentProfile() {
        guard let profile = model.userProfile else { return }
        if username.isEmpty { username = profile.username ?? "" }
        if displayName.isEmpty { displayName = profile.displayName ?? "" }
    }

    @ViewBuilder
    private func requiredNameField<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: BTSpacing.xs) {
            content()
            Image(systemName: "asterisk")
                .font(.caption.weight(.bold))
                .foregroundStyle(BTTheme.danger)
                .accessibilityHidden(true)
        }
    }

    private func prepareSelectedAvatar(_ item: PhotosPickerItem) async {
        do {
            guard let sourceData = try await item.loadTransferable(type: Data.self),
                  let sanitized = Self.prepareAvatarData(sourceData) else {
                errorMessage = localizedProfileSaveFailure
                return
            }
            errorMessage = nil
            localAvatar = UIImage(data: sanitized)
            stagedAvatarData = sanitized
            avatarRemovalRequested = false
        } catch is CancellationError {
        } catch {
            errorMessage = localizedProfileSaveFailure
        }
    }

    /// Bounds source bytes and image dimensions before creating a decoded
    /// bitmap, then lets ImageIO decode only a 1024px thumbnail. This avoids a
    /// brief full-resolution allocation for a panorama or high-megapixel photo.
    static func prepareAvatarData(_ sourceData: Data) -> Data? {
        // The backend's 5 MiB limit applies to the sanitized JPEG, not a
        // normal high-resolution HEIC/JPEG selected from Photos.
        let maxSourceBytes = 25 * 1_024 * 1_024
        // Keep an abuse ceiling but allow a normal 48MP iPhone photo. ImageIO
        // still produces only the 1024px thumbnail below, never a full UIImage.
        let maxSourceDimension = 12_000
        let maxSourcePixels = 100_000_000
        let outputDimension = 1_024

        guard !sourceData.isEmpty, sourceData.count <= maxSourceBytes,
              let source = CGImageSourceCreateWithData(sourceData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0,
              width <= maxSourceDimension, height <= maxSourceDimension,
              width <= maxSourcePixels / height else {
            return nil
        }

        let options: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: outputDimension,
            kCGImageSourceShouldCacheImmediately: false,
        ] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return nil
        }
        // A fresh JPEG encoding strips EXIF, GPS, filename, or Photos-library
        // metadata before upload. The decoded image is the bounded thumbnail.
        guard let jpeg = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.82),
              jpeg.count <= 5 * 1_024 * 1_024 else {
            return nil
        }
        return jpeg
    }

    private func removeAvatar() {
        localAvatar = nil
        selectedPhoto = nil
        stagedAvatarData = nil
        avatarRemovalRequested = true
    }

    private func saveProfile() {
        errorMessage = nil
        Task {
            let saved = await model.updateProfile(username: normalizedUsername, displayName: normalizedDisplayName)
            guard saved else {
                errorMessage = model.lastError?.localizedDescription ?? localizedProfileSaveFailure
                return
            }
            if let stagedAvatarData {
                guard await model.uploadProfileAvatar(stagedAvatarData) else {
                    errorMessage = localizedProfileSaveFailure
                    return
                }
                self.stagedAvatarData = nil
                localAvatar = nil
            } else if avatarRemovalRequested {
                guard await model.deleteProfileAvatar() else {
                    errorMessage = localizedProfileSaveFailure
                    return
                }
                avatarRemovalRequested = false
            }
            saveSucceeded = true
            if requiresCompletion {
                model.completeRequiredProfile()
            }
            if !requiresCompletion || !model.profileEditorRequired {
                dismiss()
            }
        }
    }

    private var localizedProfileSaveFailure: String {
        NativeLocalization.string(
            "BrassTune couldn't save your latest changes on this device. Keep the app open, export your data if needed, and try again."
        )
    }
}
