import SwiftUI
import UIKit

struct PlayAlongIdleView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var moreWaysExpanded: Bool

    var body: some View {
        BTPageHeader(
            eyebrow: "Play-Along",
            title: "Today's recommendation",
            subtitle: "Start small, then choose another exercise when you want one."
        )
        .accessibilityIdentifier("playAlong.hero")

        BTCard(tint: BTTheme.surfaceWarm) {
            Label("Guided five-minute warm-up", systemImage: "timer")
                .font(.title3.weight(.bold))
                .foregroundStyle(BTTheme.text)
            Text("Five short steps for steady air, relaxed attacks, and centered notes.")
                .font(.subheadline)
                .foregroundStyle(BTTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text("5 minutes")
                .font(.caption.weight(.semibold))
                .foregroundStyle(BTTheme.accent)
        }
        .accessibilityIdentifier("playAlong.recommendation")

        VStack(alignment: .leading, spacing: BTSpacing.md) {
            Button {
                moreWaysExpanded.toggle()
            } label: {
                HStack(spacing: BTSpacing.sm) {
                    Label("More ways to practice", systemImage: "ellipsis.circle")
                        .font(.headline)
                    Spacer()
                    Image(systemName: moreWaysExpanded ? "chevron.up" : "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(BTTheme.text)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .btMinimumInteractiveSize()
            .accessibilityValue(moreWaysExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("More ways to practice")
            .accessibilityIdentifier("playAlong.moreWaysDisclosure")

            if moreWaysExpanded {
                Divider()
                PlayAlongMoreWaysView()
                    .transition(.opacity)
            }
        }
        .padding(BTSpacing.lg)
        .btContentSurface(tint: BTTheme.surface, interactive: true)
    }
}

struct PlayAlongWarmupButton: View {
    var body: some View {
        NavigationLink {
            GuidedWarmupView()
        } label: {
            Label("Start warm-up", systemImage: "play.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(BrassGlassButtonStyle(prominent: true, tint: BTTheme.accent))
        .accessibilityIdentifier("playAlong.startWarmup")
    }
}

private struct PlayAlongMoreWaysView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: BTSpacing.md) {
            NavigationLink {
                CustomExerciseBuilderView()
            } label: {
                Label("Create a Play-Along exercise", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(BTSecondaryButtonStyle())
            .accessibilityIdentifier("practice.quickStart.builder")

            NavigationLink {
                PracticePacksView()
            } label: {
                Label("Offline practice packs", systemImage: "shippingbox")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(BTSecondaryButtonStyle())
            .accessibilityIdentifier("practice.quickStart.packs")

            Divider()
            exercisePicker
            SelectedExerciseFavoriteButton()
            startSelectedExerciseButton

            Divider()
            PracticeShortcutSection(
                title: NativeLocalization.string("Favorites"),
                emptyMessage: NativeLocalization.string("Favorite an exercise to keep it close."),
                shortcuts: model.practiceFeatures.favorites
            )
            PracticeShortcutSection(
                title: NativeLocalization.string("Recent practice"),
                emptyMessage: NativeLocalization.string("Your recently started practice will appear here."),
                shortcuts: model.practiceFeatures.recents
            )

            if model.audioEngine.permissionDenied || model.lastError == .microphoneUnavailable {
                MicrophoneRecoveryCard()
            }
        }
    }

    private var exercisePicker: some View {
        VStack(alignment: .leading, spacing: BTSpacing.sm) {
            Picker("Exercise", selection: $model.selectedPlayAlongExerciseID) {
                ForEach(PlayAlongExerciseCategory.allCases) { category in
                    Section(category.title) {
                        ForEach(model.playAlongExercises.filter { $0.category == category }) { exercise in
                            Text(verbatim: exercise.displayTitle)
                                .tag(exercise.id)
                        }
                    }
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("playAlong.exercisePicker")

            Text(verbatim: model.selectedPlayAlongExercise.displayDetail)
                .font(.subheadline)
                .foregroundStyle(BTTheme.muted)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BTSpacing.sm) {
                    ForEach(Array(model.selectedPlayAlongExercise.writtenNotes.enumerated()), id: \.offset) { _, note in
                        Text(verbatim: note)
                            .font(.headline.monospaced())
                            .padding(.horizontal, BTSpacing.md)
                            .padding(.vertical, BTSpacing.sm)
                            .background(BTTheme.surfaceAlt, in: Capsule())
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
            }
            .accessibilityIdentifier("playAlong.exerciseNotes")
        }
    }

    private var startSelectedExerciseButton: some View {
        Button {
            Task {
                await model.startPlayAlong(exerciseID: model.selectedPlayAlongExerciseID)
            }
        } label: {
            Label {
                Text(verbatim: selectedExerciseButtonTitle)
            } icon: {
                Image(systemName: "mic.fill")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(BTSecondaryButtonStyle())
        .disabled(model.playAlongStartInProgress)
        .accessibilityIdentifier("playAlong.start")
    }

    private var selectedExerciseButtonTitle: String {
        if model.playAlongStartInProgress {
            return NativeLocalization.format(
                "Getting %@ ready…",
                model.selectedPlayAlongExercise.displayTitle
            )
        }
        return NativeLocalization.format(
            "Start %@",
            model.selectedPlayAlongExercise.displayTitle
        )
    }
}

private struct PracticeShortcutSection: View {
    @EnvironmentObject private var model: AppModel
    let title: String
    let emptyMessage: String
    let shortcuts: [PracticeShortcut]

    var body: some View {
        VStack(alignment: .leading, spacing: BTSpacing.sm) {
            Text(verbatim: title)
                .font(.headline)
            if shortcuts.isEmpty {
                Label {
                    Text(verbatim: emptyMessage)
                } icon: {
                    Image(systemName: "tray")
                }
                .font(.subheadline)
                .foregroundStyle(BTTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("practice.shortcuts.empty")
            } else {
                ForEach(shortcuts.prefix(3)) { shortcut in
                    shortcutDestination(shortcut)
                }
            }
        }
    }

    @ViewBuilder
    private func shortcutDestination(_ shortcut: PracticeShortcut) -> some View {
        switch shortcut.kind {
        case .playAlongExercise:
            Button {
                Task { _ = await model.launchShortcut(shortcut) }
            } label: {
                PracticeShortcutRow(shortcut: shortcut)
            }
            .buttonStyle(.plain)
        case .guidedWarmup:
            NavigationLink {
                GuidedWarmupView()
            } label: {
                PracticeShortcutRow(shortcut: shortcut)
            }
            .buttonStyle(.plain)
        case .practicePack:
            NavigationLink {
                PracticePacksView()
            } label: {
                PracticeShortcutRow(shortcut: shortcut)
            }
            .buttonStyle(.plain)
        case .drone:
            NavigationLink {
                DroneIntervalView()
            } label: {
                PracticeShortcutRow(shortcut: shortcut)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct PracticeShortcutRow: View {
    let shortcut: PracticeShortcut

    var body: some View {
        HStack(spacing: BTSpacing.md) {
            Image(systemName: systemImage)
                .foregroundStyle(BTTheme.accent)
                .frame(width: 28, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BTSpacing.xs) {
                Text(verbatim: shortcut.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BTTheme.text)
                if let date = shortcut.lastStartedAt {
                    Text(verbatim: date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(BTTheme.muted)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .contentShape(Rectangle())
        .frame(minHeight: 44)
    }

    private var systemImage: String {
        switch shortcut.kind {
        case .playAlongExercise: return "music.note.list"
        case .guidedWarmup: return "timer"
        case .practicePack: return "shippingbox"
        case .drone: return "waveform"
        }
    }
}

struct MicrophoneRecoveryCard: View {
    var body: some View {
        BTCard(tint: BTTheme.surfaceWarm) {
            Label("Microphone access is off", systemImage: "mic.slash.fill")
                .font(.headline)
                .foregroundStyle(BTTheme.warning)
            Text("Allow microphone access in iOS Settings, then retry. You can still use guided practice without listening.")
                .font(.subheadline)
                .foregroundStyle(BTTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("microphone.recovery")
    }
}

struct MicrophoneRecoveryActions: View {
    let retry: () -> Void

    var body: some View {
        VStack(spacing: BTSpacing.sm) {
            Button(action: openSettings) {
                Label("Open iOS Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BrassGlassButtonStyle(prominent: true, tint: BTTheme.accent))
            .accessibilityIdentifier("microphone.openSettings")

            Button(action: retry) {
                Label("Retry microphone", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BTSecondaryButtonStyle())
            .accessibilityIdentifier("microphone.retry")

            NavigationLink {
                GuidedWarmupView()
            } label: {
                Label("Practice without listening", systemImage: "timer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .btMinimumInteractiveSize()
            .accessibilityIdentifier("microphone.practiceWithoutListening")
        }
    }

    private func openSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(settingsURL)
    }
}

struct ProgressTabView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var selectedTab: AppTab

    var body: some View {
        let snapshot = model.analyticsSnapshot
        VStack(spacing: 0) {
            BTScreen {
                BTPageHeader(
                    eyebrow: "Progress",
                    title: "Practice momentum",
                    subtitle: "See what you did today, how this week is going, and what to try next."
                )

                ProgressTodaySection()

                ProgressGettingStartedSection()

                Text("This week")
                    .font(.title2.weight(.bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("progress.thisWeek")
                WeeklyGoalCard()

                ProgressNextStepSection()

                if progressShouldShowWarmupResume(model.currentWarmupCheckpoint) {
                    NavigationLink {
                        GuidedWarmupView()
                    } label: {
                        Label("Resume warm-up", systemImage: "play.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BTSecondaryButtonStyle())
                    .accessibilityIdentifier("progress.resumeWarmup")
                }

                Button {
                    selectedTab = .tuner
                } label: {
                    Label("Open Tuner", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BTPrimaryButtonStyle())
                .accessibilityIdentifier("progress.openTuner")

                if let _ = model.weakTransitionInsight {
                    WeakTransitionCard()
                }

                if snapshot.hasSessions {
                    ProgressTrendsSection(snapshot: snapshot)
                    ProgressHistorySection()
                }
            }
            .accessibilityIdentifier("screen.progress")
        }
        .background(BTTheme.background.ignoresSafeArea())
        .navigationTitle("Progress")
    }
}

func progressShouldShowWarmupResume(_ checkpoint: GuidedWarmupCheckpoint?) -> Bool {
    checkpoint?.completed == false
}

struct ProgressOnboardingMilestone: Equatable, Identifiable {
    let id: String
    let title: String
    let earned: Bool
}

@MainActor
func progressOnboardingMilestones(for model: AppModel) -> [ProgressOnboardingMilestone] {
    [
        ProgressOnboardingMilestone(
            id: "instrument",
            title: NativeLocalization.string("Choose your instrument"),
            earned: model.tutorialCompleted
        ),
        ProgressOnboardingMilestone(
            id: "first-note",
            title: NativeLocalization.string("Record your first note"),
            earned: model.sessions.contains { session in
                session.frames.contains { frame in
                    frame.isValidForRecording
                        && frame.frequencyHz != nil
                        && frame.writtenNoteName != nil
                }
            }
        ),
        ProgressOnboardingMilestone(
            id: "warmup",
            title: NativeLocalization.string("Warm-up complete"),
            earned: model.currentWarmupCheckpoint?.completed == true
        ),
        ProgressOnboardingMilestone(
            id: "play-along",
            title: NativeLocalization.string("Finish a Play-Along exercise"),
            earned: !model.practiceFeatures.playAlongAttempts.isEmpty
        ),
    ]
}

private struct ProgressGettingStartedSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let milestones = progressOnboardingMilestones(for: model)
        let earnedCount = milestones.filter(\.earned).count
        VStack(alignment: .leading, spacing: BTSpacing.sm) {
            Text("Getting started")
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("progress.gettingStarted")
            BTCard {
                Text(verbatim: NativeLocalization.format(
                    "%@ of %@ complete",
                    String(earnedCount),
                    String(milestones.count)
                ))
                    .font(.headline)
                    .foregroundStyle(earnedCount == milestones.count ? BTTheme.success : BTTheme.text)

                ForEach(milestones) { milestone in
                    Label {
                        Text(verbatim: milestone.title)
                    } icon: {
                        Image(systemName: milestone.earned ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(milestone.earned ? BTTheme.success : BTTheme.muted)
                    }
                    .accessibilityValue(milestone.earned
                        ? NativeLocalization.string("Done")
                        : NativeLocalization.string("Next step"))
                    .accessibilityIdentifier("progress.milestone.\(milestone.id)")
                }
            }
        }
    }
}

private struct ProgressTodaySection: View {
    @EnvironmentObject private var model: AppModel

    private var todaySessions: [PracticeSession] {
        model.sessions.filter { Calendar.current.isDateInToday($0.startedAt) }
    }

    private var todayMinutes: Int {
        Int((todaySessions.reduce(0) { $0 + $1.durationSeconds } / 60).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BTSpacing.sm) {
            Text("Today")
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            BTCard(tint: BTTheme.surfaceWarm) {
                Label {
                    Text(verbatim: NativeLocalization.string(
                        todaySessions.isEmpty ? "No practice saved today" : "Practice saved today"
                    ))
                } icon: {
                    Image(systemName: todaySessions.isEmpty ? "circle.dashed" : "checkmark.circle.fill")
                }
                .font(.headline)
                .foregroundStyle(todaySessions.isEmpty ? BTTheme.muted : BTTheme.success)
                Text(verbatim: todaySessions.isEmpty
                    ? NativeLocalization.string("One short session is enough to get moving.")
                    : NativeLocalization.format(
                        "%@ minutes · %@ sessions",
                        String(todayMinutes),
                        String(todaySessions.count)
                    ))
                    .font(.subheadline)
                    .foregroundStyle(BTTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("progress.today")
    }
}

private struct ProgressNextStepSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: BTSpacing.sm) {
            Text("Next step")
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            BTCard {
                Label("3-minute tuning check", systemImage: "tuningfork")
                    .font(.headline)
                Text(verbatim: model.analyticsSnapshot.hasSessions
                    ? model.analyticsSnapshot.recommendation
                    : NativeLocalization.string("Play one comfortable note, find the center, and save the result."))
                    .font(.subheadline)
                    .foregroundStyle(BTTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("progress.nextStep")
    }
}

private struct ProgressTrendsSection: View {
    let snapshot: AnalyticsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: BTSpacing.sm) {
            Text("Trends")
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 145), spacing: BTSpacing.md)],
                spacing: BTSpacing.md
            ) {
                BTMetricTile(
                    title: "In tune",
                    value: .verbatim(NativeLocalization.isolate("\(Int(snapshot.averageInTunePercentage.rounded()))%")),
                    detail: "within 5 cents",
                    tint: BTTheme.success
                )
                BTMetricTile(
                    title: "Average distance",
                    value: .verbatim(String(format: "%.1f", snapshot.averageAbsCents)),
                    detail: "cents from center",
                    tint: BTTheme.secondaryAccent
                )
                BTMetricTile(
                    title: "Practice time",
                    value: .verbatim(progressPracticeTimeLabel(snapshot.totalPracticeSeconds)),
                    detail: "saved"
                )
                BTMetricTile(
                    title: "Recordings",
                    value: .verbatim(NativeLocalization.isolate(String(snapshot.sessionCount))),
                    detail: "total"
                )
            }
            .accessibilityIdentifier("progress.metrics")
        }
    }
}

private struct ProgressHistorySection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        BTCard {
            HStack {
                BTSectionHeader(title: "Practice history", subtitle: "Your latest recordings.")
                Spacer()
                NavigationLink {
                    SessionsView()
                } label: {
                    Text("See all")
                        .font(.subheadline.weight(.semibold))
                }
                .accessibilityIdentifier("progress.allSessions")
            }

            ForEach(model.sessions.prefix(3)) { session in
                NavigationLink {
                    SessionDetailView(sessionID: session.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: BTSpacing.xs) {
                            Text(verbatim: session.name)
                                .font(.headline)
                            Text(verbatim: session.startedAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(BTTheme.muted)
                        }
                        Spacer()
                        Text(verbatim: NativeLocalization.isolate("\(Int(session.inTunePercentage.rounded()))%"))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(session.inTunePercentage >= 70 ? BTTheme.success : BTTheme.warning)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, BTSpacing.md)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct GuestProgressSafetyBanner: View {
    let createAccount: () -> Void
    let keepPracticing: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: BTSpacing.md) {
            Image(systemName: "checkmark.shield.fill")
                .font(.title3)
                .foregroundStyle(BTTheme.success)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BTSpacing.xs) {
                Text("Keep your progress safe")
                    .font(.headline)
                Text("Create a free account to back up practice and join Classes.")
                    .font(.footnote)
                    .foregroundStyle(BTTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: BTSpacing.md) {
                        actionButtons
                    }
                    VStack(alignment: .leading, spacing: BTSpacing.sm) {
                        actionButtons
                    }
                }
            }
        }
        .padding(BTSpacing.md)
        .frame(maxWidth: 620, alignment: .leading)
        .background(BTTheme.surfaceWarm)
        .clipShape(RoundedRectangle(cornerRadius: BTTheme.radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BTTheme.radius, style: .continuous)
                .stroke(BTTheme.success.opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("guest.progressSafetyPrompt")
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button("Create free account", action: createAccount)
            .buttonStyle(.borderedProminent)
            .tint(BTTheme.accent)
            .accessibilityIdentifier("guest.progressSafetyCreate")
        Button("Keep practicing", action: keepPracticing)
            .buttonStyle(.bordered)
            .accessibilityIdentifier("guest.progressSafetyDismiss")
    }
}

private struct NativeSuccessFeedbackModifier: ViewModifier {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.sensoryFeedback(.success, trigger: model.persistedPracticeSuccessSequence) { oldValue, newValue in
            nativeSuccessFeedbackAllowed(
                enabled: model.successHapticsEnabled,
                reduceMotion: reduceMotion
            ) && newValue > oldValue
        }
    }
}

extension View {
    func nativeSuccessFeedback() -> some View {
        modifier(NativeSuccessFeedbackModifier())
    }
}

private func progressPracticeTimeLabel(_ seconds: TimeInterval) -> String {
    if seconds < 60 {
        return NativeLocalization.isolate("\(Int(seconds.rounded()))s")
    }
    return NativeLocalization.isolate("\(Int((seconds / 60).rounded()))m")
}

func nativeSuccessFeedbackAllowed(enabled: Bool, reduceMotion: Bool) -> Bool {
    enabled && !reduceMotion
}
