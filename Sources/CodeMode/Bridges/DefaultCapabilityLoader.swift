import Foundation

public enum DefaultCapabilityLoader {
    public static func loadAllRegistrations(
        fileSystem: any CodeModeFileSystem = LocalCodeModeFileSystem(),
        networkAccessPolicy: NetworkAccessPolicy = .standard,
        eventInbox: any CodeModeEventInbox = UnavailableCodeModeEventInbox(),
        cloudKitClient: any CloudKitClient = UnavailableCloudKitClient(),
        remoteNotificationsClient: any RemoteNotificationsClient = UnavailableRemoteNotificationsClient(),
        speechClient: any SpeechClient = UnavailableSpeechClient(),
        appIntentsClient: any AppIntentsClient = UnavailableAppIntentsClient(),
        foundationModelsClient: any FoundationModelsClient = UnavailableFoundationModelsClient(),
        activityClient: any ActivityClient = UnavailableActivityClient(),
        mapsClient: any MapsClient = UnavailableMapsClient(),
        musicClient: any MusicClient = UnavailableMusicClient(),
        passKitClient: any PassKitClient = UnavailablePassKitClient(),
        storeKitClient: any StoreKitClient = UnavailableStoreKitClient()
    ) -> [CapabilityRegistration] {
        DefaultCapabilityRegistrationBuilder(
            fileSystem: fileSystem,
            networkAccessPolicy: networkAccessPolicy,
            eventInbox: eventInbox,
            cloudKitClient: cloudKitClient,
            remoteNotificationsClient: remoteNotificationsClient,
            speechClient: speechClient,
            appIntentsClient: appIntentsClient,
            foundationModelsClient: foundationModelsClient,
            activityClient: activityClient,
            mapsClient: mapsClient,
            musicClient: musicClient,
            passKitClient: passKitClient,
            storeKitClient: storeKitClient
        ).loadAll()
    }
}

struct DefaultCapabilityRegistrationBuilder {
    let fs: FileSystemBridge
    let network: NetworkBridge
    let keychain: KeychainBridge
    let location: LocationBridge
    let weather: WeatherBridge
    let eventKit: EventKitBridge
    let contacts: ContactsBridge
    let photos: PhotosBridge
    let vision: VisionBridge
    let notifications: NotificationsBridge
    let alarm: AlarmBridge
    let health: HealthBridge
    let home: HomeBridge
    let media: MediaBridge
    let systemUI: SystemUIBridge
    let eventInbox: any CodeModeEventInbox
    let cloudKit: CloudKitBridge
    let remoteNotifications: RemoteNotificationsBridge
    let speech: SpeechBridge
    let appIntents: AppIntentsBridge
    let foundationModels: FoundationModelsBridge
    let activity: ActivityBridge
    let maps: MapsBridge
    let music: MusicBridge
    let passKit: PassKitBridge
    let storeKit: StoreKitBridge

    init(
        fileSystem: any CodeModeFileSystem,
        networkAccessPolicy: NetworkAccessPolicy,
        eventInbox: any CodeModeEventInbox,
        cloudKitClient: any CloudKitClient,
        remoteNotificationsClient: any RemoteNotificationsClient,
        speechClient: any SpeechClient,
        appIntentsClient: any AppIntentsClient,
        foundationModelsClient: any FoundationModelsClient,
        activityClient: any ActivityClient,
        mapsClient: any MapsClient,
        musicClient: any MusicClient,
        passKitClient: any PassKitClient,
        storeKitClient: any StoreKitClient
    ) {
        self.fs = FileSystemBridge(fileSystem: fileSystem)
        self.network = NetworkBridge(policy: networkAccessPolicy)
        self.keychain = KeychainBridge()
        self.location = LocationBridge()
        self.weather = WeatherBridge()
        self.eventKit = EventKitBridge()
        self.contacts = ContactsBridge()
        self.photos = PhotosBridge()
        self.vision = VisionBridge()
        self.notifications = NotificationsBridge()
        self.alarm = AlarmBridge()
        self.health = HealthBridge()
        self.home = HomeBridge()
        self.media = MediaBridge()
        self.systemUI = SystemUIBridge()
        self.eventInbox = eventInbox
        self.cloudKit = CloudKitBridge(client: cloudKitClient, eventInbox: eventInbox)
        self.remoteNotifications = RemoteNotificationsBridge(client: remoteNotificationsClient, eventInbox: eventInbox)
        self.speech = SpeechBridge(client: speechClient)
        self.appIntents = AppIntentsBridge(client: appIntentsClient, eventInbox: eventInbox)
        self.foundationModels = FoundationModelsBridge(client: foundationModelsClient)
        self.activity = ActivityBridge(client: activityClient)
        self.maps = MapsBridge(client: mapsClient)
        self.music = MusicBridge(client: musicClient)
        self.passKit = PassKitBridge(client: passKitClient)
        self.storeKit = StoreKitBridge(client: storeKitClient, eventInbox: eventInbox)
    }

    func loadAll() -> [CapabilityRegistration] {
        [
            networkRegistrations(),
            keychainRegistrations(),
            locationAndWeatherRegistrations(),
            calendarAndReminderRegistrations(),
            contactRegistrations(),
            photoAndDocumentRegistrations(),
            interactionUIRegistrations(),
            visionRegistrations(),
            notificationRegistrations(),
            alarmRegistrations(),
            healthRegistrations(),
            homeRegistrations(),
            mediaRegistrations(),
            bigTicketAppleRegistrations(),
            filesystemRegistrations(),
        ].flatMap { $0 }
    }
}
