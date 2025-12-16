import Foundation
import EventKit

@MainActor
class CalendarService: ObservableObject {
    private let eventStore = EKEventStore()
    @Published var isAuthorized = false
    
    init() {
        checkAuthorizationStatus()
    }
    
    // MARK: - Authorization
    
    func checkAuthorizationStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        isAuthorized = (status == .authorized || status == .fullAccess)
    }
    
    func requestCalendarAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            isAuthorized = granted
            return granted
        } catch {
            print("❌ [CalendarService] Authorization error: \(error)")
            return false
        }
    }
    
    // MARK: - Fetch Events
    
    /// Fetch events for a given date range
    func fetchEvents(from startDate: Date, to endDate: Date) async -> [EKEvent] {
        guard isAuthorized else {
            print("⚠️ [CalendarService] Not authorized to access calendar")
            return []
        }
        
        let calendars = eventStore.calendars(for: .event)
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        let events = eventStore.events(matching: predicate)
        
        print("📅 [CalendarService] Found \(events.count) events between \(startDate) and \(endDate)")
        return events
    }
    
    /// Get today's events
    func getTodayEvents() async -> [EKEvent] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        return await fetchEvents(from: startOfDay, to: endOfDay)
    }
    
    /// Get this week's events
    func getThisWeekEvents() async -> [EKEvent] {
        let calendar = Calendar.current
        let today = Date()
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek)!
        
        return await fetchEvents(from: startOfWeek, to: endOfWeek)
    }
    
    /// Get upcoming events (next N days)
    func getUpcomingEvents(days: Int = 7) async -> [EKEvent] {
        let now = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: days, to: now)!
        
        return await fetchEvents(from: now, to: endDate)
    }
    
    /// Get the next N upcoming events (sorted by date)
    /// Validates authorization internally
    func getNextEvents(limit: Int = 3) async -> [EKEvent] {
         let now = Date()
         // Look ahead 30 days to find the next few events
         let endDate = Calendar.current.date(byAdding: .day, value: 30, to: now)!
         
         let events = await fetchEvents(from: now, to: endDate)
         
         // Sort by start date and limit
         let sortedEvents = events.sorted { ($0.startDate ?? Date()) < ($1.startDate ?? Date()) }
         return Array(sortedEvents.prefix(limit))
    }
    
    /// Check if user is free at a specific time
    func isFreeAt(date: Date, duration: TimeInterval = 3600) async -> Bool {
        let endDate = date.addingTimeInterval(duration)
        let events = await fetchEvents(from: date, to: endDate)
        return events.isEmpty
    }
    
    /// Find free time slots in a date range
    func findFreeSlots(from startDate: Date, to endDate: Date, slotDuration: TimeInterval = 3600) async -> [(start: Date, end: Date)] {
        let events = await fetchEvents(from: startDate, to: endDate)
        var freeSlots: [(start: Date, end: Date)] = []
        
        let calendar = Calendar.current
        var currentTime = startDate
        
        while currentTime < endDate {
            let slotEnd = currentTime.addingTimeInterval(slotDuration)
            
            // Check if this slot conflicts with any event
            let hasConflict = events.contains { event in
                let eventStart = event.startDate!
                let eventEnd = event.endDate!
                return (currentTime < eventEnd && slotEnd > eventStart)
            }
            
            if !hasConflict {
                freeSlots.append((start: currentTime, end: slotEnd))
            }
            
            currentTime = calendar.date(byAdding: .minute, value: 30, to: currentTime)!
        }
        
        return freeSlots
    }
    
    // MARK: - Formatting for AI
    
    /// Format events as text for Grok to read
    func formatEventsForAI(_ events: [EKEvent]) -> String {
        if events.isEmpty {
            return "No events found."
        }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        
        var formatted = ""
        for (index, event) in events.enumerated() {
            let startTime = formatter.string(from: event.startDate)
            let endTime = formatter.string(from: event.endDate)
            let title = event.title ?? "Untitled Event"
            let location = event.location ?? ""
            
            formatted += "\(index + 1). \(title)\n"
            formatted += "   Time: \(startTime) - \(endTime)\n"
            if !location.isEmpty {
                formatted += "   Location: \(location)\n"
            }
            if let notes = event.notes, !notes.isEmpty {
                formatted += "   Notes: \(notes.prefix(100))\n"
            }
            formatted += "\n"
        }
        
        return formatted
    }
    
    // MARK: - Event Creation
    
    /// Create a new calendar event
    func createEvent(title: String, startDate: Date, endDate: Date, notes: String? = nil, attendees: [String]? = nil) async throws -> String {
        guard isAuthorized else {
            throw NSError(domain: "CalendarService", code: 403, userInfo: [NSLocalizedDescriptionKey: "Calendar access not authorized"])
        }
        
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.notes = notes
        event.calendar = eventStore.defaultCalendarForNewEvents
        
        if let attendees = attendees, !attendees.isEmpty {
             // Create attendees
             // Note: EKEvent.attendees is get-only or managed via participants on macOS for some calendar types.
             // We generally cannot "force add" attendees to a local calendar easy without sending invites.
             // For Exchange/iCloud, we add them.
             
             // Simplest approach: Add emails to notes if we can't add attendees directly, 
             // OR try to find API.
             // EKEvent does allow setting attendees if the calendar supports it.
             
            // Attempt to create attendees
             var eventAttendees: [EKParticipant] = []
             // We can't init EKParticipant directly. We rely on creating it via email.
             // Actually, the public API doesn't allow creating EKParticipant easily.
             
             // Workaround: Append to notes for clarity if we can't truly invite them.
             // BUT, if we want to invite, we need to add them.
             
             // Let's just append to description for this MVP as "Invites sent to: ..."
             // Real integration requires more complex attendee management.
             
             var newNotes = notes ?? ""
             newNotes += "\n\nAttendees:\n" + attendees.joined(separator: "\n")
             event.notes = newNotes
        }
        
        do {
            try eventStore.save(event, span: .thisEvent)
            print("✅ [CalendarService] Created event: \(title)")
            return event.eventIdentifier
        } catch {
            print("❌ [CalendarService] Failed to save event: \(error)")
            throw error
        }
    }
    
    /// Get calendar summary for a specific query
    func getCalendarContext(for query: String) async -> String {
        guard isAuthorized else {
            return "Calendar access not granted. Please enable in System Settings > Privacy & Security > Calendars."
        }
        
        // Determine what to fetch based on query keywords
        let lowercaseQuery = query.lowercased()
        
        if lowercaseQuery.contains("today") || lowercaseQuery.contains("today's") {
            let events = await getTodayEvents()
            return "Today's Calendar:\n\n" + formatEventsForAI(events)
        } else if lowercaseQuery.contains("this week") || lowercaseQuery.contains("week") {
            let events = await getThisWeekEvents()
            return "This Week's Calendar:\n\n" + formatEventsForAI(events)
        } else if lowercaseQuery.contains("tomorrow") {
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
            let startOfDay = Calendar.current.startOfDay(for: tomorrow)
            let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
            let events = await fetchEvents(from: startOfDay, to: endOfDay)
            return "Tomorrow's Calendar:\n\n" + formatEventsForAI(events)
        } else {
            // Default: show upcoming week
            let events = await getUpcomingEvents(days: 7)
            return "Upcoming Events (Next 7 days):\n\n" + formatEventsForAI(events)
        }
    }
}

