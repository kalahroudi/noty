// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import NotyKit

/// "Filter" button next to the search box; opens the popover.
struct FilterButton: View {
    let lib = LibraryModel.shared
    @State private var open = false

    var body: some View {
        let n = lib.filter.activeFilterCount
        Button { open.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: n > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle").frame(width: 14, height: 16)
                if n > 0 { Text("\(n)").font(.system(size: 11, weight: .semibold)).padding(.horizontal, 5).background(Theme.accent, in: Capsule()).foregroundStyle(Theme.onAccent) }
            }
        }
        .buttonStyle(Pill()).fixedSize().accessibilityLabel("Filter").help("Filter by tag, category, kind, status and date")
        .popover(isPresented: $open, arrowEdge: .bottom) { FilterPopover() }
    }
}

/// Sort order menu with a checkmark on the current choice.
struct SortMenu: View {
    let lib = LibraryModel.shared
    var body: some View {
        Menu {
            ForEach(ItemQuery.Sort.allCases, id: \.self) { s in
                Button { lib.filter.sort = s } label: { if lib.filter.sort == s { Label(s.label, systemImage: "checkmark") } else { Text(s.label) } }
            }
        } label: { Image(systemName: "arrow.up.arrow.down").frame(width: 14, height: 16) }
            .menuStyle(.button).buttonStyle(Pill()).menuIndicator(.hidden).fixedSize().accessibilityLabel("Sort").help("Sort: \(lib.filter.sort.label)")
    }
}

struct FilterPopover: View {
    let lib = LibraryModel.shared
    @State private var find = ""

    private var tags: [(tag: String, count: Int)] {
        let q = ItemQuery.fold(find.trimmingCharacters(in: .whitespaces))
        return lib.tagCounts.filter { q.isEmpty || ItemQuery.fold($0.tag).contains(q) }
    }
    private var cats: [[String]] {
        let q = ItemQuery.fold(find.trimmingCharacters(in: .whitespaces))
        return lib.allCategoryPaths.filter { q.isEmpty || ItemQuery.fold($0.joined(separator: " ")).contains(q) }
    }

    var body: some View {
        let f = Bindable(lib).filter
        VStack(alignment: .leading, spacing: 12) {
            SearchBox(prompt: "Find a tag or category…", text: $find)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if tags.isEmpty && cats.isEmpty { Text("No tags or categories match").font(.system(size: 12.5)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 18) }
                    if !tags.isEmpty {
                        header("Tags")
                        ForEach(tags, id: \.tag) { t in
                            check("#\(t.tag)", count: t.count, on: lib.filter.tags.contains { ItemQuery.fold($0) == ItemQuery.fold(t.tag) }, indent: 0) { toggleTag(t.tag) }
                        }
                    }
                    if !cats.isEmpty {
                        header("Categories")
                        ForEach(cats, id: \.self) { p in
                            check(find.isEmpty ? (p.last ?? "") : p.joined(separator: " › "), count: nil, on: lib.filter.categories.contains(p), indent: find.isEmpty ? p.count - 1 : 0) {
                                if lib.filter.categories.contains(p) { lib.filter.categories.remove(p) } else { lib.filter.categories.insert(p) }
                            }
                        }
                    }
                }
            }.frame(maxHeight: 220).padding(4).background(Theme.fill.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            Divider()
            HStack(spacing: 6) {
                ForEach(ItemKind.allCases, id: \.self) { k in
                    Button { if lib.filter.kinds.contains(k) { lib.filter.kinds.remove(k) } else { lib.filter.kinds.insert(k) } } label: { Label(k.label, systemImage: k.symbol).labelStyle(.titleOnly) }
                        .buttonStyle(ChipStyle(on: lib.filter.kinds.contains(k)))
                }
            }
            Picker("Status", selection: f.status) { ForEach(ItemQuery.Status.allCases, id: \.self) { Text($0.label).tag($0) } }.pickerStyle(.segmented).labelsHidden()
            HStack(spacing: 6) {
                ToggleChip(title: "Today", symbol: "sun.max", isOn: f.onlyToday)
                ToggleChip(title: "Has reminders", symbol: "bell", isOn: f.withReminders)
                ToggleChip(title: "Has files", symbol: "paperclip", isOn: f.withAttachments)
            }
            HStack {
                Text("Date").font(.system(size: 12.5)).foregroundStyle(.secondary)
                Spacer()
                Picker("Date field", selection: f.dateField) {
                    ForEach(ItemQuery.DateField.allCases, id: \.self) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(ItemQuery.DateRange.quickPresets, id: \.self) { r in
                    Button {
                        if r == .custom {
                            if lib.filter.dateFrom == nil { lib.filter.dateFrom = Date() }
                            if lib.filter.dateTo == nil { lib.filter.dateTo = Date() }
                            lib.filter.added = .custom
                        } else {
                            lib.filter.added = (lib.filter.added == r && r != .any) ? .any : r
                        }
                    } label: { Text(r.shortLabel).frame(maxWidth: .infinity) }
                        .buttonStyle(ChipStyle(on: lib.filter.added == r && (r != .any || !lib.filter.hasDateFilter)))
                }
            }
            if lib.filter.added == .custom {
                VStack(alignment: .leading, spacing: 6) {
                    DatePicker("From", selection: customDateBinding(\.dateFrom), displayedComponents: .date).font(.system(size: 12))
                    DatePicker("To", selection: customDateBinding(\.dateTo), displayedComponents: .date).font(.system(size: 12))
                }
            }
            HStack {
                Spacer()
                Button("Clear filters") { lib.filter = lib.filter.clearingFilters() }.buttonStyle(Pill()).disabled(!lib.filter.isFiltering)
            }
        }.padding(14).frame(width: 320)
    }

    private func customDateBinding(_ kp: WritableKeyPath<ItemQuery, Date?>) -> Binding<Date> {
        Binding(
            get: { lib.filter[keyPath: kp] ?? Date() },
            set: { lib.filter[keyPath: kp] = $0; lib.filter.added = .custom }
        )
    }

    private func toggleTag(_ t: String) {
        if let have = lib.filter.tags.first(where: { ItemQuery.fold($0) == ItemQuery.fold(t) }) { lib.filter.tags.remove(have) } else { lib.filter.tags.insert(t) }
    }

    private func header(_ s: String) -> some View {
        Text(s.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.5).foregroundStyle(.secondary).padding(.horizontal, 6).padding(.top, 6).padding(.bottom, 2)
    }

    private func check(_ title: String, count: Int?, on: Bool, indent: Int, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: on ? "checkmark.square.fill" : "square").foregroundStyle(on ? Theme.highlight : Color.secondary)
                Text(title).font(.system(size: 12.5)).lineLimit(1)
                Spacer(minLength: 0)
                if let count { Text("\(count)").font(.system(size: 11)).foregroundStyle(.secondary) }
            }.padding(.leading, CGFloat(indent) * 14 + 6).padding(.trailing, 6).padding(.vertical, 3).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
    }
}

private struct ChipStyle: ButtonStyle {
    let on: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium)).lineLimit(1).padding(.horizontal, 9).padding(.vertical, 5)
            .foregroundStyle(on ? Theme.onSoft : Color.secondary)
            .background(on ? Theme.accentSoft : Theme.fill, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Theme.highlight.opacity(0.6) : .clear))
    }
}

/// Removable chips for every active filter, under the header.
struct ActiveFilterChips: View {
    let lib = LibraryModel.shared

    var body: some View {
        let f = lib.filter
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(f.tags.sorted(), id: \.self) { t in chip("#\(t)") { lib.filter.tags.remove(t) } }
                    ForEach(f.categories.sorted { $0.joined(separator: "/") < $1.joined(separator: "/") }, id: \.self) { p in chip(p.joined(separator: " › "), "folder") { lib.filter.categories.remove(p) } }
                    ForEach(f.kinds.sorted { $0.rawValue < $1.rawValue }, id: \.self) { k in chip(k.label, k.symbol) { lib.filter.kinds.remove(k) } }
                    if f.status != .any { chip(f.status.label) { lib.filter.status = .any } }
                    if f.onlyToday { chip("Today", "sun.max") { lib.filter.onlyToday = false } }
                    if f.withReminders { chip("Has reminders", "bell") { lib.filter.withReminders = false } }
                    if f.withAttachments { chip("Has files", "paperclip") { lib.filter.withAttachments = false } }
                    if f.hasDateFilter {
                        chip("\(f.dateField.label): \(dateChipLabel(f))", "calendar") {
                            lib.filter.added = .any; lib.filter.dateFrom = nil; lib.filter.dateTo = nil
                        }
                    }
                }
            }
            Button("Clear all") { lib.filter = lib.filter.clearingFilters() }.buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).fixedSize()
        }.padding(.horizontal, 22).padding(.vertical, 8)
    }

    private func dateChipLabel(_ f: ItemQuery) -> String {
        if f.added == .custom {
            let from = f.dateFrom?.formatted(date: .abbreviated, time: .omitted) ?? "…"
            let to = f.dateTo?.formatted(date: .abbreviated, time: .omitted) ?? "…"
            return "\(from) – \(to)"
        }
        return f.added.label
    }

    private func chip(_ title: String, _ symbol: String? = nil, remove: @escaping () -> Void) -> some View {
        Button(action: remove) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 10)) }
                Text(title).lineLimit(1)
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }.font(.system(size: 12, weight: .medium)).padding(.horizontal, 9).padding(.vertical, 4)
                .foregroundStyle(Theme.onSoft).background(Theme.accentSoft, in: Capsule())
        }.buttonStyle(.plain).help("Remove this filter").accessibilityLabel("Remove filter \(title)")
    }
}

/// Quick date filter bar below the pane header (Today, Yesterday, This week, etc., plus custom date range).
struct QuickDateBar: View {
    let lib = LibraryModel.shared
    @State private var showCustom = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Menu {
                    ForEach(ItemQuery.DateField.allCases, id: \.self) { df in
                        Button { lib.filter.dateField = df } label: {
                            if lib.filter.dateField == df { Label(df.label, systemImage: "checkmark") } else { Text(df.label) }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "calendar").font(.system(size: 10.5))
                        Text(lib.filter.dateField.label)
                        Image(systemName: "chevron.down").font(.system(size: 8.5, weight: .semibold))
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: 7))
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .help("Filter by Created or Updated date")

                ForEach(ItemQuery.DateRange.quickPresets, id: \.self) { r in
                    let active = lib.filter.added == r && (r != .any || !lib.filter.hasDateFilter)
                    Button {
                        if r == .custom {
                            if lib.filter.dateFrom == nil { lib.filter.dateFrom = Date() }
                            if lib.filter.dateTo == nil { lib.filter.dateTo = Date() }
                            lib.filter.added = .custom
                            showCustom = true
                        } else {
                            lib.filter.added = (lib.filter.added == r && r != .any) ? .any : r
                        }
                    } label: {
                        Text(r.shortLabel)
                            .font(.system(size: 11.5, weight: .medium))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .foregroundStyle(active ? Theme.onSoft : Color.secondary)
                            .background(active ? Theme.accentSoft : Theme.fill.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(active ? Theme.highlight.opacity(0.5) : .clear))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: r == .custom ? $showCustom : .constant(false), arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Custom date range (\(lib.filter.dateField.label))").font(.system(size: 12.5, weight: .semibold))
                            DatePicker("From", selection: Binding(get: { lib.filter.dateFrom ?? Date() }, set: { lib.filter.dateFrom = $0; lib.filter.added = .custom }), displayedComponents: .date)
                            DatePicker("To", selection: Binding(get: { lib.filter.dateTo ?? Date() }, set: { lib.filter.dateTo = $0; lib.filter.added = .custom }), displayedComponents: .date)
                            HStack {
                                Button("Reset") { lib.filter.added = .any; lib.filter.dateFrom = nil; lib.filter.dateTo = nil; showCustom = false }.buttonStyle(Pill())
                                Spacer()
                                Button("Done") { showCustom = false }.buttonStyle(Pill(kind: .primary))
                            }
                        }.padding(12).frame(width: 240)
                    }
                }
            }.padding(.horizontal, 22).padding(.vertical, 7)
        }
        .background(Theme.pane)
        .overlay(alignment: .bottom) { Divider() }
    }
}
