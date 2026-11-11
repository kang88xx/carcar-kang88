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
        ParkingEntry(date: Date(), snapshot: ["floor": "B2", "zone": "C", "spot": "24", "updatedAt": ISO8601DateFormatter().string(from: Date())], isDemo: true)
    }
    func getSnapshot(in context: Context, completion: @escaping (ParkingEntry) -> Void) { completion(read()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ParkingEntry>) -> Void) {
        let entry = read()
        if let until = entry.draft["busyUntil"] as? Double, until > Date().timeIntervalSince1970 {
            // Finish local recovery for an action started by the previous widget.
            completion(Timeline(entries: [entry], policy: .after(Date(timeIntervalSince1970: until + 1))))
        } else { completion(Timeline(entries: [entry], policy: .never)) }
    }
    private func read() -> ParkingEntry {
        let raw = UserDefaults(suiteName: "group.com.kang88.carcar")?.dictionary(forKey: "parkingSnapshot") ?? [:]
        let draft = (try? WidgetSession.locked { try WidgetSession.display() }) ?? [:]
        return ParkingEntry(date: Date(), snapshot: raw.compactMapValues { $0 as? String }, isDemo: raw["isDemo"] as? Bool ?? false, draft: draft)
    }
}

private enum WidgetPalette {
    static let ink = Color(red: 30 / 255, green: 41 / 255, blue: 59 / 255)
    static let highlight = Color(red: 219 / 255, green: 234 / 255, blue: 254 / 255)
    static let mist = Color(red: 203 / 255, green: 213 / 255, blue: 225 / 255)
}

private struct ParkingWidgetView: View {
    let entry: ParkingEntry
    private var floor: String { value("floor") }
    private var zone: String { value("zone") }
    private var spot: String { value("spot") }
    private var zoneLabel: String { zone.hasSuffix("구역") ? zone : "\(zone)구역" }
    private var spotLabel: String { spot.hasSuffix("번") ? spot : "\(spot)번" }

    private func value(_ key: String) -> String {
        (entry.snapshot[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var recordTime: String {
        guard !floor.isEmpty else { return entry.isDemo ? "체험 · 기록 없음" : "주차 기록 없음" }
        let prefix = entry.isDemo ? "체험 · " : ""
        guard let raw = entry.snapshot["updatedAt"], !raw.isEmpty else { return prefix + "기록 시각 확인 필요" }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = parser.date(from: raw)
        if date == nil {
            parser.formatOptions = [.withInternetDateTime]
            date = parser.date(from: raw)
        }
        guard let date = date else { return prefix + "기록 시각 확인 필요" }
        // updatedAt carries the saved record's created_at, never the render time.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let display = DateFormatter()
        display.locale = Locale(identifier: "ko_KR")
        display.calendar = calendar
        display.timeZone = .autoupdatingCurrent
        display.dateFormat = calendar.component(.year, from: date) == calendar.component(.year, from: entry.date)
            ? "M월 d일 HH:mm '기록'" : "yyyy년 M월 d일 HH:mm '기록'"
        return prefix + display.string(from: date)
    }

    private var locationLabel: String {
        [floor, zone.isEmpty ? nil : zoneLabel, spot.isEmpty ? nil : spotLabel]
            .compactMap { $0 }.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "clock").accessibilityHidden(true)
                Text(recordTime).lineLimit(1).minimumScaleFactor(0.75)
            }
            .font(.system(size: 12))
            .foregroundStyle(WidgetPalette.mist)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(recordTime)
            .privacySensitive()

            if floor.isEmpty {
                Text("위치를 기록해 주세요")
                    .font(.system(size: 19, weight: .bold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .minimumScaleFactor(0.8)
            } else {
                HStack(alignment: .center, spacing: 10) {
                    Text(floor)
                        .font(.system(size: 60, weight: .bold, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.35)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !zone.isEmpty || !spot.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            if !zone.isEmpty {
                                Text(zoneLabel)
                                    .font(.system(size: 19, weight: .bold))
                                    .lineLimit(1).minimumScaleFactor(0.55)
                            }
                            if !spot.isEmpty {
                                Text(spotLabel)
                                    .font(.system(size: 17))
                                    .lineLimit(2).minimumScaleFactor(0.65)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxHeight: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(locationLabel)
                .privacySensitive()
            }

            Link(destination: URL(string: "carcar://parking")!) {
                Label("주차 기록", systemImage: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1).minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(WidgetPalette.ink)
                    .background(WidgetPalette.highlight, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("주차 기록")
            .accessibilityHint("앱에서 주차 위치 입력 화면을 엽니다")
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(WidgetPalette.ink, for: .widget)
        .widgetURL(URL(string: "carcar://home"))
    }
}

struct ParkingHomeWidget: Widget {
    let kind = "ParkingHomeWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ParkingProvider()) { ParkingWidgetView(entry: $0) }
            .configurationDisplayName("마지막 주차 위치")
            .description("정사각형 위젯에서 위치를 확인하고, 주차 기록을 눌러 앱에서 입력해요.")
            .supportedFamilies([.systemSmall])
            .contentMarginsDisabled()
    }
}

struct ParkingLiveWidget: Widget {
    private let ink = WidgetPalette.ink

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
                .activityBackgroundTint(Color(red: 245 / 255, green: 247 / 255, blue: 250 / 255))
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
