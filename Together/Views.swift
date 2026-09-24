import SwiftUI
import Charts
import UniformTypeIdentifiers
import PDFKit

enum AppTheme: String, CaseIterable, Identifiable {
    case charcoal, mint, lavender
    var id: String { rawValue }
    var name: String {
        switch self { case .charcoal: "Dark charcoal"; case .mint: "Mint"; case .lavender: "Lavender" }
    }
    var canvas: Color {
        switch self {
        case .charcoal: Color(red: 0.045, green: 0.063, blue: 0.075)
        case .mint: Color(red: 0.035, green: 0.10, blue: 0.085)
        case .lavender: Color(red: 0.085, green: 0.065, blue: 0.13)
        }
    }
    var panel: Color {
        switch self {
        case .charcoal: Color(red: 0.085, green: 0.11, blue: 0.125)
        case .mint: Color(red: 0.07, green: 0.17, blue: 0.14)
        case .lavender: Color(red: 0.15, green: 0.12, blue: 0.21)
        }
    }
    var accent: Color {
        switch self {
        case .charcoal: Color(red: 0.67, green: 0.92, blue: 0.76)
        case .mint: Color(red: 0.48, green: 0.92, blue: 0.76)
        case .lavender: Color(red: 0.80, green: 0.73, blue: 0.98)
        }
    }
    var secondaryAccent: Color { self == .lavender ? Color(red: 0.92, green: 0.73, blue: 0.87) : Color(red: 0.73, green: 0.69, blue: 0.91) }
    var muted: Color { Color(red: 0.64, green: 0.68, blue: 0.70) }
}
private struct AppThemeKey: EnvironmentKey { static let defaultValue = AppTheme.charcoal }
extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}
private struct PanelStyle: ViewModifier {
    @Environment(\.appTheme) private var theme
    func body(content: Content) -> some View { content.padding(18).background(theme.panel, in: RoundedRectangle(cornerRadius: 22)) }
}
extension View {
    func panel() -> some View { modifier(PanelStyle()) }
}
struct RootView: View {
    @Environment(\.appTheme) private var theme
    @EnvironmentObject var store: Store
    @State private var tab = 0
    @State private var importing = false
    var body: some View {
        ZStack {
            theme.canvas.ignoresSafeArea()
            if store.unlocked {
                TabView(selection: $tab) {
                    NavigationStack { Dashboard(importing: $importing, tab: $tab) }.tabItem { Label("Overview", systemImage: "square.grid.2x2.fill") }.tag(0)
                    NavigationStack { ActivityView() }.tabItem { Label("Activity", systemImage: "list.bullet.rectangle") }.tag(1)
                    NavigationStack { CardsView() }.tabItem { Label("Cards", systemImage: "creditcard") }.tag(2)
                    NavigationStack { StatementsView(importing: $importing) }.tabItem { Label("Statements", systemImage: "doc.text") }.tag(3)
                    NavigationStack { HouseholdView() }.tabItem { Label("Household", systemImage: "person.2") }.tag(4)
                }.tint(theme.accent)
            } else {
                VStack(spacing: 24) {
                    Image(systemName: "lock.shield").font(.system(size: 54)).foregroundStyle(theme.accent)
                    Text("Your space. Together.").font(.title.bold())
                    Text("Unlock to see your household finances.").foregroundStyle(theme.muted)
                    Button("Unlock Together") { Task { await store.authenticate() } }.buttonStyle(PrimaryButton())
                }.padding(30)
            }
        }
        .sheet(isPresented: $importing) { ImportView() }
        .sheet(isPresented: Binding(get: { store.sharing != nil }, set: { if !$0 { store.sharing = nil } })) {
            if let share = store.sharing, let cloud = store.cloud { SharingView(share: share, container: cloud.container) { store.error = $0 } }
        }
        .alert("A little attention needed", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
    }
}
struct PrimaryButton: ButtonStyle {
    @Environment(\.appTheme) private var theme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 16)
            .foregroundStyle(theme.canvas).background(theme.accent.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 15))
    }
}
struct Page<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 24) { content }.padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 28) }.background(theme.canvas).toolbarBackground(theme.canvas, for: .navigationBar).toolbarBackground(.visible, for: .tabBar).toolbarBackground(theme.panel, for: .tabBar) }
}
struct SectionHeading: View {
    @Environment(\.appTheme) private var theme
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title3.weight(.semibold))
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(theme.muted) }
        }
    }
}
struct Dashboard: View {
    @Environment(\.appTheme) private var theme
    @EnvironmentObject var store: Store
    @Binding var importing: Bool
    @Binding var tab: Int
    var entries: [Entry] { store.household.entries }
    var monthly: [Entry] { entries.filter { Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) && $0.amount > 0 } }
    var total: Double { monthly.reduce(0) { $0 + $1.amount } }
    var flags: [Entry] { entries.filter { Insights.unusual($0, in: entries) } }
    var recurring: Set<UUID> { Insights.recurring(entries) }
    var categories: [(Category, Double)] { Dictionary(grouping: monthly, by: \.category).map { ($0.key, $0.value.reduce(0) { $0 + $1.amount }) }.sorted { $0.1 > $1.1 } }
    var body: some View {
        Page {
            HStack {
                HStack(spacing: 9) { Image(systemName: "circle.hexagongrid.fill").foregroundStyle(theme.accent); Text("together").tracking(-1).font(.system(size: 26, weight: .semibold)) }
                Spacer()
                Button { tab = 4 } label: { HStack(spacing: -8) { avatar("Y", theme.accent); avatar("+", theme.secondaryAccent) } }.accessibilityLabel("Our household")
                SettingsButton()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("A little clarity.\nA lot more together.").font(.system(size: 30, weight: .semibold, design: .rounded)).tracking(-0.7)
                Text("Your household, all in one place.").font(.subheadline).foregroundStyle(theme.muted)
            }
            if store.demo {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").foregroundStyle(theme.accent)
                    Text("A preview of life together").font(.caption)
                    Spacer()
                    Text("DEMO").font(.system(size: 9, weight: .bold)).tracking(1.2).padding(6).background(Color.white.opacity(0.08), in: Capsule())
                }.padding(12).background(theme.panel, in: RoundedRectangle(cornerRadius: 12))
            }
            VStack(alignment: .leading, spacing: 18) {
                HStack { Label("MONTHLY SPENDING", systemImage: "arrow.up.right").font(.system(size: 10, weight: .bold)).tracking(1.6); Spacer(); Text(Date(), format: .dateTime.month(.abbreviated).year()).font(.caption) }.foregroundStyle(theme.canvas.opacity(0.7))
                Text(total.money).font(.system(size: 43, weight: .medium, design: .rounded)).tracking(-1.5).contentTransition(.numericText())
                HStack(spacing: 5) {
                    ForEach(0..<(Calendar.current.range(of: .day, in: .month, for: Date())?.count ?? 31), id: \.self) { index in
                        let dayTotal = monthly.filter { Calendar.current.component(.day, from: $0.date) == index + 1 }.reduce(0) { $0 + $1.amount }
                        RoundedRectangle(cornerRadius: 3).fill(theme.canvas.opacity(index == Calendar.current.component(.day, from: Date()) - 1 ? 0.8 : 0.18)).frame(height: max(6, min(46, dayTotal / max(total, 1) * 150))).frame(maxHeight: 46, alignment: .bottom)
                    }
                }.accessibilityLabel("Daily spending this month")
                HStack { Text("\(monthly.count) purchases this month"); Spacer(); Image(systemName: "checkmark.shield") }.font(.caption).foregroundStyle(theme.canvas.opacity(0.7))
            }.padding(22).foregroundStyle(theme.canvas).background(LinearGradient(colors: [theme.accent, theme.accent.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 25))
            HStack(spacing: 12) {
                metric("Card balances", value: store.household.cards.reduce(0) { $0 + $1.balance }.money, icon: "creditcard", color: theme.secondaryAccent)
                metric("Recurring", value: "\(Set(entries.filter { recurring.contains($0.id) }.map { Insights.key($0.merchant) }).count) found", icon: "arrow.trianglehead.2.clockwise.rotate.90", color: theme.accent)
            }
            Button { importing = true } label: { Label("Upload a statement", systemImage: "plus.circle.fill") }.buttonStyle(PrimaryButton())
            if let flag = flags.first {
                NavigationLink { InsightsView() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkle.magnifyingglass").font(.title2).foregroundStyle(Color.orange)
                        VStack(alignment: .leading, spacing: 5) { Text("Worth a second look").font(.subheadline.weight(.semibold)).foregroundStyle(.white); Text("\(flag.merchant) · \(flag.amount.money)").font(.caption).foregroundStyle(theme.muted) }
                        Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(theme.muted)
                    }.panel()
                }.buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 18) {
                SectionHeading(title: "Where it went", subtitle: "Your spending by category this month")
                if categories.isEmpty { Text("Your categories will appear after your first import.").font(.subheadline).foregroundStyle(theme.muted) }
                ForEach(Array(categories.prefix(4).enumerated()), id: \.element.0) { index, item in
                    HStack(spacing: 12) {
                        Image(systemName: item.0.icon).foregroundStyle(index == 0 ? theme.accent : theme.secondaryAccent).frame(width: 34, height: 34).background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 7) {
                            HStack { Text(item.0.rawValue).font(.subheadline); Spacer(); Text(item.1.money).font(.subheadline.monospacedDigit()) }
                            GeometryReader { proxy in Capsule().fill(Color.white.opacity(0.06)).overlay(alignment: .leading) { Capsule().fill(index == 0 ? theme.accent : theme.secondaryAccent.opacity(0.7)).frame(width: proxy.size.width * item.1 / max(total, 1)) } }.frame(height: 4)
                        }
                    }
                }
            }.panel()
            HStack { SectionHeading(title: "Recent activity"); Spacer(); Button("See all") { tab = 1 }.font(.caption).foregroundStyle(theme.accent) }
            VStack(spacing: 18) { ForEach(entries.sorted { $0.date > $1.date }.prefix(4)) { entry in NavigationLink { EntryEditor(entry: entry) } label: { EntryRow(entry: entry, recurring: recurring.contains(entry.id)) }.buttonStyle(.plain) } }
            HStack { Spacer(); Label("Your finances. Your private space.", systemImage: "lock.shield").font(.caption2).foregroundStyle(theme.muted); Spacer() }
        }.toolbar(.hidden, for: .navigationBar)
    }
    func avatar(_ text: String, _ color: Color) -> some View { Text(text).font(.caption.bold()).foregroundStyle(color).frame(width: 34, height: 34).background(theme.panel, in: Circle()).overlay(Circle().stroke(theme.canvas, lineWidth: 3)) }
    func metric(_ title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 11) { Image(systemName: icon).foregroundStyle(color); Text(value).font(.title3.weight(.semibold)); Text(title).font(.caption).foregroundStyle(theme.muted) }.frame(maxWidth: .infinity, alignment: .leading).panel()
    }
}
struct EntryRow: View {
    @Environment(\.appTheme) private var theme
    let entry: Entry
    var recurring = false
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.category.icon).font(.system(size: 17)).foregroundStyle(theme.accent).frame(width: 42, height: 42).background(theme.panel, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 5) { Text(entry.merchant).font(.subheadline.weight(.medium)).lineLimit(1); Text(entry.category.rawValue + " · " + entry.date.formatted(.dateTime.month(.abbreviated).day())).font(.caption2).foregroundStyle(theme.muted) }
            Spacer(minLength: 2)
            VStack(alignment: .trailing, spacing: 5) { Text(entry.amount.money).font(.subheadline.monospacedDigit()); if recurring { Text("Recurring").font(.system(size: 10)).foregroundStyle(theme.accent) } }
        }.foregroundStyle(.white)
    }
}
struct ActivityView: View {
    @Environment(\.appTheme) private var theme
    @EnvironmentObject var store: Store
    @State private var search = ""
    @State private var filter = "All"
    var recurring: Set<UUID> { Insights.recurring(store.household.entries) }
    var filtered: [Entry] {
        store.household.entries.filter { entry in
            (search.isEmpty || entry.merchant.localizedCaseInsensitiveContains(search) || entry.category.rawValue.localizedCaseInsensitiveContains(search)) && (filter == "All" || (filter == "Recurring" && recurring.contains(entry.id)) || (filter == "To review" && Insights.unusual(entry, in: store.household.entries)))
        }.sorted { $0.date > $1.date }
    }
    var body: some View {
        Page {
            SectionHeading(title: "Every little detail", subtitle: "Search, review, and make it yours.")
            Picker("Filter", selection: $filter) { ForEach(["All", "Recurring", "To review"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
            if filtered.isEmpty { ContentUnavailableView("Nothing here yet", systemImage: "tray", description: Text("Import a statement or try a different filter.")) }
            ForEach(filtered) { entry in NavigationLink { EntryEditor(entry: entry) } label: { EntryRow(entry: entry, recurring: recurring.contains(entry.id)) }.buttonStyle(.plain) }
        }.navigationTitle("Activity").toolbar { ToolbarItem(placement: .topBarTrailing) { SettingsButton() } }.searchable(text: $search, prompt: "Merchant or category").refreshable { await store.sync() }
    }
}
struct EntryEditor: View {
    @Environment(\.appTheme) private var theme
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State var entry: Entry
    var body: some View {
        Form {
            Section("Transaction") { TextField("Merchant", text: $entry.merchant); TextField("Amount", value: $entry.amount, format: .number).keyboardType(.numbersAndPunctuation); DatePicker("Date", selection: $entry.date, displayedComponents: .date); TextField("Account", text: $entry.account) }
            Section("Category") { Picker("Category", selection: $entry.category) { ForEach(Category.allCases) { Text($0.rawValue).tag($0) } } }
            Section { Toggle("Reviewed by me", isOn: $entry.reviewed) } footer: { Text("Unusual charge flags are suggestions based on amount and your imported history. Review the statement to confirm a charge.") }
            Section { Button("Save changes") { entry.modified = Date(); if let index = store.household.entries.firstIndex(where: { $0.id == entry.id }) { store.household.entries[index] = entry; store.save() }; dismiss() }.disabled(entry.merchant.isEmpty || !entry.amount.isFinite) }
        }.scrollContentBackground(.hidden).background(theme.canvas).navigationTitle("Transaction").navigationBarTitleDisplayMode(.inline)
    }
}
struct InsightsView: View {
    @Environment(\.appTheme) private var theme
    @EnvironmentObject var store: Store
    var body: some View {
        Page { Text("These charges stand out from your imported spending. A flag doesn’t mean a charge is fraudulent.").font(.subheadline).foregroundStyle(theme.muted)
            ForEach(store.household.entries.filter { Insights.unusual($0, in: store.household.entries) }) { entry in NavigationLink { EntryEditor(entry: entry) } label: { EntryRow(entry: entry) }.buttonStyle(.plain) }
        }.navigationTitle("Worth a look")
    }
}
struct CardsView: View {
    @Environment(\.appTheme) private var theme
    @EnvironmentObject var store: Store
    @State var adding = false
    var body: some View {
        Page {
            VStack(alignment: .leading, spacing: 8) { Text("TOTAL CARD DEBT").font(.caption).tracking(2).foregroundStyle(theme.muted); Text(store.household.cards.reduce(0) { $0 + $1.balance }.money).font(.system(size: 40, weight: .medium, design: .rounded)); Text("Statement balances · updated by you").font(.caption).foregroundStyle(theme.muted) }
            ForEach(Array(store.household.cards.enumerated()), id: \.element.id) { index, card in
                NavigationLink { CardEditor(card: card) } label: {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack { Text(card.name).font(.headline); Spacer(); Image(systemName: "wave.3.right").rotationEffect(.degrees(90)) }
                        Text("••••  ••••  ••••  " + card.lastFour).font(.system(.subheadline, design: .monospaced)).foregroundStyle(.white.opacity(0.65))
                        HStack(alignment: .bottom) { VStack(alignment: .leading, spacing: 5) { Text("Statement balance").font(.caption); Text(card.balance.money).font(.title.weight(.semibold)) }; Spacer(); Text("Due " + card.due.formatted(.dateTime.month(.abbreviated).day())).font(.caption) }
                        VStack(spacing: 8) { ProgressView(value: min(max(card.balance / max(card.limit, 1), 0), 1)).tint(index == 0 ? theme.accent : theme.secondaryAccent); HStack { Text("\(Int(card.balance / max(card.limit, 1) * 100))% utilized"); Spacer(); Text(card.limit.money + " limit") }.font(.caption2) }
                        HStack { Text("Minimum payment"); Spacer(); Text(card.minimum.money); Image(systemName: "chevron.right") }.font(.caption)
                    }.padding(24).background(LinearGradient(colors: index == 0 ? [theme.accent.opacity(0.22), theme.panel] : [theme.secondaryAccent.opacity(0.22), theme.panel], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24)).overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.07))).foregroundStyle(.white)
                }.buttonStyle(.plain)
            }
            Button { adding = true } label: { Label("Add a credit card", systemImage: "plus") }.buttonStyle(PrimaryButton())
            Text("Only a nickname and the last four digits are needed. Update balances from each statement; imported purchases don’t change your balance automatically.").font(.caption).foregroundStyle(theme.muted)
        }.navigationTitle("Your cards").toolbar { ToolbarItem(placement: .topBarTrailing) { SettingsButton() } }.sheet(isPresented: $adding) { NavigationStack { CardEditor(card: Card(name: "", lastFour: "", balance: 0, limit: 1000, due: Date(), minimum: 0)) } }
    }
}
struct CardEditor: View {
    @Environment(\.appTheme) private var theme
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State var card: Card
    var valid: Bool { !card.name.trimmingCharacters(in: .whitespaces).isEmpty && card.lastFour.count == 4 && card.lastFour.allSatisfy(\.isNumber) && card.balance >= 0 && card.balance.isFinite && card.limit > 0 && card.limit.isFinite && card.minimum >= 0 && card.minimum.isFinite }
    var body: some View {
        Form {
            Section("Card details") { TextField("Card nickname", text: $card.name); TextField("Last four digits only", text: $card.lastFour).keyboardType(.numberPad) }
            Section("From your latest statement") { currency("Balance", $card.balance); currency("Credit limit", $card.limit); currency("Minimum payment", $card.minimum); DatePicker("Payment due", selection: $card.due, displayedComponents: .date) }
            if store.demo { Section { Text("Saving a card starts your real household and removes the preview data.").foregroundStyle(theme.muted) } }
        }.scrollContentBackground(.hidden).background(theme.canvas).navigationTitle("Card details").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Save") { if store.demo { store.startHousehold() }; card.modified = Date(); if let i = store.household.cards.firstIndex(where: { $0.id == card.id }) { store.household.cards[i] = card } else { store.household.cards.append(card) }; store.save(); dismiss() }.disabled(!valid) } }
    }
    func currency(_ title: String, _ value: Binding<Double>) -> some View { HStack { Text(title); TextField(title, value: value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) } }
}
struct StatementsView: View {
    @Environment(\.appTheme) private var theme
    @EnvironmentObject var store: Store
    @Binding var importing: Bool
    var body: some View {
        Page {
            VStack(spacing: 18) { Image(systemName: "doc.text.viewfinder").font(.system(size: 42)).foregroundStyle(theme.accent); Text("Less paperwork.\nMore perspective.").font(.title2.bold()).multilineTextAlignment(.center); Text("Upload a PDF, CSV, or text statement. We’ll suggest categories, then you review.").font(.subheadline).foregroundStyle(theme.muted).multilineTextAlignment(.center); Button("Upload a statement") { importing = true }.buttonStyle(PrimaryButton()); Label("Read on your device", systemImage: "lock.shield").font(.caption).foregroundStyle(theme.muted) }.frame(maxWidth: .infinity).panel()
            SectionHeading(title: "Your documents", subtitle: "Original statements, kept with your household")
            if store.household.statements.isEmpty { Text("Your first statement starts the story.").foregroundStyle(theme.muted).font(.subheadline) }
            ForEach(store.household.statements.sorted { $0.imported > $1.imported }) { statement in
                NavigationLink { DocumentView(statement: statement) } label: {
                    HStack { Image(systemName: "doc.text.fill").foregroundStyle(theme.accent); VStack(alignment: .leading, spacing: 5) { Text(statement.name).lineLimit(1); Text("\(statement.count) transactions · \(statement.imported.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(theme.muted) }; Spacer(); Image(systemName: "chevron.right").font(.caption) }.panel()
                }.buttonStyle(.plain)
            }
        }.navigationTitle("Statements").toolbar { ToolbarItem(placement: .topBarTrailing) { SettingsButton() } }
    }
}
struct DocumentView: View {
    @Environment(\.appTheme) private var theme
    let statement: Statement
    var body: some View {
        Group { if statement.name.lowercased().hasSuffix(".pdf") { PDFPreview(data: statement.data) } else { ScrollView { Text(String(data: statement.data, encoding: .utf8) ?? "Document unavailable").font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding() } } }.navigationTitle(statement.name).navigationBarTitleDisplayMode(.inline)
    }
}
struct PDFPreview: UIViewRepresentable {
    @Environment(\.appTheme) private var theme
    let data: Data
    func makeUIView(context: Context) -> PDFView { let view = PDFView(); view.document = PDFDocument(data: data); view.autoScales = true; return view }
    func updateUIView(_ uiView: PDFView, context: Context) {}
}
struct HouseholdView: View {
    @Environment(\.appTheme) private var theme
    @EnvironmentObject var store: Store
    var body: some View {
        Page {
            VStack(alignment: .leading, spacing: 18) { Image(systemName: "person.2.fill").font(.largeTitle).foregroundStyle(theme.accent); SectionHeading(title: "One home. One clear picture.", subtitle: "A private space for you and your partner."); Text(store.demo ? "You’re exploring sample data. Start fresh when you’re ready." : store.cloudStatus).font(.subheadline).foregroundStyle(theme.muted)
                if store.demo { Button("Start our household") { store.startHousehold() }.buttonStyle(PrimaryButton()) }
                else { Button { Task { await store.invite() } } label: { Label("Invite or manage partner", systemImage: "person.badge.plus") }.buttonStyle(PrimaryButton()); Button { Task { await store.sync() } } label: { Label(store.syncing ? "Syncing…" : "Sync household", systemImage: "arrow.triangle.2.circlepath") }.disabled(store.syncing || store.cloud == nil) }
            }.panel()
            VStack(alignment: .leading, spacing: 18) {
                SectionHeading(title: "A little peace of mind")
                Label("No bank login required", systemImage: "building.columns"); Label("Statement reading stays on-device", systemImage: "iphone"); Label("Files protected by iOS Data Protection", systemImage: "lock.doc")
                if store.lockEnabled { Label("App lock is enabled", systemImage: "faceid"); Button("Lock now") { store.unlocked = false } }
                else { Button { Task { await store.authenticate(enable: true) } } label: { Label("Enable Face ID / passcode lock", systemImage: "faceid") } }
            }.font(.subheadline).panel()
            Text(store.cloud == nil ? "iCloud sharing is not configured in this preview build. Your real data stays on this phone. Enable CloudKit and sign the app with your Apple developer account to invite your partner." : "Private iCloud sharing includes your transactions, card details, and uploaded documents. Invite only your partner. Both people can edit. Open the app or pull to refresh Activity to sync.").font(.caption).foregroundStyle(theme.muted)
        }.navigationTitle("Our household").toolbar { ToolbarItem(placement: .topBarTrailing) { SettingsButton() } }
    }
}

struct SettingsButton: View {
    @Environment(\.appTheme) private var theme
    @State private var showingSettings = false
    var body: some View {
        Button { showingSettings = true } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(theme.accent)
                .frame(width: 44, height: 44)
                .background(theme.panel, in: Circle())
        }
        .accessibilityLabel("Settings")
        .sheet(isPresented: $showingSettings) { SettingsView() }
    }
}
struct SettingsView: View {
    @AppStorage("appearanceTheme") private var selection: AppTheme = .charcoal
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Page {
                SectionHeading(title: "Make it feel like you", subtitle: "Choose your color scheme.")
                ForEach(AppTheme.allCases) { option in
                    Button { selection = option } label: {
                        HStack(spacing: 16) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(option.canvas)
                                .frame(width: 62, height: 54)
                                .overlay {
                                    VStack(spacing: 5) {
                                        RoundedRectangle(cornerRadius: 4).fill(option.accent).frame(width: 40, height: 15)
                                        HStack(spacing: 4) {
                                            RoundedRectangle(cornerRadius: 3).fill(option.panel)
                                            RoundedRectangle(cornerRadius: 3).fill(option.secondaryAccent.opacity(0.5))
                                        }.frame(width: 40, height: 10)
                                    }
                                }
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.15)))
                            Text(option.name).font(.headline).foregroundStyle(.white)
                            Spacer()
                            Image(systemName: selection == option ? "checkmark.circle.fill" : "circle")
                                .font(.title2).foregroundStyle(selection == option ? selection.accent : selection.muted)
                        }.panel()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.name)
                    .accessibilityValue(selection == option ? "Selected" : "Not selected")
                    .accessibilityAddTraits(selection == option ? [.isSelected] : [])
                }
                Text("Your theme changes immediately and is saved on this iPhone. Your partner can choose their own.")
                    .font(.subheadline).foregroundStyle(selection.muted)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .environment(\.appTheme, selection)
        .tint(selection.accent)
        .preferredColorScheme(.dark)
    }
}
