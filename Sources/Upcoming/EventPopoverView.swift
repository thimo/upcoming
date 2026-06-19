import CoreLocation
import MapKit
import SwiftUI
import UpcomingCore
import WeatherKit

/// Read-only port of Apple Calendar's event-detail popover: a stack of
/// rounded cards on a material backdrop. Display-only — every editing
/// affordance from Calendar (steppers, "Add …" placeholders, Propose/
/// Unsubscribe, status editing) is dropped, and empty fields simply don't
/// render. Shown as a pointer-transparent hover panel beside the popup.
struct EventPopoverView: View {
    let event: EventItem
    let calendar: Calendar
    @Environment(\.colorScheme) private var colorScheme

    /// Apple's popover is ~360pt; 340 fits comfortably beside our 320 popup.
    static let contentWidth: CGFloat = 340

    private var palette: PillPalette { PillPalette(colorScheme: colorScheme) }

    var body: some View {
        VStack(spacing: 8) {
            headerCard
            if let url = event.videoCallURL { videoCard(url) }
            dateCard
            if !event.attendees.isEmpty { attendeesCard }
            if hasNotes { notesCard }
            if hasMap { mapCard }
        }
    }

    // MARK: - Cards

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(event.title)
                    .font(.system(size: 17, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Circle()
                    .fill(Color(calendarColor: event.color))
                    .frame(width: 12, height: 12)
                    .padding(.top, 4)
            }
            if let location = event.location, !location.isEmpty {
                Divider()
                Text(location)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardStyle()
    }

    private func videoCard(_ url: URL) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "video.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(url.host ?? url.absoluteString)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Button {
                VideoCallOpener.open(url)
                AppDelegate.shared?.closePopup()
            } label: {
                Text("Join")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.10), in: Capsule())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
        .cardStyle()
    }

    private var dateCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(dateTimeString)
                .font(.system(size: 13))
            if let recurrence = event.recurrenceText {
                HStack(alignment: .top, spacing: 6) {
                    Text(recurrence)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: EventStyle.recurrenceSymbol)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            if let alert = event.alertText {
                Text(alert)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    private var attendeesCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(event.attendees) { attendee in
                HStack(spacing: 10) {
                    statusGlyph(attendee.status)
                    Text(nameLine(attendee))
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
            }
        }
        .cardStyle()
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let notes = event.notes, !notes.isEmpty {
                Text(notes)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(12)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let url = event.url, url != event.videoCallURL {
                Text(url.absoluteString)
                    .font(.system(size: 13))
                    .foregroundStyle(.tint)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        NSWorkspace.shared.open(url)
                        AppDelegate.shared?.closePopup()
                    }
                    .pointingHandCursor()
            }
        }
        .cardStyle()
    }

    @ViewBuilder private var mapCard: some View {
        if let coordinate = eventCoordinate {
            EventMapCard(coordinate: coordinate, locationName: event.location)
        }
    }

    // MARK: - Attendee rendering

    private func statusGlyph(_ status: EventAttendee.Status) -> some View {
        let (symbol, color): (String, Color)
        switch status {
        case .accepted: (symbol, color) = ("checkmark.circle.fill", .green)
        case .declined: (symbol, color) = ("xmark.circle.fill", .red)
        case .tentative: (symbol, color) = ("questionmark.circle.fill", .orange)
        case .noResponse: (symbol, color) = ("questionmark.circle", .secondary)
        }
        return Image(systemName: symbol)
            .font(.system(size: 15))
            .foregroundStyle(color)
    }

    private func nameLine(_ attendee: EventAttendee) -> String {
        var line = attendee.name
        if attendee.isOrganizer { line += " (organiser)" }
        if attendee.isOptional { line += " (optional)" }
        return line
    }

    // MARK: - Derived content

    private var hasNotes: Bool {
        if let notes = event.notes, !notes.isEmpty { return true }
        if let url = event.url, url != event.videoCallURL { return true }
        return false
    }

    private var hasMap: Bool { eventCoordinate != nil }

    private var eventCoordinate: CLLocationCoordinate2D? {
        guard let lat = event.latitude, let lon = event.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// "17 Jun 2026  08:00 – 18:00", with sensible variants for all-day and
    /// multi-day events.
    private var dateTimeString: String {
        let date = DateFormatter()
        date.calendar = calendar
        date.setLocalizedDateFormatFromTemplate("d MMM y")
        let time = DateFormatter()
        time.calendar = calendar
        time.timeStyle = .short
        time.dateStyle = .none

        let startDay = calendar.startOfDay(for: event.start)
        // All-day events end at the next midnight; step back to the last
        // day they actually cover.
        let lastInstant = max(event.start, event.end.addingTimeInterval(-1))
        let endDay = calendar.startOfDay(for: lastInstant)
        let sameDay = calendar.isDate(startDay, inSameDayAs: endDay)

        if event.isAllDay {
            return sameDay
                ? date.string(from: event.start)
                : "\(date.string(from: event.start)) – \(date.string(from: endDay))"
        }
        if sameDay {
            return "\(date.string(from: event.start))  \(time.string(from: event.start)) – \(time.string(from: event.end))"
        }
        return "\(date.string(from: event.start)) \(time.string(from: event.start)) – \(date.string(from: event.end)) \(time.string(from: event.end))"
    }
}

private extension View {
    /// A single rounded "card" inside the popover (subtle fill, left-aligned).
    func cardStyle() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                Color.primary.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
    }
}

/// Map + weather card (bottom of Apple's location popovers): a static
/// MapKit snapshot with a pin, plus a "City, Region — 14°" line. The
/// coordinate comes from the event's structured location (we don't geocode
/// free-text, matching Apple — meeting-room names get no map). Weather is
/// best-effort: it needs the WeatherKit entitlement and degrades to just
/// the place name (or nothing) when unavailable. The line's height is
/// reserved up front so the async fill never resizes the preview panel.
private struct EventMapCard: View {
    let coordinate: CLLocationCoordinate2D
    let locationName: String?

    @State private var snapshot: NSImage?
    @State private var weatherLine: String?

    private static let mapHeight: CGFloat = 120

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let snapshot {
                    Image(nsImage: snapshot)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(Color.secondary.opacity(0.12))
                }
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white, .red)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            }
            .frame(height: Self.mapHeight)
            .frame(maxWidth: .infinity)
            .clipped()

            // Reserved even before it loads, so the panel keeps its size.
            Text(weatherLine ?? " ")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 17)
                .padding(.vertical, 8)
        }
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { openInMaps() }
        .pointingHandCursor()
        .task(id: "\(coordinate.latitude),\(coordinate.longitude)") {
            await renderSnapshot(at: coordinate)
            await loadWeather(at: coordinate)
        }
    }

    /// Open Apple Maps at the event's location, pinned with its name.
    private func openInMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = locationName
        item.openInMaps()
        AppDelegate.shared?.closePopup()
    }

    @MainActor
    private func renderSnapshot(at coordinate: CLLocationCoordinate2D) async {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        options.size = CGSize(width: EventPopoverView.contentWidth - 24, height: Self.mapHeight)
        options.showsBuildings = true
        if let appearance = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
            options.appearance = NSAppearance(named: appearance)
        }
        let snapshotter = MKMapSnapshotter(options: options)
        if let result = try? await snapshotter.start() {
            snapshot = result.image
        }
    }

    private func loadWeather(at coordinate: CLLocationCoordinate2D) async {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        // Place name (City, Region) for the leading half of the line.
        var place: String?
        if let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first {
            let parts = [mark.locality, mark.administrativeArea].compactMap { $0 }
            place = parts.isEmpty ? nil : parts.joined(separator: ", ")
        }

        // Temperature is best-effort: WeatherKit needs its entitlement.
        var temperature: String?
        do {
            let weather = try await WeatherService.shared.weather(for: location)
            let measurement = weather.currentWeather.temperature
            let formatter = MeasurementFormatter()
            formatter.numberFormatter.maximumFractionDigits = 0
            formatter.unitOptions = .temperatureWithoutUnit
            temperature = formatter.string(from: measurement) + "°"
        } catch {
            // Best-effort: WeatherKit can fail (no entitlement propagation
            // yet, offline, throttled). Fall back to the place name only.
        }

        switch (place, temperature) {
        case let (p?, t?): weatherLine = "\(p) — \(t)"
        case let (p?, nil): weatherLine = p
        case let (nil, t?): weatherLine = t
        case (nil, nil): weatherLine = nil
        }
    }
}
