import Foundation

extension DefaultCapabilityRegistrationBuilder {
    func appIntentsRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(tool: AppIntentsListTool(appIntents: appIntents)),
            CapabilityRegistration(tool: AppIntentsRunTool(appIntents: appIntents)),
            CapabilityRegistration(tool: AppIntentsDonateTool(appIntents: appIntents)),
            CapabilityRegistration(tool: AppIntentsOpenTool(appIntents: appIntents)),
            CapabilityRegistration(tool: AppIntentsHandoffsReadTool(appIntents: appIntents)),
        ]
    }


    func foundationModelsRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(tool: FoundationModelsStatusTool(foundationModels: foundationModels)),
            CapabilityRegistration(tool: FoundationModelsGenerateTool(foundationModels: foundationModels)),
            CapabilityRegistration(tool: FoundationModelsExtractTool(foundationModels: foundationModels)),
        ]
    }


    func activityRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(tool: ActivityListTool(activity: activity)),
            CapabilityRegistration(tool: ActivityStartTool(activity: activity)),
            CapabilityRegistration(tool: ActivityUpdateTool(activity: activity)),
            CapabilityRegistration(tool: ActivityEndTool(activity: activity)),
            CapabilityRegistration(tool: ActivityPushTokenReadTool(activity: activity)),
        ]
    }


    func mapsRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(tool: MapsGeocodeTool(maps: maps)),
            CapabilityRegistration(tool: MapsReverseGeocodeTool(maps: maps)),
            CapabilityRegistration(tool: MapsSearchTool(maps: maps)),
            CapabilityRegistration(tool: MapsRouteEstimateTool(maps: maps)),
            CapabilityRegistration(tool: MapsOpenTool(maps: maps)),
        ]
    }
}
