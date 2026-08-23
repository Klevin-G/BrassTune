import SwiftUI
import UIKit

struct PlayAlongIdleView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var moreWaysExpanded: Bool

    var body: some View {
        BTPageHeader(
            eyebrow: "Guided Practice",
            title: "Choose a clear next step",
            subtitle: "Each routine tells you what it trains, what it needs, and when you are finished."
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
            Label("Steady air and relaxed attacks", systemImage: "wind")
                .font(.subheadline)
            Label("Any level · no microphone required", systemImage: "person.fill.checkmark")
                .font(.subheadline)
            Label("Complete five guided steps", systemImage: "checkmark.circle")
                .font(.subheadline)
        }
        .accessibilityIdentifier("playAlong.recommendation")

        if requiresNativeMicrophoneRecovery(model) {
            MicrophoneRecoveryCard()
            MicrophoneRecoveryActions {
                Task {
                    await model.startPlayAlong(exerciseID: model.selectedPlayAlongExerciseID)
                }
            }
            .accessibilityIdentifier("playAlong.microphoneRecoveryActions")
        }

        VStack(alignment: .leading, spacing: BTSpacing.md) {
            Button {
                moreWaysExpanded.toggle()
            } label: {
                HStack(spacing: BTSpacing.sm) {
                    Label("Choose another exercise", systemImage: "music.note.list")
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
            .accessibilityHint("Shows the exercise library and custom exercise builder")
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
                Label("Build a custom scale exercise", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(BTSecondaryButtonStyle())
            .accessibilityIdentifier("practice.quickStart.builder")

            if NativeReleaseFeatureFlags.offlinePacks {
                NavigationLink {
                    PracticePacksView()
                } label: {
                    Label("Downloaded practice routines", systemImage: "shippingbox")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(BTSecondaryButtonStyle())
                .accessibilityIdentifier("practice.quickStart.packs")
            }

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

            Label("Pitch accuracy and smooth note changes", systemImage: "scope")
                .font(.caption)
            Label("About 3 minutes · microphone required", systemImage: "mic")
                .font(.caption)
            Label("Finish by holding each written note accurately", systemImage: "checkmark.circle")
                .font(.caption)

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

@MainActor
func requiresNativeMicrophoneRecovery(_ model: AppModel) -> Bool {
    switch model.audioEngine.audioState {
    case .permissionDenied, .permissionRestrictedOrUnavailable:
        return true
    default:
        return model.lastError == .microphoneUnavailable
    }
}

private struct PracticeShortcutSection: View {
    @EnvironmentObject private var model: AppModel
    let title: String
    let emptyMessage: String
    let shortcuts: [PracticeShortcut]

    var body: some View {
        let visibleShortcuts = shortcuts.filter {
            NativeReleaseFeatureFlags.offlinePacks || $0.kind != .practicePack
        }
        VStack(alignment: .leading, spacing: BTSpacing.sm) {
            Text(verbatim: title)
                .font(.headline)
            if visibleShortcuts.isEmpty {
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
                ForEach(visibleShortcuts.prefix(3)) { shortcut in
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
        let weeklySnapshot = AnalyticsSnapshot(sessions: progressWeeklySessions(model.sessions))
        VStack(spacing: 0) {
            BTScreen {
                BTPageHeader(
                    eyebrow: "Progress",
                    title: "Practice momentum",
                    subtitle: "See what you did today, how this week is going, and what to try next."
                )

                ProgressTodaySection()

                if weeklySnapshot.hasSessions {
                    ProgressTrendsSection(snapshot: weeklySnapshot)
                }

                PracticeStreakCard(summary: PracticeStreakSummary.calculate(sessions: model.sessions))

                ProgressNextStepSection(selectedTab: $selectedTab)
                WeeklyGoalCard()
                ProgressGettingStartedSection()

                if model.analyticsSnapshot.hasSessions { ProgressHistorySection() }
            }
            .accessibilityIdentifier("screen.progress")
        }
        .background(BTTheme.background.ignoresSafeArea())
        .navigationTitle("Progress")
    }
}

func progressWeeklySessions(
    _ sessions: [PracticeSession],
    now: Date = Date(),
    calendar: Calendar = .current
) -> [PracticeSession] {
    guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
    return sessions.filter { interval.contains($0.startedAt) }
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
            earned: model.sessions.contains {
                $0.activity == .guidedWarmup && $0.completion == .completed
            } || model.currentWarmupCheckpoint?.completed == true
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
        if earnedCount < milestones.count {
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
}

private struct ProgressTodaySection: View {
    @EnvironmentObject private var model: AppModel

    private var todaySessions: [PracticeSession] {
        model.sessions.filter {
            Calendar.current.isDateInToday($0.startedAt) && $0.contributesPracticeTime
        }
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
                .btReadableForeground()
                Text(verbatim: todaySessions.isEmpty
                    ? NativeLocalization.string("One short session is enough to get moving.")
                    : NativeLocalization.format(
                        "%@ minutes · %@ sessions",
                        String(todayMinutes),
                        String(todaySessions.count)
                    ))
                    .font(.subheadline)
                    .btReadableForeground()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("progress.today")
    }
}

private struct ProgressNextStepSection: View {
    @EnvironmentObject private var model: AppModel
    @Binding var selectedTab: AppTab

    var body: some View {
        VStack(alignment: .leading, spacing: BTSpacing.sm) {
            Text("Next step")
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("progress.nextStep")
            BTCard {
                Label {
                    Text(verbatim: recommendationTitle)
                } icon: {
                    Image(systemName: recommendationIcon)
                }
                    .font(.headline)
                Text(verbatim: recommendationText)
                    .font(.subheadline)
                    .btReadableForeground()
                    .fixedSize(horizontal: false, vertical: true)

                recommendedAction
            }
        }
    }

    @ViewBuilder
    private var recommendedAction: some View {
        switch model.progressRecommendationDestination {
        case .guidedWarmup:
            NavigationLink {
                GuidedWarmupView()
            } label: {
                Label("Start 5-minute warm-up", systemImage: "timer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BTPrimaryButtonStyle())
            .accessibilityIdentifier("progress.nextStep.cta")
        case .practicePlan:
            Button {
                selectedTab = .scales
            } label: {
                Label("Open Scales", systemImage: "music.note.list")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BTPrimaryButtonStyle())
            .accessibilityIdentifier("progress.nextStep.cta")
        case .scalePractice, .visualScalePractice:
            Button {
                selectedTab = .scales
            } label: {
                Label("Open Scales", systemImage: "music.note.list")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BTPrimaryButtonStyle())
            .accessibilityIdentifier("progress.nextStep.cta")
        case .tuning, .playAlong:
            Button {
                selectedTab = .tuner
            } label: {
                Label("Open Tuner", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BTPrimaryButtonStyle())
            .accessibilityIdentifier("progress.nextStep.cta")
        }
    }

    private var recommendationTitle: String {
        switch model.progressRecommendationDestination {
        case .guidedWarmup: return NativeLocalization.string("5-minute warm-up")
        case .practicePlan: return NativeLocalization.string("Practice without live listening")
        case .tuning, .playAlong, .scalePractice, .visualScalePractice: return NativeLocalization.string("3-minute tuning check")
        }
    }

    private var recommendationIcon: String {
        switch model.progressRecommendationDestination {
        case .guidedWarmup: return "timer"
        case .practicePlan: return "music.note.list"
        case .tuning, .playAlong, .scalePractice, .visualScalePractice: return "tuningfork"
        }
    }

    private var recommendationText: String {
        switch model.progressRecommendationDestination {
        case .guidedWarmup:
            return NativeLocalization.string("Microphone access is off. Start a guided warm-up to build steady air and relaxed attacks without listening.")
        case .practicePlan:
            return NativeLocalization.string("Live listening needs attention. Use a scale or practice plan while you check your audio connection.")
        case .tuning, .playAlong, .scalePractice, .visualScalePractice:
            return model.analyticsSnapshot.hasSessions
                ? model.analyticsSnapshot.recommendation
                : NativeLocalization.string("Play one comfortable note, find the center, and save the result.")
        }
    }
}

private struct ProgressTrendsSection: View {
    let snapshot: AnalyticsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: BTSpacing.sm) {
            Text("Weekly trend")
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
                    value: .verbatim(NativeLocalization.isolate(String(snapshot.recordingSessionCount))),
                    detail: "meaningful captures"
                )
            }
            .accessibilityIdentifier("progress.metrics")
        }
    }
}

private struct PracticeStreakCard: View {
    let summary: PracticeStreakSummary

    private var accessibilitySummary: String {
        NativeLocalization.format(
            "Current streak: %@ days. Longest streak: %@ days.",
            String(summary.currentStreakDays),
            String(summary.longestStreakDays)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BTSpacing.sm) {
            Text("Practice streak")
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)

            BTCard(tint: BTTheme.surfaceWarm) {
                HStack(spacing: BTSpacing.md) {
                    streakMetric(title: "Current streak", days: summary.currentStreakDays)
                    Divider()
                    streakMetric(title: "Longest streak", days: summary.longestStreakDays)
                }

                Text("Last 7 days")
                    .font(.subheadline.weight(.semibold))
                    .btReadableForeground()

                HStack(spacing: BTSpacing.sm) {
                    ForEach(summary.recentDays) { day in
                        VStack(spacing: BTSpacing.xs) {
                            Text(verbatim: day.date.formatted(.dateTime.weekday(.narrow)))
                                .font(.caption.weight(.semibold))
                                .btReadableForeground()
                            Image(systemName: day.practiced ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(day.practiced ? BTTheme.success : BTTheme.muted)
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide)))
                        .accessibilityValue(day.practiced
                            ? NativeLocalization.string("Practiced")
                            : NativeLocalization.string("No practice"))
                    }
                }
            }
        }
        .accessibilityIdentifier("progress.streak")
        .accessibilityElement(children: .contain)
        .accessibilityLabel(NativeLocalization.string("Practice streak"))
        .accessibilityValue(accessibilitySummary)
    }

    private func streakMetric(title: String, days: Int) -> some View {
        VStack(alignment: .leading, spacing: BTSpacing.xs) {
            Text(verbatim: title)
                .font(.caption.weight(.semibold))
                .btReadableForeground()
            Text(verbatim: NativeLocalization.format("%@ days", String(days)))
                .font(.title3.weight(.bold).monospacedDigit())
                .btReadableForeground()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

            ForEach(model.sessions.filter(\.contributesPracticeTime).prefix(3)) { session in
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
                        if session.activity.contributesPitchMetrics {
                            Text(verbatim: NativeLocalization.isolate("\(Int(session.inTunePercentage.rounded()))%"))
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(session.inTunePercentage >= 70 ? BTTheme.success : BTTheme.warning)
                        } else {
                            Text(verbatim: NativeLocalization.string("Completed"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(BTTheme.success)
                        }
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
                Text("Create a free account to personalize your BrassTune practice profile.")
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
