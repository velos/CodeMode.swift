import Foundation

extension DefaultCapabilityRegistrationBuilder {
    func calendarAndReminderRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(tool: CalendarListEventsTool(eventKit: eventKit)),
            CapabilityRegistration(tool: CalendarWriteEventTool(eventKit: eventKit)),
            CapabilityRegistration(tool: CalendarDeleteEventTool(eventKit: eventKit)),
            CapabilityRegistration(tool: CalendarPickCalendarTool(systemUI: systemUI)),
            CapabilityRegistration(tool: CalendarPresentEventTool(systemUI: systemUI)),
            CapabilityRegistration(tool: CalendarPresentNewEventTool(systemUI: systemUI)),
            CapabilityRegistration(tool: RemindersListTool(eventKit: eventKit)),
            CapabilityRegistration(tool: RemindersWriteTool(eventKit: eventKit)),
            CapabilityRegistration(tool: RemindersDeleteTool(eventKit: eventKit)),
        ]
    }
}
