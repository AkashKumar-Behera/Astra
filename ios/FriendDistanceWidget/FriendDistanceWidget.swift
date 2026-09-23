import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    typealias Entry = FriendDistanceEntry

    func placeholder(in context: Context) -> FriendDistanceEntry {
        FriendDistanceEntry(
            date: Date(),
            friendName: "Friend",
            distance: "2.4 km away",
            status: "Astra Live",
            avatarPath: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (FriendDistanceEntry) -> ()) {
        let entry = getCurrentEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let entry = getCurrentEntry()
        // Refresh periodically (e.g. every 15 minutes or when pinged by app)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func getCurrentEntry() -> FriendDistanceEntry {
        let defaults = UserDefaults(suiteName: "group.com.astra.always")
        let name = defaults?.string(forKey: "friend_name") ?? "Friend"
        let distance = defaults?.string(forKey: "friend_distance") ?? "-- km"
        let status = defaults?.string(forKey: "friend_status") ?? "Astra Live"
        let photoPath = defaults?.string(forKey: "friend_photo_path")

        return FriendDistanceEntry(
            date: Date(),
            friendName: name,
            distance: distance,
            status: status,
            avatarPath: photoPath
        )
    }
}

struct FriendDistanceEntry: TimelineEntry {
    let date: Date
    let friendName: String
    let distance: String
    let status: String
    let avatarPath: String?
}

struct FriendDistanceWidgetEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        HStack(spacing: 12) {
            // Avatar View
            ZStack {
                Circle()
                    .fill(Color(red: 0.13, green: 0.12, blue: 0.23))
                    .overlay(Circle().stroke(Color(red: 0.49, green: 0.30, blue: 1.0), lineWidth: 2))

                if let path = entry.avatarPath,
                   let uiImage = UIImage(contentsOfFile: path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(Circle())
                } else {
                    Text(String(entry.friendName.prefix(1)).uppercased())
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 52, height: 52)

            // Info details
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.friendName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 0.88, green: 0.88, blue: 1.0))
                    .lineLimit(1)

                Text(entry.distance)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(Color(red: 0.70, green: 0.53, blue: 1.0))
                    .lineLimit(1)

                Text(entry.status)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(red: 0.56, green: 0.55, blue: 0.73))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(14)
        .widgetBackground(Color(red: 0.07, green: 0.07, blue: 0.15))
    }
}

extension View {
    func widgetBackground(_ backgroundView: some View) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            return containerBackground(for: .widget) {
                backgroundView
            }
        } else {
            return background(backgroundView)
        }
    }
}

@main
struct AstraWidgetBundle: WidgetBundle {
    var body: some Widget {
        FriendDistanceWidget()
    }
}

struct FriendDistanceWidget: Widget {
    let kind: String = "FriendDistanceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            FriendDistanceWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Astra")
        .description("Track your connected friend's real-time distance and status.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
