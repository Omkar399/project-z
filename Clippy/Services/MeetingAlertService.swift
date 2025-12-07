//
//  MeetingAlertService.swift
//  ProjectZ
//
//  Proactive meeting briefing alerts - auto-shows Spotlight 5 mins before meetings
//

import Foundation
import EventKit
import Combine

@MainActor
class MeetingAlertService: ObservableObject {
    // Dependencies
    private weak var calendarService: CalendarService?
    private weak var mem0Service: Mem0Service?
    private weak var grokService: GrokService?
    private weak var spotlightController: SpotlightWindowController?
    
    // Configuration
    @Published var isEnabled: Bool = true
    private let alertMinutesBefore: Int = 5
    
    // State tracking
    private var alertedMeetingIds: Set<String> = []
    private var monitoringTimer: Timer?
    
    init() {
        print("📅 [MeetingAlertService] Initialized")
    }
    
    // MARK: - Dependency Injection
    
    func setDependencies(
        calendarService: CalendarService,
        mem0Service: Mem0Service,
        grokService: GrokService,
        spotlightController: SpotlightWindowController
    ) {
        self.calendarService = calendarService
        self.mem0Service = mem0Service
        self.grokService = grokService
        self.spotlightController = spotlightController
        
        print("📅 [MeetingAlertService] Dependencies injected")
    }
    
    // MARK: - Monitoring
    
    func startMonitoring() {
        guard isEnabled else {
            print("📅 [MeetingAlertService] Monitoring disabled")
            return
        }
        
        stopMonitoring() // Stop existing timer if any
        
        print("📅 [MeetingAlertService] Starting calendar monitoring (check every 60s)")
        
        // Check immediately on start
        checkUpcomingMeetings()
        
        // Then check every minute
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkUpcomingMeetings()
            }
        }
    }
    
    func stopMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        print("📅 [MeetingAlertService] Monitoring stopped")
    }
    
    // MARK: - Meeting Detection
    
    private func checkUpcomingMeetings() {
        guard let calendarService = calendarService else { return }
        
        Task {
            // Get events happening in the next 10 minutes
            let upcomingEvents = await calendarService.getNextEvents(limit: 10)
            
            let now = Date()
            let targetWindow = TimeInterval(alertMinutesBefore * 60) // 5 minutes in seconds
            let windowTolerance: TimeInterval = 60 // 1 minute tolerance for timer jitter
            
            for event in upcomingEvents {
                let timeUntilMeeting = event.startDate.timeIntervalSince(now)
                
                // Check if meeting is approximately 5 minutes away (4-6 min window)
                if timeUntilMeeting > (targetWindow - windowTolerance) &&
                   timeUntilMeeting <= (targetWindow + windowTolerance) {
                    
                    // Check if we haven't already alerted for this meeting
                    let meetingId = event.eventIdentifier ?? UUID().uuidString // Fallback ID if nil
                    guard !alertedMeetingIds.contains(meetingId) else {
                        continue // Already alerted
                    }
                    
                    print("📅 [MeetingAlertService] Meeting in ~\(Int(timeUntilMeeting / 60)) mins: \(event.title ?? "Untitled")")
                    
                    // Mark as alerted
                    alertedMeetingIds.insert(meetingId)
                    
                    // Generate and show briefing
                    await generateAndShowBriefing(for: event)
                }
            }
            
            // Clean up old alerted IDs (meetings that are now in the past)
            cleanupAlertedMeetings(upcomingEvents: upcomingEvents)
        }
    }
    
    private func cleanupAlertedMeetings(upcomingEvents: [EKEvent]) {
        // Keep only IDs that are still in upcoming events
        let upcomingIds = Set(upcomingEvents.compactMap { $0.eventIdentifier })
        alertedMeetingIds = alertedMeetingIds.intersection(upcomingIds)
    }
    
    // MARK: - Briefing Generation
    
    private func generateAndShowBriefing(for event: EKEvent) async {
        guard let mem0 = mem0Service,
              let grok = grokService,
              let spotlight = spotlightController else {
            print("⚠️ [MeetingAlertService] Services not available")
            return
        }
        
        let title = event.title ?? "Untitled Meeting"
        
        // Build briefing context (similar to /meetnotes but for single event)
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let time = formatter.string(from: event.startDate)
        
        var briefingContext = "Upcoming meeting in 5 minutes:\n\n"
        briefingContext += "Title: \(title)\nTime: \(time)\n"
        
        // Get attendees if available
        var searchTerms = title
        if let attendees = event.attendees {
            let attendeeNames = attendees.compactMap { $0.name }.joined(separator: ", ")
            if !attendeeNames.isEmpty {
                briefingContext += "Attendees: \(attendeeNames)\n"
                searchTerms += " " + attendeeNames
            }
        }
        
        // Search Mem0 for relevant memories
        let memories = await mem0.searchMemories(query: searchTerms, limit: 5)
        if !memories.isEmpty {
            briefingContext += "🧠 Related Memories:\n" + memories.map { "• \($0.memory)" }.joined(separator: "\n") + "\n"
        }
        
        briefingContext += """
        
        Task: Generate a concise briefing for this meeting.
        Output ONLY a JSON object (no markdown):
        {
            "title": "Meeting Title",
            "time": "Time string",
            "summary": "One sentence about the meeting",
            "points": ["Key point 1", "Key point 2"]
        }
        """
        
        // Ask Grok for briefing
        print("📅 [MeetingAlertService] Generating briefing with Grok...")
        let response = await grok.chat(message: briefingContext, context: nil)
        
        // Format for display
        let displayMessage = """
        📅 Meeting in 5 minutes!
        
        \(response)
        """
        
        // Show proactive briefing in Spotlight
        await MainActor.run {
            spotlight.showWithNudge(message: displayMessage)
            print("✅ [MeetingAlertService] Briefing shown for: \(title)")
        }
    }
    
    // Note: deinit cannot be @MainActor, so we can't call stopMonitoring here
    // The timer will be invalidated when the object is deallocated
}
