import SwiftUI

/// Folha que apresenta a linha do tempo e os membros de uma equipe.
struct TeamDetailSheet: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case timeline = "Linha do tempo"
        case people = "Pessoas"

        var id: Self { self }
    }

    let team: TeamDetail
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appTheme) private var theme
    @State private var selectedTab: Tab = .timeline
    @State private var selectedMember: TeamMember?
    @State private var pinnedActivityIDs: [TeamActivity.ID] = []
    @State private var displayedPinnedIndex = 0
    @State private var pendingPinID: TeamActivity.ID?
    @State private var isPinnedListPresented = false
    @State private var timelineScrollTarget: TeamActivity.ID?

    private var selectedIndex: Binding<Int> {
        Binding(
            get: {
                Tab.allCases.firstIndex(of: selectedTab) ?? 0
            },
            set: { newIndex in
                if Tab.allCases.indices.contains(newIndex) {
                    select(Tab.allCases[newIndex])
                }
            }
        )
    }

    private var displayedPinnedActivity: TeamActivity? {
        guard pinnedActivityIDs.indices.contains(displayedPinnedIndex) else { return nil }
        let activityID = pinnedActivityIDs[displayedPinnedIndex]
        return team.timeline.first { $0.id == activityID }
    }

    private var pendingPinActivity: TeamActivity? {
        guard let pendingPinID else { return nil }
        return team.timeline.first { $0.id == pendingPinID }
    }

    private var pinnedActivities: [TeamActivity] {
        pinnedActivityIDs.compactMap { activityID in
            team.timeline.first { $0.id == activityID }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(team.name.capitalized)
//                        .font(.largeTitle.weight(.semibold))
                        .adaptiveTextStyle(.largeTitle)
                        .fontWeight(.semibold)

                    Spacer()

                    Button("Fechar", systemImage: "xmark", action: { dismiss() })
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 36)
                .padding(.top, 32)
                .padding(.bottom, 22)

                ClearSegmentedPicker(
                    tabs: Tab.allCases.map(\.rawValue),
                    colors: [theme.accentColor, theme.accentColor],
                    badges: nil,
                    selectedTextColor: Color.Token.textPrimary,
                    unselectedTextColor: Color.Token.textNavigation,
                    currentTab: selectedIndex
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.Token.surfaceRaised, in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.Token.borderSubtle.opacity(0.65), lineWidth: 1)
                }
                .padding(.top, 12)
                .padding(.trailing, 12)
                .padding(.horizontal, 36)
                .padding(.bottom, 28)
            }
            .background(ThemeGradientBackground(theme: theme))

            if selectedTab == .timeline, let displayedPinnedActivity {
                PinnedActivityBanner(
                    activity: displayedPinnedActivity,
                    position: displayedPinnedIndex + 1,
                    total: pinnedActivityIDs.count,
                    navigate: { navigateToActivity(displayedPinnedActivity.id) },
                    showPinnedList: { isPinnedListPresented = true },
                    move: movePinnedBanner
                )
                .padding(.horizontal, 36)
                .padding(.vertical, 12)
            }

            Divider()

            Group {
                switch selectedTab {
                case .timeline:
                    TeamTimelineView(
                        activities: team.timeline,
                        members: team.members,
                        pinnedActivityIDs: $pinnedActivityIDs,
                        scrollTarget: $timelineScrollTarget
                    ) { activityID in
                        togglePin(activityID)
                    }
                case .people:
                    TeamPeopleView(members: team.members, selectedMember: $selectedMember)
                }
            }
        }
        .frame(minWidth: 960, idealWidth: 1_160, minHeight: 620, idealHeight: 720)
        .alert("Limite de tópicos fixados", isPresented: Binding(
            get: { pendingPinID != nil },
            set: { if !$0 { pendingPinID = nil } }
        ), presenting: pendingPinActivity) { activity in
            Button("Substituir o mais antigo") {
                replaceOldestPin(with: activity.id)
            }
            Button("Cancelar", role: .cancel) {
                pendingPinID = nil
            }
        } message: { activity in
            Text("Você já tem 4 tópicos fixados. Deseja substituir o tópico fixado há mais tempo por “\(activity.title)”?" )
        }
        .sheet(isPresented: $isPinnedListPresented) {
            PinnedActivitiesSheet(
                activities: pinnedActivities,
                onSelect: { activityID in
                    if let index = pinnedActivityIDs.firstIndex(of: activityID) {
                        displayedPinnedIndex = index
                    }
                    isPinnedListPresented = false
                    navigateToActivity(activityID)
                },
                onUnpin: unpin
            )
        }
    }

    private func select(_ tab: Tab) {
        guard tab != selectedTab else { return }

        if tab == .people {
            selectedMember = nil
        }

        if reduceMotion {
            selectedTab = tab
        } else {
            withAnimation(.snappy(duration: 0.25)) {
                selectedTab = tab
            }
        }
    }

    private func togglePin(_ activityID: TeamActivity.ID) {
        if pinnedActivityIDs.contains(activityID) {
            unpin(activityID)
        } else if pinnedActivityIDs.count < 4 {
            pinnedActivityIDs.append(activityID)
            displayedPinnedIndex = pinnedActivityIDs.count - 1
        } else {
            pendingPinID = activityID
        }
    }

    private func replaceOldestPin(with activityID: TeamActivity.ID) {
        guard !pinnedActivityIDs.isEmpty else { return }
        pinnedActivityIDs.removeFirst()
        pinnedActivityIDs.append(activityID)
        displayedPinnedIndex = pinnedActivityIDs.count - 1
        pendingPinID = nil
    }

    private func unpin(_ activityID: TeamActivity.ID) {
        guard let index = pinnedActivityIDs.firstIndex(of: activityID) else { return }
        pinnedActivityIDs.remove(at: index)

        if pinnedActivityIDs.isEmpty {
            displayedPinnedIndex = 0
        } else if index < displayedPinnedIndex {
            displayedPinnedIndex -= 1
        } else if displayedPinnedIndex >= pinnedActivityIDs.count {
            displayedPinnedIndex = pinnedActivityIDs.count - 1
        }
    }

    private func movePinnedBanner(by offset: Int) {
        guard pinnedActivityIDs.count > 1 else { return }
        displayedPinnedIndex = (displayedPinnedIndex + offset + pinnedActivityIDs.count) % pinnedActivityIDs.count
    }

    private func navigateToActivity(_ activityID: TeamActivity.ID) {
        if selectedTab != .timeline {
            select(.timeline)
        }

        timelineScrollTarget = nil
        DispatchQueue.main.async {
            timelineScrollTarget = activityID
        }
    }
}

private struct TeamTimelineView: View {
    let activities: [TeamActivity]
    let members: [TeamMember]
    @Binding var pinnedActivityIDs: [TeamActivity.ID]
    @Binding var scrollTarget: TeamActivity.ID?
    let togglePin: (TeamActivity.ID) -> Void
    @State private var highlightedActivityID: TeamActivity.ID?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(activities.enumerated()), id: \.element.id) { index, activity in
                        TeamTimelineRow(
                            activity: activity,
                            members: members,
                            isPinned: pinnedActivityIDs.contains(activity.id),
                            isHighlighted: highlightedActivityID == activity.id,
                            showsConnector: index < activities.count - 1
                        ) {
                            togglePin(activity.id)
                        }
                        .id(activity.id)
                    }
                }
                .padding(36)
            }
            .onAppear {
                scroll(to: scrollTarget, using: proxy)
            }
            .onChange(of: scrollTarget) { _, newValue in
                scroll(to: newValue, using: proxy)
            }
        }
    }

    private func scroll(to target: TeamActivity.ID?, using proxy: ScrollViewProxy) {
        guard let target else { return }

        DispatchQueue.main.async {
            withAnimation(.snappy(duration: 0.4)) {
                proxy.scrollTo(target, anchor: .center)
                highlightedActivityID = target
            }
            scrollTarget = nil

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                guard highlightedActivityID == target else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    highlightedActivityID = nil
                }
            }
        }
    }
}

private struct TeamTimelineRow: View {
    let activity: TeamActivity
    let members: [TeamMember]
    let isPinned: Bool
    let isHighlighted: Bool
    let showsConnector: Bool
    let togglePin: () -> Void
    @Environment(\.appTheme) private var theme
    @State private var isHovering = false

    private var categoryColor: Color {
        switch activity.category {
        case .decision: Color.categoryItemDecision
        case .task: Color.categoryItemTask
        case .meeting: Color.categoryItemMeeting
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(activity.category.rawValue)
//                    .font(.headline.weight(.semibold))
                    .adaptiveTextStyle(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(categoryColor)
                Text(activity.date)
//                    .font(.subheadline)
                    .adaptiveTextStyle(.subheadline)
                    .foregroundStyle(theme.accentColor.opacity(0.72))
            }
            .frame(width: 180, alignment: .center)

            VStack(spacing: 0) {
                Circle()
                    .fill(.secondary)
                    .frame(width: 9, height: 9)
                Rectangle()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 1)
                    .frame(maxHeight: showsConnector ? .infinity : 0)
            }
            .frame(minHeight: 146, alignment: .top)

            VStack(alignment: .leading, spacing: 12) {
                Text(activity.title)
//                    .font(.title3.weight(.semibold))
                    .adaptiveTextStyle(.title3)
                    .fontWeight(.semibold)
                    
                Text(activity.detail)
//                    .font(.body)
                    .adaptiveTextStyle(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    HStack(spacing: -8) {
                        ForEach(activity.participants, id: \.self) { participant in
                            ProfileAvatar(name: participant, size: 36)
                                .overlay(Circle().stroke(.background, lineWidth: 1))
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
            .padding(.bottom, 28)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, alignment: .leading)

            if isHovering || isPinned {
                Button(action: togglePin) {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
//                        .font(.title3.weight(.medium))
                        .adaptiveTextStyle(.title3)
                        .fontWeight(.medium)
                        .foregroundStyle(isPinned ? theme.accentColor : .secondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPinned ? "Desfixar tópico" : "Fixar tópico")
                .accessibilityValue(isPinned ? "Fixado" : "Não fixado")
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                Color.clear
                    .frame(width: 36, height: 36)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill((isHighlighted || isHovering) ? theme.accentColor.opacity(isHighlighted ? 0.12 : 0.07) : .clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke((isHighlighted || isHovering) ? theme.accentColor.opacity(isHighlighted ? 0.45 : 0.24) : .clear, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.16)) {
                isHovering = hovering
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isHighlighted)
    }
}

private struct PinnedActivityBanner: View {
    let activity: TeamActivity
    let position: Int
    let total: Int
    let navigate: () -> Void
    let showPinnedList: () -> Void
    let move: (Int) -> Void

    @Environment(\.appTheme) private var theme
    @State private var ignoresNextTap = false

    var body: some View {
        HStack(spacing: 10) {
            if total > 1 {
                Button("Tópico anterior", systemImage: "chevron.left") {
                    move(-1)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(theme.accentColor)
            }

            HStack(spacing: 12) {
                Image(systemName: "pin.fill")
                    .foregroundStyle(theme.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Tópico fixado \(position) de \(total)")
//                        .font(.caption.weight(.semibold))
                        .adaptiveTextStyle(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Text(activity.title)
//                        .font(.subheadline.weight(.semibold))
                        .adaptiveTextStyle(.subheadline)
                        .fontWeight(Font.Weight.semibold)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                Image(systemName: "arrow.down")
//                    .font(.subheadline.weight(.semibold))
                    .adaptiveTextStyle(.subheadline)
                    .fontWeight(Font.Weight.semibold)
                    .foregroundStyle(theme.accentColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture {
                guard !ignoresNextTap else { return }
                navigate()
            }
            .onLongPressGesture(minimumDuration: 0.6) {
                ignoresNextTap = true
                showPinnedList()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    ignoresNextTap = false
                }
            }
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { gesture in
                        guard total > 1 else { return }
                        move(gesture.translation.width < 0 ? 1 : -1)
                    }
            )

            if total > 1 {
                Button("Próximo tópico", systemImage: "chevron.right") {
                    move(1)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(theme.accentColor)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(theme.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

private struct PinnedActivitiesSheet: View {
    let activities: [TeamActivity]
    let onSelect: (TeamActivity.ID) -> Void
    let onUnpin: (TeamActivity.ID) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Tópicos fixados")
//                    .font(.title2.weight(.semibold))
                    .adaptiveTextStyle(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Fechar", systemImage: "xmark", action: { dismiss() })
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            if activities.isEmpty {
                ContentUnavailableView("Nenhum tópico fixado", systemImage: "pin.slash")
            } else {
                List {
                    ForEach(Array(activities.enumerated()), id: \.element.id) { index, activity in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
//                                .font(.caption.weight(.bold))
                                .adaptiveTextStyle(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                                .frame(width: 18)

                            Button {
                                onSelect(activity.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Label(activity.category.rawValue, systemImage: activity.category.systemImage)
//                                        .font(.caption)
                                        .adaptiveTextStyle(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(activity.title)
//                                        .font(.subheadline.weight(.semibold))
                                        .adaptiveTextStyle(.subheadline)
                                        .fontWeight(.semibold)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button("Desfixar", systemImage: "pin.slash", role: .destructive) {
                                onUnpin(activity.id)
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Desfixar \(activity.title)")
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(24)
        .frame(width: 460, height: 360)
    }
}

private struct TeamPeopleView: View {
    let members: [TeamMember]
    @Binding var selectedMember: TeamMember?

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 20) {
                    ForEach(members) { member in
                        TeamMemberCard(member: member, isSelected: selectedMember == member) {
                            selectedMember = member
                        }
                    }
                }
                .padding(36)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                TapGesture().onEnded {
                    selectedMember = nil
                },
                including: .gesture
            )

            if let selectedMember {
                Divider()
                TeamMemberDetailView(member: selectedMember)
                    .frame(width: 330)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedMember)
    }
}

private struct TeamMemberCard: View {
    let member: TeamMember
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                TeamMemberAvatar(member: member, highlighted: isSelected, size: 92)
                Text(member.name)
//                    .font(.headline)
                    .adaptiveTextStyle(.headline)
                    .lineLimit(1)
                Text(member.role)
//                    .font(.subheadline)
                    .adaptiveTextStyle(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 154, height: 190)
            .padding(12)
            .background(isSelected ? Color.accentColor.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct TeamMemberDetailView: View {
    let member: TeamMember

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 14) {
                    TeamMemberAvatar(member: member, highlighted: false, size: 72)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(member.name)
//                            .font(.title2.weight(.semibold))
                            .adaptiveTextStyle(.title2)
                            .fontWeight(.semibold)
                        Text(member.email).foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    TeamMemberDetailRow(label: "Cargo", value: member.role, systemImage: "person.2")
                    TeamMemberDetailRow(label: "Contratado em", value: member.hiredDate, systemImage: "calendar")
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Últimas atividades")
                        .adaptiveTextStyle(.headline)
                    ForEach(member.recentActivities, id: \.self) { activity in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(activity)
//                                .font(.subheadline.weight(.semibold))
                                .adaptiveTextStyle(.headline)
                                .fontWeight(.semibold)
                            Label("5 ago, 2026", systemImage: "calendar")
//                                .font(.caption)
                                .adaptiveTextStyle(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Label("Projetos relacionados", systemImage: "briefcase")
//                        .font(.headline)
                        .adaptiveTextStyle(.headline)
                    ForEach(member.relatedProjects, id: \.self) { project in
                        Text(project)
//                            .font(.subheadline.weight(.semibold))
                            .adaptiveTextStyle(.subheadline)
                            .fontWeight(.semibold)
                    }
                }
            }
            .padding(28)
        }
        .background(Color.accentColor.opacity(0.045))
    }
}

private struct TeamMemberDetailRow: View {
    let label: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Label(LocalizedStringKey(label), systemImage: systemImage)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
//        .font(.subheadline)
        .adaptiveTextStyle(.subheadline)
    }
}

private struct TeamMemberAvatar: View {
    let member: TeamMember
    let highlighted: Bool
    let size: CGFloat

    var body: some View {
        ProfileAvatar(name: member.name, highlighted: highlighted, size: size)
    }
}

private struct ProfileAvatar: View {
    let name: String
    var highlighted = false
    let size: CGFloat

    private var initials: String {
        name
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
    }

    private var color: Color {
        switch name.unicodeScalars.first?.value ?? 0 {
        case 65...70: Color.Token.themePlumAccent
        case 71...76: Color.Token.statusSuccess
        case 77...82: Color.Token.statusWarning
        default: Color.Token.interactiveAccent
        }
    }

    var body: some View {
        Circle()
            .fill(highlighted ? Color.Token.interactiveAccent : color.opacity(0.20))
            .overlay {
                Text(initials)
//                    .font(size >= 60 ? .title3.weight(.semibold) : .caption.weight(.semibold))
                    .adaptiveTextStyle(size >= 60 ? .title3 : .caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(highlighted ? Color.Token.textOnAccent : color)
            }
            .frame(width: size, height: size)
    }
}
