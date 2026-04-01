import SwiftUI

struct BrowserView: View {
    @State private var viewModel = BrowserViewModel()

    var body: some View {
        HStack(spacing: 0) {
            // Left column: app list
            VStack(alignment: .leading, spacing: 0) {
                Text("APPS")
                    .font(DS.Fonts.sectionHeader)
                    .foregroundStyle(DS.Colors.textSecondary)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.top, DS.Spacing.md)
                    .padding(.bottom, DS.Spacing.sm)

                ScrollView {
                    LazyVStack(spacing: DS.Spacing.xxs) {
                        ForEach(viewModel.apps) { app in
                            Button {
                                viewModel.selectedApp = app
                                viewModel.loadFragments(for: app.bundleIdentifier)
                            } label: {
                                HStack {
                                    Image(systemName: iconFor(app.bundleIdentifier))
                                        .font(.system(size: 12))
                                        .foregroundStyle(DS.Colors.accent)
                                        .frame(width: 18)

                                    Text(app.appName)
                                        .font(DS.Fonts.body)
                                        .foregroundStyle(DS.Colors.text)
                                        .lineLimit(1)

                                    Spacer()

                                    Text("\(app.count)")
                                        .font(DS.Fonts.captionSmall)
                                        .foregroundStyle(DS.Colors.textSecondary)
                                }
                                .padding(.horizontal, DS.Spacing.md)
                                .padding(.vertical, DS.Spacing.sm)
                                .background(
                                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                                        .fill(viewModel.selectedApp?.id == app.id ? DS.Colors.surfaceHover : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, DS.Spacing.sm)
                }

                Divider()

                // Stats
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("STATS")
                        .font(DS.Fonts.sectionHeader)
                        .foregroundStyle(DS.Colors.textSecondary)

                    statsRow("Today", value: "\(viewModel.todayCount)")
                    statsRow("This week", value: "\(viewModel.weekCount)")
                    statsRow("Total", value: "\(viewModel.totalCount)")
                }
                .padding(DS.Spacing.md)
            }
            .frame(width: 200)
            .background(DS.Colors.bg)

            Divider()

            // Right column: fragments from selected app
            if let app = viewModel.selectedApp {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("\(app.appName) · \(viewModel.fragments.count) fragments")
                            .font(DS.Fonts.subtitle)
                            .foregroundStyle(DS.Colors.text)
                        Spacer()
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.md)

                    Divider()

                    ScrollView {
                        LazyVStack(spacing: DS.Spacing.sm) {
                            ForEach(groupedByDay(), id: \.day) { group in
                                Text(group.day)
                                    .font(DS.Fonts.sectionHeader)
                                    .foregroundStyle(DS.Colors.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, DS.Spacing.sm)

                                ForEach(group.fragments) { fragment in
                                    FragmentRowView(
                                        fragment: fragment,
                                        snippet: nil,
                                        expanded: viewModel.expandedId == fragment.id
                                    ) {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            if viewModel.expandedId == fragment.id {
                                                viewModel.expandedId = nil
                                            } else {
                                                viewModel.expandedId = fragment.id
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.bottom, DS.Spacing.lg)
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack {
                    Spacer()
                    Text("Select an app to browse fragments")
                        .font(DS.Fonts.body)
                        .foregroundStyle(DS.Colors.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { viewModel.load() }
    }

    private func statsRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(DS.Fonts.bodySmall)
                .foregroundStyle(DS.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(DS.Fonts.bodySmall)
                .foregroundStyle(DS.Colors.text)
        }
    }

    private func iconFor(_ bundleID: String) -> String {
        let cat = AppCategory.from(bundleID: bundleID)
        switch cat {
        case .code: return "chevronleft.forwardslash.chevronright"
        case .browsing: return "globe"
        case .communication: return "bubble.left.fill"
        case .email: return "envelope.fill"
        case .design: return "paintbrush.fill"
        case .work: return "briefcase.fill"
        case .other: return "app.fill"
        }
    }

    private func groupedByDay() -> [(day: String, fragments: [Fragment])] {
        let grouped = Dictionary(grouping: viewModel.fragments, by: \.day)
        return grouped.sorted { $0.key > $1.key }.map { (day: displayDay($0.key), fragments: $0.value) }
    }

    private func displayDay(_ day: String) -> String {
        let today = Fragment.makeDay()
        if day == today { return "Today" }

        let yesterday = Fragment.makeDay(from: Date().addingTimeInterval(-86400))
        if day == yesterday { return "Yesterday" }

        return day
    }
}
