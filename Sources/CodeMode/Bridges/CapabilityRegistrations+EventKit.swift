import Foundation

extension DefaultCapabilityRegistrationBuilder {
    func calendarAndReminderRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(tool: CalendarListEventsTool()),
            CapabilityRegistration(tool: CalendarCreateEventTool()),
            CapabilityRegistration(tool: CalendarUpdateEventTool()),
            CapabilityRegistration(tool: CalendarDeleteEventTool()),
            CapabilityRegistration(tool: CalendarPickCalendarTool(systemUI: systemUI)),
            CapabilityRegistration(tool: CalendarPresentEventTool(systemUI: systemUI)),
            CapabilityRegistration(tool: CalendarPresentNewEventTool(systemUI: systemUI)),
            CapabilityRegistration(tool: RemindersListTool()),
            CapabilityRegistration(tool: RemindersCreateTool()),
            CapabilityRegistration(tool: RemindersUpdateTool()),
            CapabilityRegistration(tool: RemindersCompleteTool()),
            CapabilityRegistration(tool: RemindersDeleteTool()),
        ]
    }
}
