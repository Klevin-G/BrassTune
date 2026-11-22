import SwiftUI

struct IntonationHistoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingAll = false
    @State private var goalCreationMessage: String?
    @State private var selectedGoalID: UUID?
    @State private var goalsPresented = false
    @State private var historySnapshot = IntonationHistory(sessions: [], instrumentID: "trumpet", referencePitchHz: 440)
    @State private var completedGoalPendingReopen = false

    var body: some View {
        let snapshot = historySnapshot
        let displayedNotes = showingAll ? snapshot.notes : snapshot.prioritizedNotes
        List {
            Section {
                Text(verbatim: NativeLocalization.format(
                    "A local review of completed live captures for %@ at A4 %@ Hz. Compared with equal temperament; intentional chord tuning can differ. Each take has equal weight.",
                    instrumentDisplayName(model.selectedInstrumentId),
                    model.referencePitchHz.formatted(.number.locale(NativeLocalization.language.locale).precision(.fractionLength(1)))
                ))
                    .font(.footnote)
                    .foregroundStyle(BTTheme.muted)
                Text(verbatim: NativeLocalization.string("Evidence window: the last 30 calendar days. A recurring tendency needs at least 3 qualifying takes across 2 days."))
                    .font(.footnote)
                    .foregroundStyle(BTTheme.muted)
            } header: {
                Text(verbatim: NativeLocalization.string("Intonation history"))
            }

            if snapshot.notes.isEmpty {
                Section {
                    Text(verbatim: NativeLocalization.string("More evidence needed"))
                        .font(.headline)
                    Text(verbatim: NativeLocalization.string("Complete live tuning captures for this instrument and A4 setting to build a note-by-note review."))
                        .foregroundStyle(BTTheme.muted)
                }
                .accessibilityIdentifier("intonationHistory.empty")
            } else {
                Section(NativeLocalization.string("Written notes")) {
                    ForEach(displayedNotes) { note in
                        noteRow(note)
                    }
                    if snapshot.notes.count > snapshot.prioritizedNotes.count {
                        Button(showingAll ? NativeLocalization.string("Show prioritized notes") : NativeLocalization.string("Show all notes")) {
                            showingAll.toggle()
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.intonationHistory")
        .navigationTitle(NativeLocalization.string("Intonation history"))
        .navigationDestination(isPresented: $goalsPresented) {
            PracticeGoalListView(focusedGoalID: selectedGoalID)
        }
        .onAppear { refreshHistory() }
        .onReceive(model.$sessions) { sessions in refreshHistory(sessions: sessions) }
        .onChange(of: model.selectedInstrumentId) { _, _ in refreshHistory() }
        .onChange(of: model.referencePitchHz) { _, _ in refreshHistory() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refreshHistory() }
        .alert(NativeLocalization.string("Practice goal"), isPresented: Binding(
            get: { goalCreationMessage != nil },
            set: { if !$0 { goalCreationMessage = nil } }
        )) {
            if completedGoalPendingReopen, let selectedGoalID {
                Button(NativeLocalization.string("Reopen")) {
                    model.reopenPracticeGoal(id: selectedGoalID)
                    completedGoalPendingReopen = false
                    goalsPresented = true
                }
            }
            if selectedGoalID != nil {
                Button(NativeLocalization.string("Practice goals")) { goalsPresented = true }
            }
            Button(NativeLocalization.string("OK"), role: .cancel) { goalCreationMessage = nil }
        } message: {
            Text(verbatim: goalCreationMessage ?? "")
        }
    }

    @ViewBuilder
    private func noteRow(_ note: IntonationHistory.Note) -> some View {
        VStack(alignment: .leading, spacing: BTSpacing.sm) {
            HStack {
                Text(verbatim: note.id).font(.headline)
                Spacer()
                Text(verbatim: centsText(note.medianSignedCents))
                    .monospacedDigit()
                    .foregroundStyle(BTTheme.text)
            }
            Text(verbatim: note.isRecurring
                ? NativeLocalization.format(
                    "%@ · spread %@¢ · %@ takes / %@ days",
                    directionText(note),
                    note.spreadCents.formatted(.number.locale(NativeLocalization.language.locale).precision(.fractionLength(1))),
                    note.takeCount.formatted(.number.locale(NativeLocalization.language.locale)),
                    note.dayCount.formatted(.number.locale(NativeLocalization.language.locale))
                )
                : NativeLocalization.format(
                    "%@ takes / %@ days",
                    note.takeCount.formatted(.number.locale(NativeLocalization.language.locale)),
                    note.dayCount.formatted(.number.locale(NativeLocalization.language.locale))
                ))
                .font(.footnote)
                .foregroundStyle(BTTheme.muted)
            if note.isRecurring {
                if note.hasActionableBias {
                    Button(NativeLocalization.string("Explore sustained tone")) { createGoal(for: note) }
                        .buttonStyle(BTSecondaryButtonStyle())
                        .accessibilityIdentifier("intonationHistory.goal.\(note.id)")
                }
            } else {
                Text(verbatim: NativeLocalization.string("More evidence needed before calling this a recurring tendency."))
                    .font(.footnote)
                    .foregroundStyle(BTTheme.muted)
            }
        }
        .padding(.vertical, BTSpacing.xs)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("intonationHistory.note.\(note.id)")
    }

    private func createGoal(for note: IntonationHistory.Note) {
        guard note.hasActionableBias else { return }
        completedGoalPendingReopen = false
        let passage = IntonationHistory.sustainedToneGoalName(instrumentID: model.selectedInstrumentId, note: note)
        let goalID = IntonationHistory.sustainedToneGoalID(instrumentID: model.selectedInstrumentId, note: note)
        selectedGoalID = goalID
        guard let existing = model.practiceFeatures.measurableGoals.first(where: { $0.id == goalID }) else {
            createNewGoal(id: goalID, passage: passage, note: note)
            return
        }
        guard !existing.isCompleted else {
            completedGoalPendingReopen = true
            goalCreationMessage = NativeLocalization.string("Completed manually")
            return
        }
        goalCreationMessage = NativeLocalization.format("An active sustained-tone goal already exists for %@.", note.id)
    }

    private func createNewGoal(id: PracticeGoal.ID, passage: String, note: IntonationHistory.Note) {
        completedGoalPendingReopen = false
        let created = model.savePracticeGoal(
            id: id,
            passage: passage,
            skill: .tone,
            criterion: PracticeGoalCriterion(
                kind: .sustainedTone,
                targetSustainSeconds: IntonationHistory.suggestedSustainSeconds(for: note)
            ),
            strategy: .listenFirst,
            nextReviewAt: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        )
        if !created { selectedGoalID = nil }
        goalCreationMessage = created
            ? NativeLocalization.format("Created an explore goal for %@. You can review it in Practice goals.", note.id)
            : NativeLocalization.string("A new goal could not be created because the goal list is full.")
    }

    private func centsText(_ cents: Double) -> String {
        let sign = cents >= 0 ? "+" : "−"
        let magnitude = abs(cents).formatted(.number.locale(NativeLocalization.language.locale).precision(.fractionLength(1)))
        return NativeLocalization.format("%@ cents", sign + magnitude)
    }

    private func directionText(_ note: IntonationHistory.Note) -> String {
        switch note.direction {
        case .above: return NativeLocalization.string("Above equal temperament")
        case .below: return NativeLocalization.string("Below equal temperament")
        case .centeredOrMixed: return NativeLocalization.string("Centered or mixed")
        }
    }

    private func refreshHistory(sessions: [PracticeSession]? = nil) {
        historySnapshot = IntonationHistory(
            sessions: sessions ?? model.sessions,
            instrumentID: model.selectedInstrumentId,
            referencePitchHz: model.referencePitchHz
        )
    }
}
