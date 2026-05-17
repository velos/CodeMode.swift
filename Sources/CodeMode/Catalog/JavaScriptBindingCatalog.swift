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
        .calendarWrite: ["apple.calendar.createEvent", "apple.calendar.updateEvent"],
        .calendarDelete: ["apple.calendar.deleteEvent"],
        .calendarUIPickCalendar: ["apple.calendar.pickCalendar"],
        .calendarUIPresentEvent: ["apple.calendar.presentEvent"],
        .calendarUIPresentNewEvent: ["apple.calendar.presentNewEvent"],
        .remindersRead: ["apple.reminders.listReminders"],
        .remindersWrite: ["apple.reminders.createReminder", "apple.reminders.updateReminder", "apple.reminders.completeReminder"],
        .remindersDelete: ["apple.reminders.deleteReminder"],
        .contactsRead: ["apple.contacts.list"],
        .contactsSearch: ["apple.contacts.search"],
        .contactsUIPick: ["apple.contacts.pick"],
        .contactsUIPresentContact: ["apple.contacts.presentContact"],
        .contactsUIPresentNewContact: ["apple.contacts.presentNewContact"],
        .photosRead: ["apple.photos.list"],
        .photosExport: ["apple.photos.export"],
        .photosUIPick: ["apple.photos.pick"],
        .photosUIPresentLimitedLibraryPicker: ["apple.photos.presentLimitedLibraryPicker"],
        .documentsUIPick: ["apple.documents.pick"],
        .documentsUIExport: ["apple.documents.export", "apple.documents.save"],
        .documentsUIOpenIn: ["apple.documents.openIn"],
        .documentsUIScan: ["apple.documents.scan"],
        .shareUIPresent: ["apple.share.present"],
        .quickLookUIPreview: ["apple.quicklook.preview"],
        .cameraUICapture: ["apple.camera.capture"],
        .cameraUIScanData: ["apple.camera.scanData"],
        .mailUICompose: ["apple.mail.compose"],
        .messagesUICompose: ["apple.messages.compose"],
        .printUIPresent: ["apple.print.present"],
        .webUIPresent: ["apple.web.present"],
        .authUIWebAuthenticate: ["apple.auth.webAuthenticate"],
        .uiAlertPresent: ["apple.ui.presentAlert"],
        .uiPromptPresent: ["apple.ui.presentPrompt"],
        .settingsUIOpen: ["apple.settings.open"],
        .visionImageAnalyze: ["apple.vision.analyzeImage"],
        .notificationsPermissionRequest: ["apple.notifications.requestPermission"],
        .notificationsSchedule: ["apple.notifications.schedule"],
        .notificationsPendingRead: ["apple.notifications.listPending"],
        .notificationsPendingDelete: ["apple.notifications.cancelPending"],
        .notificationsDeliveredRead: ["apple.notifications.listDelivered"],
        .notificationsDeliveredDelete: ["apple.notifications.removeDelivered"],
        .notificationsRemoteRegister: ["apple.notifications.registerRemote"],
        .notificationsRemoteTokenRead: ["apple.notifications.getRemoteToken"],
        .notificationsSettingsRead: ["apple.notifications.getSettings"],
        .notificationsCategoriesSet: ["apple.notifications.setCategories"],
        .notificationsResponsesRead: ["apple.notifications.listResponses"],
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
        .cloudKitAccountStatus: ["apple.cloudkit.getAccountStatus"],
        .cloudKitRecordsQuery: ["apple.cloudkit.queryRecords"],
        .cloudKitRecordSave: ["apple.cloudkit.saveRecord"],
        .cloudKitRecordDelete: ["apple.cloudkit.deleteRecord"],
        .cloudKitSubscriptionSave: ["apple.cloudkit.subscribe"],
        .cloudKitSubscriptionEventsRead: ["apple.cloudkit.listEvents"],
        .speechPermissionRequest: ["apple.speech.requestPermission"],
        .speechStatus: ["apple.speech.getStatus"],
        .speechFileTranscribe: ["apple.speech.transcribeFile"],
        .speechMicrophoneTranscribe: ["apple.speech.transcribeMicrophone"],
        .appIntentsList: ["apple.appIntents.list"],
        .appIntentsRun: ["apple.appIntents.run"],
        .appIntentsDonate: ["apple.appIntents.donate"],
        .appIntentsOpen: ["apple.appIntents.open"],
        .appIntentsHandoffsRead: ["apple.appIntents.listHandoffs"],
        .foundationModelsStatus: ["apple.foundationModels.getStatus"],
        .foundationModelsGenerate: ["apple.foundationModels.generate"],
        .foundationModelsExtract: ["apple.foundationModels.extract"],
        .activityList: ["apple.activity.list"],
        .activityStart: ["apple.activity.start"],
        .activityUpdate: ["apple.activity.update"],
        .activityEnd: ["apple.activity.end"],
        .activityPushTokenRead: ["apple.activity.getPushToken"],
        .mapsGeocode: ["apple.maps.geocode"],
        .mapsReverseGeocode: ["apple.maps.reverseGeocode"],
        .mapsSearch: ["apple.maps.search"],
        .mapsRouteEstimate: ["apple.maps.routeEstimate"],
        .mapsOpen: ["apple.maps.open"],
        .musicPermissionRequest: ["apple.music.requestPermission"],
        .musicSubscriptionStatus: ["apple.music.getSubscriptionStatus"],
        .musicCatalogSearch: ["apple.music.search"],
        .musicCatalogDetails: ["apple.music.getDetails"],
        .musicLibraryRead: ["apple.music.readLibrary"],
        .musicPlaylistWrite: ["apple.music.writePlaylist"],
        .musicPlaybackControl: ["apple.music.play"],
        .passKitWalletStatus: ["apple.wallet.getStatus"],
        .passKitPassesRead: ["apple.wallet.listPasses"],
        .passKitPassAdd: ["apple.wallet.addPass"],
        .passKitPassPresent: ["apple.wallet.presentPass"],
        .passKitApplePayStatus: ["apple.wallet.canMakePayments"],
        .passKitApplePayPresent: ["apple.wallet.presentPayment"],
        .storeKitProductsRead: ["apple.storekit.listProducts"],
        .storeKitEntitlementsRead: ["apple.storekit.listEntitlements"],
        .storeKitPurchase: ["apple.storekit.purchase"],
        .storeKitRestore: ["apple.storekit.restore"],
        .storeKitTransactionsRead: ["apple.storekit.listTransactions"],
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
