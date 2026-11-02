import SwiftUI
import WidgetKit
import ActivityKit

private struct ParkingEntry: TimelineEntry {
    let date: Date
    let snapshot: [String: String]
    let isDemo: Bool
    var draft: [String: Any] = [:]
}

private struct ParkingProvider: TimelineProvider {
    func placeholder(in context: Context) -> ParkingEntry {
        ParkingEntry(date: Date(), snapshot: ["floor": "B2", "zone": "C", "spot": "24"], isDemo: true)
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
        return ParkingEntry(date: Date(), snapshot: raw.compactMapValues { $0 as? String }, isDemo: raw["isDemo"] as? Bool ?? false, draft: (try? WidgetSession.locked { try WidgetSession.display() }) ?? [:])
    }
}

private struct ParkingWidgetView: View {
    let entry: ParkingEntry
    @Environment(\.widgetFamily) private var family
    private var recordTime: String {
        guard let raw = entry.snapshot["updatedAt"], !raw.isEmpty else { return "기록 시각 확인 필요" }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = parser.date(from: raw)
        if date == nil {
            parser.formatOptions = [.withInternetDateTime]
            date = parser.date(from: raw)
        }
        guard let date = date else { return "기록 시각 확인 필요" }
        return "기록 \(date.formatted(date: .numeric, time: .shortened))"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(entry.isDemo ? "차곡 · 체험" : "차곡 · 마지막 주차", systemImage: "car.fill")
                .font(.caption.bold()).foregroundStyle(Color(red: 0.26, green: 0.42, blue: 0.32))
            if let floor = entry.snapshot["floor"], !floor.isEmpty {
                Text("\(floor) · \(entry.snapshot["zone"] ?? "") \(entry.snapshot["spot"] ?? "")")
                    .font(.system(size: 29, weight: .bold, design: .rounded)).minimumScaleFactor(0.6)
                    .privacySensitive()
            } else { Text("앱에서 주차 위치를\n확인해 주세요").font(.headline) }
            Text(recordTime).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            Text(entry.draft["status"] as? String ?? "앱을 열어 최신 위치 확인 · 기록").font(.caption2).foregroundStyle(.secondary)
            if family == .systemMedium {
                HStack {
                    Button(intent: ParkingActionIntent("floor")) { Text(entry.draft["floor"] as? String ?? "층") }.accessibilityLabel("다음 층 선택")
                    Button(intent: ParkingActionIntent("zone")) { Text(entry.draft["zone"] as? String ?? "구역") }.accessibilityLabel("다음 구역 선택")
                    Button(intent: ParkingActionIntent("save")) { Text(entry.draft["busy"] as? Bool == true ? "저장 중" : "저장") }
                }.buttonStyle(.bordered).tint(Color(red: 0.26, green: 0.42, blue: 0.32))
                    .disabled(entry.draft["enabled"] as? Bool != true || entry.draft["busy"] as? Bool == true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(Color(red: 0.95, green: 0.96, blue: 0.93), for: .widget)
        .widgetURL(URL(string: "carcar://home"))
    }
}

struct ParkingHomeWidget: Widget {
    let kind = "ParkingHomeWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ParkingProvider()) { ParkingWidgetView(entry: $0) }
            .configurationDisplayName("차곡 · 마지막 주차")
            .description("마지막으로 확인한 주차 위치를 보고 앱에서 새 기록을 남겨요.")
            .supportedFamilies([.systemSmall, .systemMedium])
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
