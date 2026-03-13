import Foundation

enum JavaScriptBindingCatalog {
    static func names(for capability: CapabilityID) -> [String] {
        bindings[capability] ?? []
    }

    static func allNames(for capabilities: some Sequence<CapabilityID>) -> Set<String> {
        Set(capabilities.flatMap { names(for: $0) })
    }

    static func pruningScript(removing capabilities: some Sequence<CapabilityID>) -> String {
        let bindingsToRemove = capabilities
            .flatMap { names(for: $0) }
            .sorted()

        guard bindingsToRemove.isEmpty == false else {
            return ""
        }

        var lines = bindingsToRemove.map { name in
            "delete globalThis.\(name);"
        }

        let groupPaths = Set(
            bindingsToRemove.compactMap { name -> String? in
                let components = name.split(separator: ".")
                guard components.count >= 2 else {
                    return nil
                }
                return components.dropLast().joined(separator: ".")
            }
        )

        for path in groupPaths.sorted(by: { lhs, rhs in
            lhs.components(separatedBy: ".").count > rhs.components(separatedBy: ".").count
        }) {
            lines.append("if (globalThis.\(path) && Object.keys(globalThis.\(path)).length === 0) { delete globalThis.\(path); }")
        }

        for root in ["apple", "ios", "fs"] {
            lines.append("if (globalThis.\(root) && Object.keys(globalThis.\(root)).length === 0) { delete globalThis.\(root); }")
        }

        return lines.joined(separator: "\n")
    }

    private static let bindings: [CapabilityID: [String]] = [
        .networkFetch: ["fetch"],
        .keychainRead: ["apple.keychain.get"],
        .keychainWrite: ["apple.keychain.set"],
        .keychainDelete: ["apple.keychain.delete"],
        .locationRead: ["apple.location.getPermissionStatus", "apple.location.getCurrentPosition"],
        .locationPermissionRequest: ["apple.location.requestPermission"],
        .weatherRead: ["apple.weather.getCurrentWeather"],
        .calendarRead: ["apple.calendar.listEvents"],
        .calendarWrite: ["apple.calendar.createEvent"],
        .remindersRead: ["apple.reminders.listReminders"],
        .remindersWrite: ["apple.reminders.createReminder"],
        .contactsRead: ["apple.contacts.list"],
        .contactsSearch: ["apple.contacts.search"],
        .photosRead: ["apple.photos.list"],
        .photosExport: ["apple.photos.export"],
        .visionImageAnalyze: ["apple.vision.analyzeImage"],
        .notificationsPermissionRequest: ["apple.notifications.requestPermission"],
        .notificationsSchedule: ["apple.notifications.schedule"],
        .notificationsPendingRead: ["apple.notifications.listPending"],
        .notificationsPendingDelete: ["apple.notifications.cancelPending"],
        .alarmPermissionRequest: ["ios.alarm.requestPermission"],
        .alarmRead: ["ios.alarm.list"],
        .alarmSchedule: ["ios.alarm.schedule"],
        .alarmCancel: ["ios.alarm.cancel"],
        .healthPermissionRequest: ["apple.health.requestPermission"],
        .healthRead: ["apple.health.read"],
        .healthWrite: ["apple.health.write"],
        .homeRead: ["apple.home.list"],
        .homeWrite: ["apple.home.writeCharacteristic"],
        .mediaMetadataRead: ["apple.media.metadata"],
        .mediaFrameExtract: ["apple.media.extractFrame"],
        .mediaTranscode: ["apple.media.transcode"],
        .fsList: ["apple.fs.list", "fs.promises.readdir"],
        .fsRead: ["apple.fs.read", "fs.promises.readFile"],
        .fsWrite: ["apple.fs.write", "fs.promises.writeFile"],
        .fsMove: ["apple.fs.move", "fs.promises.rename"],
        .fsCopy: ["apple.fs.copy", "fs.promises.copyFile"],
        .fsDelete: ["apple.fs.delete", "fs.promises.rm"],
        .fsStat: ["apple.fs.stat", "fs.promises.stat"],
        .fsMkdir: ["apple.fs.mkdir", "fs.promises.mkdir"],
        .fsExists: ["apple.fs.exists"],
        .fsAccess: ["apple.fs.access", "fs.promises.access"],
    ]
}
