import SwiftUI
import os

private let log = Logger(subsystem: "dev.cobrain.app", category: "timeline")

struct TimelineView: View {
    @State private var selectedDate: Date = Date()
    @State private var fragments: [Fragment] = []
    @State private var totalForDay: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            // Date navigation
            dateHeader
            Divider()

            // Timeline content
            if fragments.isEmpty {
                emptyState
            } else {
                timelineContent
            }
        }
        .onAppear { loadFragments() }
        .onChange(of: selectedDate) { _, _ in loadFragments() }
    }

    // MARK: - Date Header

    private var dateHeader: some View {
        HStack {
            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate)!
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.Colors.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: DS.Spacing.xxs) {
                Text(dayLabel)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Colors.text)
                Text("\(totalForDay) fragments")
                    .font(DS.Fonts.caption)
                    .foregroundStyle(DS.Colors.textSecondary)
            }

            Spacer()

            Button {
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate)!
                if tomorrow <= Date() {
                    selectedDate = tomorrow
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isToday ? DS.Colors.border : DS.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(isToday)
        }
        .padding(.horizontal, DS.Spacing.xl)
        .padding(.vertical, DS.Spacing.md)
    }

    // MARK: - Timeline Content

    private var timelineContent: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(groupedByTimeBlock(), id: \.block) { group in
                    Section {
                        ForEach(group.fragments) { fragment in
                            TimelineRow(fragment: fragment)
                        }
                    } header: {
                        timeBlockHeader(group.block, count: group.fragments.count)
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.xl)
        }
    }

    // MARK: - Time Block Header

    private func timeBlockHeader(_ block: TimeBlock, count: Int) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: block.icon)
                .font(.system(size: 11))
                .foregroundStyle(DS.Colors.accent)

            Text(block.label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.textSecondary)
                .textCase(.uppercase)

            Text("\(count)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.Colors.textSecondary.opacity(0.7))

            Rectangle()
                .fill(DS.Colors.border)
                .frame(height: 0.5)
        }
        .padding(.vertical, DS.Spacing.sm)
        .padding(.top, DS.Spacing.md)
        .background(DS.Colors.bg)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Spacer()
            Image(systemName: "clock")
                .font(.system(size: 28, weight: .thin))
                .foregroundStyle(DS.Colors.textSecondary)
            Text("No fragments for \(dayLabel.lowercased())")
                .font(DS.Fonts.body)
                .foregroundStyle(DS.Colors.textSecondary)
            Spacer()
        }
    }

    // MARK: - Data

    private func loadFragments() {
        let day = Fragment.makeDay(from: selectedDate)
        do {
            fragments = try StorageManager.shared.fragmentsForDay(day)
            totalForDay = fragments.count
            log.info("Loaded \(fragments.count) fragments for \(day)")
        } catch {
            log.error("Failed to load timeline: \(error.localizedDescription)")
            fragments = []
            totalForDay = 0
        }
    }

    private var dayLabel: String {
        if isToday { return "Today" }
        if Calendar.current.isDateInYesterday(selectedDate) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: selectedDate)
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    // MARK: - Grouping

    private func groupedByTimeBlock() -> [(block: TimeBlock, fragments: [Fragment])] {
        let grouped = Dictionary(grouping: fragments) { fragment -> TimeBlock in
            TimeBlock.from(timestamp: fragment.capturedAt)
        }
        return TimeBlock.allCases.compactMap { block in
            guard let frags = grouped[block], !frags.isEmpty else { return nil }
            return (block: block, fragments: frags)
        }
    }
}

// MARK: - Time Blocks

enum TimeBlock: String, CaseIterable, Hashable {
    case earlyMorning
    case morning
    case afternoon
    case evening
    case night

    var label: String {
        switch self {
        case .earlyMorning: return "Early Morning"
        case .morning: return "Morning"
        case .afternoon: return "Afternoon"
        case .evening: return "Evening"
        case .night: return "Night"
        }
    }

    var icon: String {
        switch self {
        case .earlyMorning: return "sunrise"
        case .morning: return "sun.max"
        case .afternoon: return "sun.haze"
        case .evening: return "sunset"
        case .night: return "moon.stars"
        }
    }

    static func from(timestamp: Int) -> TimeBlock {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 0..<6: return .night
        case 6..<9: return .earlyMorning
        case 9..<12: return .morning
        case 12..<17: return .afternoon
        case 17..<21: return .evening
        default: return .night
        }
    }
}

// MARK: - Timeline Row

struct TimelineRow: View {
    let fragment: Fragment
    @State private var expanded = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                expanded.toggle()
            }
        } label: {
            HStack(alignment: .top, spacing: DS.Spacing.md) {
                // Time + dot
                VStack(spacing: DS.Spacing.xxs) {
                    Text(timeString)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(DS.Colors.textSecondary)

                    Circle()
                        .fill(appColor)
                        .frame(width: 6, height: 6)

                    if !expanded {
                        Rectangle()
                            .fill(DS.Colors.border)
                            .frame(width: 1)
                            .frame(maxHeight: .infinity)
                    }
                }
                .frame(width: 44)

                // Content card
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: fragment.appIcon)
                            .font(.system(size: 10))
                            .foregroundStyle(appColor)

                        Text(fragment.appName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DS.Colors.text)

                        if let title = fragment.windowTitle, !title.isEmpty {
                            Text("·")
                                .foregroundStyle(DS.Colors.textSecondary)
                            Text(title)
                                .font(.system(size: 11))
                                .foregroundStyle(DS.Colors.textSecondary)
                                .lineLimit(1)
                        }
                    }

                    if let summary = fragment.summary {
                        Text(summary)
                            .font(DS.Fonts.bodySmall)
                            .foregroundStyle(DS.Colors.text)
                            .lineLimit(expanded ? nil : 2)

                        if expanded {
                            if let imgPath = fragment.imagePath {
                                let imgURL = StorageManager.screenshotURL(for: imgPath)
                                AsyncImageView(url: imgURL)
                                    .frame(maxWidth: 320, maxHeight: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                                    .padding(.vertical, DS.Spacing.xs)
                            }

                            if let url = fragment.url, !url.isEmpty {
                                HStack(spacing: DS.Spacing.xxs) {
                                    Image(systemName: "link")
                                        .font(.system(size: 9))
                                    Text(url)
                                        .font(.system(size: 10))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(DS.Colors.accent)
                            }

                            if let url = fragment.url, let u = URL(string: url) {
                                Button("Open URL") { NSWorkspace.shared.open(u) }
                                    .font(DS.Fonts.caption)
                                    .foregroundStyle(DS.Colors.accent)
                                    .padding(.top, DS.Spacing.xxs)
                            }
                        }
                    } else {
                        HStack(spacing: DS.Spacing.xs) {
                            ProgressView()
                                .scaleEffect(0.5)
                            Text("Summarizing...")
                                .font(DS.Fonts.captionSmall)
                                .foregroundStyle(DS.Colors.textSecondary)
                        }
                    }
                }
                .padding(DS.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .fill(expanded ? DS.Colors.surface : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .stroke(expanded ? DS.Colors.border : Color.clear, lineWidth: 0.5)
                )
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, DS.Spacing.xxs)
    }

    private var timeString: String {
        let date = Date(timeIntervalSince1970: TimeInterval(fragment.capturedAt))
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private var appColor: Color {
        let cat = AppCategory.from(bundleID: fragment.bundleIdentifier)
        switch cat {
        case .code: return .blue
        case .browsing: return .orange
        case .communication: return .green
        case .email: return .purple
        case .work: return .indigo
        case .design: return .pink
        case .other: return .gray
        }
    }
}

