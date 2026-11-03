import SwiftUI
import WidgetKit
import ActivityKit

private struct ParkingEntry: TimelineEntry {
    let date: Date
    let snapshot: [String: String]
    let isDemo: Bool
    var draft: [String: Any] = [:]
    var floors: [String] = []
}

private struct ParkingProvider: TimelineProvider {
    func placeholder(in context: Context) -> ParkingEntry {
        ParkingEntry(date: Date(), snapshot: ["floor": "B2", "zone": "C", "spot": "24"], isDemo: true, draft: ["enabled": true, "floor": "B2", "zone": "C"], floors: ["F3", "F2", "F1", "B1", "B2", "B3"])
    }
    func getSnapshot(in context: Context, completion: @escaping (ParkingEntry) -> Void) { completion(read()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ParkingEntry>) -> Void) {
        // No background polling. User-triggered intents perform authenticated writes.
        let entry = read()
        if let until = entry.draft["busyUntil"] as? Double, until > Date().timeIntervalSince1970 {
            // Single local recovery after a killed intent; no periodic network work.
            completion(Timeline(entries: [entry], policy: .after(Date(timeIntervalSince1970: until + 1))))
        } else { completion(Timeline(entries: [entry], policy: .never)) }
    }
    private func read() -> ParkingEntry {
        let raw = UserDefaults(suiteName: "group.com.kang88.carcar")?.dictionary(forKey: "parkingSnapshot") ?? [:]
        let (draft, floors): ([String: Any], [String]) = (try? WidgetSession.locked { (try WidgetSession.display(), WidgetSession.options("floor")) }) ?? ([:], [])
        return ParkingEntry(date: Date(), snapshot: raw.compactMapValues { $0 as? String }, isDemo: raw["isDemo"] as? Bool ?? false, draft: draft, floors: floors)
    }
}

private enum WidgetPalette {
    static let ink = Color(red: 0.11, green: 0.23, blue: 0.19)
    static let lime = Color(red: 0.86, green: 0.92, blue: 0.71)
    static let mist = Color(red: 0.75, green: 0.83, blue: 0.78)
    static let chip = Color.white.opacity(0.14)
}

private struct ParkingWidgetView: View {
    let entry: ParkingEntry
    @Environment(\.widgetFamily) private var family
    private var recordTime: String {
        guard let raw = entry.snapshot["updatedAt"], !raw.isEmpty else { return "앱에서 확인" }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = parser.date(from: raw)
        if date == nil {
            parser.formatOptions = [.withInternetDateTime]
            date = parser.date(from: raw)
        }
        guard let date = date else { return "앱에서 확인" }
        let text = date.formatted(date: .numeric, time: .shortened)
        return entry.isDemo ? "체험 · \(text)" : text
    }
    private var location: String? {
        guard let floor = entry.snapshot["floor"], !floor.isEmpty else { return nil }
        return "\(floor) · \(entry.snapshot["zone"] ?? "") \(entry.snapshot["spot"] ?? "")".trimmingCharacters(in: .whitespaces)
    }
    private var enabled: Bool { entry.draft["enabled"] as? Bool == true }
    private var interactive: Bool { enabled && entry.draft["busy"] as? Bool != true }
    private var floors: [String] { enabled ? Array(entry.floors.prefix(12)) : [] }
    private var large: Bool { family == .systemLarge }

    var body: some View {
        VStack(alignment: .leading, spacing: large ? 6 : 3) {
            // No app name: the location is the headline.
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                if let location = location {
                    Text(location)
                        .font(.system(size: large ? 34 : (family == .systemSmall ? 30 : 26), weight: .bold, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .privacySensitive()
                } else {
                    Text("주차 위치 없음").font(.system(.title3, design: .rounded, weight: .bold))
                }
                if family != .systemSmall {
                    Spacer(minLength: 0)
                    Text(recordTime).font(.caption2).foregroundStyle(WidgetPalette.mist).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            if family == .systemSmall {
                Text(recordTime).font(.caption2).foregroundStyle(WidgetPalette.mist).lineLimit(1).minimumScaleFactor(0.8)
            }
            Text(entry.draft["status"] as? String ?? "층을 누른 뒤 등록을 누르면 서버에 저장돼요")
                .font(.caption2).foregroundStyle(WidgetPalette.mist).lineLimit(1).minimumScaleFactor(0.8)
            if family != .systemSmall {
                Spacer(minLength: 2)
                controls
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, large ? 16 : 12).padding(.vertical, large ? 16 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(WidgetPalette.ink, for: .widget)
        .widgetURL(URL(string: "carcar://home"))
    }

    private var controls: some View {
        let chipHeight: CGFloat = large ? 44 : 26
        let actionHeight: CGFloat = large ? 48 : 30
        let rows = stride(from: 0, to: floors.count, by: 6).map { Array(floors[$0..<min($0 + 6, floors.count)]) }
        return VStack(spacing: large ? 6 : 3) {
            ForEach(Array(rows.enumerated()), id: \.offset) { item in
                HStack(spacing: large ? 6 : 3) {
                    ForEach(item.element, id: \.self) { floor in
                        let selected = floor == entry.draft["floor"] as? String
                        Button(intent: ParkingActionIntent("floor", value: floor)) {
                            Text(floor)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .lineLimit(1).minimumScaleFactor(0.6)
                                .frame(maxWidth: .infinity, minHeight: chipHeight, maxHeight: chipHeight)
                                .background(selected ? WidgetPalette.lime : WidgetPalette.chip, in: RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(selected ? WidgetPalette.ink : .white)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(selected ? "\(floor) 선택됨" : "\(floor) 선택")
                    }
                }
            }
            HStack(spacing: large ? 6 : 3) {
                Button(intent: ParkingActionIntent("zone")) {
                    Text(enabled ? "\(entry.draft["zone"] as? String ?? "") 구역" : "구역")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: actionHeight, maxHeight: actionHeight)
                        .background(WidgetPalette.chip, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("다음 구역 선택")
                Button(intent: ParkingActionIntent("save")) {
                    Text(entry.draft["busy"] as? Bool == true ? "저장 중…" : "등록")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: actionHeight, maxHeight: actionHeight)
                        .background(WidgetPalette.lime, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(WidgetPalette.ink)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("선택한 층과 구역을 서버에 등록")
            }
        }
        .disabled(!interactive)
        .opacity(interactive ? 1 : 0.5)
    }
}

struct ParkingHomeWidget: Widget {
    let kind = "ParkingHomeWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ParkingProvider()) { ParkingWidgetView(entry: $0) }
            .configurationDisplayName("마지막 주차 위치")
            .description("마지막 주차 위치를 보고 층을 눌러 바로 등록해요.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
            .contentMarginsDisabled()
    }
}

struct ParkingLiveWidget: Widget {
    private let ink = Color(red: 0.13, green: 0.24, blue: 0.20)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ParkingAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "car.fill")
                    .font(.title3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(context.state.floor) · \(context.state.zone) \(context.state.spot)")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .privacySensitive()
                    HStack(spacing: 6) {
                        Text("\(context.attributes.vehicleName) 찾기")
                            .lineLimit(1).truncationMode(.tail)
                        if context.isStale {
                            Text("시간 만료").fixedSize()
                        } else {
                            Text(timerInterval: min(Date(), context.state.expiresAt)...context.state.expiresAt, countsDown: true)
                                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                                .frame(width: 64, alignment: .leading)
                        }
                    }.font(.caption2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                StopFindingButton(activityID: context.activityID, tint: ink)
            }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .foregroundStyle(ink)
                .activityBackgroundTint(Color(red: 0.95, green: 0.96, blue: 0.93))
                .activitySystemActionForegroundColor(ink)
                .widgetURL(URL(string: "carcar://home"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Image(systemName: "car.fill").accessibilityHidden(true)
                        Text(context.state.floor).bold().lineLimit(1).minimumScaleFactor(0.7)
                    }.privacySensitive()
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StopFindingButton(activityID: context.activityID, tint: .white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.isStale ? "앱에서 최신 위치 확인" : "\(context.state.zone) 구역 · \(context.state.spot)")
                        .lineLimit(1).minimumScaleFactor(0.7).privacySensitive()
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Image(systemName: "car.fill").accessibilityHidden(true)
                    Text(context.state.floor).bold().lineLimit(1).minimumScaleFactor(0.7)
                }.privacySensitive()
            }
              compactTrailing: { EmptyView() }
              minimal: { Image(systemName: "car.fill") }
                .widgetURL(URL(string: "carcar://home"))
        }
    }
}

private struct StopFindingButton: View {
    let activityID: String
    let tint: Color

    var body: some View {
        Button(intent: StopParkingActivityIntent(activityID: activityID)) {
            Label("종료", systemImage: "xmark")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .frame(minWidth: 44, minHeight: 44)
                .background(tint.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .accessibilityLabel("차량 찾기 표시 종료")
        .accessibilityHint("현재 표시만 닫고 주차 기록은 유지합니다")
    }
}

@main
struct ParkingWidgets: WidgetBundle {
    var body: some Widget { ParkingHomeWidget(); ParkingLiveWidget() }
}
