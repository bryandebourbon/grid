import SwiftUI

/// Underline tabs for All / Favorites / custom groups, plus a trailing add button.
struct GridPeopleTabBar: View {
    @Binding var selection: GridPeopleTab
    let groups: [PeopleGroup]
    var interestPages: [Interest] = []
    var canAddInterestPage = true
    var onSearchInterests: () -> Void
    var onDeleteInterest: (Interest) -> Void = { _ in }

    @State private var interestPendingDelete: Interest?

    private var tabs: [GridPeopleTab] {
        GridPeopleTabPaging.orderedTabs(customGroups: groups, interestPages: interestPages)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(tabs, id: \.self) { tab in
                        tabButton(for: tab)
                            .id(tab)
                    }

                    if canAddInterestPage {
                        Button(action: onSearchInterests) {
                            accessoryLabel(systemImage: "magnifyingglass")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Search interests")
                        .id("tab.accessory.search")
                    }
                }
            }
            .padding(.top, 10)
            .onAppear {
                scrollSelectedTab(intoView: proxy)
            }
            .onChange(of: selection) { _ in
                scrollSelectedTab(intoView: proxy)
            }
            .onChange(of: tabs) { _ in
                scrollSelectedTab(intoView: proxy)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("People filter")
    }

    private func scrollSelectedTab(intoView proxy: ScrollViewProxy) {
        let target = selection
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.22)) {
                proxy.scrollTo(target, anchor: .center)
            }
        }
    }

    @ViewBuilder
    private func tabButton(for tab: GridPeopleTab) -> some View {
        let isSelected = selection == tab
        let removableInterest: Interest? = {
            guard isSelected, case .interest(let raw) = tab else { return nil }
            return Interest(rawValue: raw)
        }()

        ZStack(alignment: .topTrailing) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    selection = tab
                }
            } label: {
                VStack(spacing: 8) {
                    Text(tab.title(in: groups))
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    Rectangle()
                        .fill(isSelected ? Color.primary : Color.clear)
                        .frame(height: 2)
                }
                .padding(.horizontal, removableInterest == nil ? 16 : 18)
                .padding(.top, removableInterest == nil ? 0 : 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("people.tab.\(tab.rawValue)")
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])

            if let interest = removableInterest {
                Button {
                    interestPendingDelete = interest
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.primary.opacity(0.55), Color.primary.opacity(0.08))
                }
                .buttonStyle(.plain)
                .offset(x: 2, y: -1)
                .accessibilityLabel("Remove \(interest.rawValue)")
            }
        }
        .popover(isPresented: deletePopoverPresented(for: tab)) {
            if let interest = removableInterest ?? interest(from: tab) {
                deleteInterestPopover(interest)
            }
        }
    }

    private func interest(from tab: GridPeopleTab) -> Interest? {
        guard case .interest(let raw) = tab else { return nil }
        return Interest(rawValue: raw)
    }

    private func accessoryLabel(systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Rectangle()
                .fill(Color.clear)
                .frame(height: 2)
        }
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

    private func deletePopoverPresented(for tab: GridPeopleTab) -> Binding<Bool> {
        Binding(
            get: {
                guard case .interest(let raw) = tab else { return false }
                return interestPendingDelete?.rawValue.compare(raw, options: .caseInsensitive) == .orderedSame
            },
            set: { presented in
                if !presented { interestPendingDelete = nil }
            }
        )
    }

    private func deleteInterestPopover(_ interest: Interest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Remove \(interest.rawValue)?")
                .font(.headline)
            Text("You’ll leave this interest and this page will close. People looking for \(interest.rawValue) won’t see you here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Keep") {
                    interestPendingDelete = nil
                }
                Spacer()
                Button("Delete", role: .destructive) {
                    let toDelete = interest
                    interestPendingDelete = nil
                    onDeleteInterest(toDelete)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 260)
        .presentationCompactAdaptation(.popover)
    }
}
