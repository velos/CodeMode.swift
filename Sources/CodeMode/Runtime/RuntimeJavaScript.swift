import Foundation

enum RuntimeJavaScript {
    static func builtInBootstrap(for registrations: [CapabilityRegistration]) -> String {
        let commands = registrations
            .sorted { $0.descriptor.id.rawValue < $1.descriptor.id.rawValue }
            .flatMap { registration in
                registration.jsNames.sorted().map { jsName in
                    "__codemodeInstallBindingIfMissing(\(jsonString(jsName)), \(jsonString(registration.descriptor.id.codeModeKey.rawValue)));"
                }
            }
        guard commands.isEmpty == false else {
            return ""
        }
        return commands.joined(separator: "\n")
    }

    static func providerBootstrap(for registrations: [CodeModeRegistration]) -> String {
        let commands = registrations
            .sorted { $0.jsPath < $1.jsPath }
            .map { registration in
                "__codemodeInstallBinding(\(jsonString(registration.jsPath)), \(jsonString(registration.capabilityKey.rawValue)));"
            }
        guard commands.isEmpty == false else {
            return ""
        }
        return commands.joined(separator: "\n")
    }

    private static func jsonString(_ value: String) -> String {
        guard let data = try? JSONEncoder.codeModeBridge.encode(value),
              let string = String(data: data, encoding: .utf8)
        else {
            return "\"\""
        }
        return string
    }

    static let searchBootstrap = """
    globalThis.__codemode = globalThis.__codemode || {};
    globalThis.__codemode.state = 'idle';
    globalThis.__codemode.result = null;
    globalThis.__codemode.error = null;

    globalThis.console = {
        log: function(){ __searchConsole('info', Array.from(arguments).map(function(v){ return String(v); }).join(' ')); },
        info: function(){ __searchConsole('info', Array.from(arguments).map(function(v){ return String(v); }).join(' ')); },
        warn: function(){ __searchConsole('warning', Array.from(arguments).map(function(v){ return String(v); }).join(' ')); },
        error: function(){ __searchConsole('error', Array.from(arguments).map(function(v){ return String(v); }).join(' ')); }
    };

    globalThis.setTimeout = function(fn, delay) {
        if (typeof fn === 'function') {
            fn();
        }
        return 0;
    };
    globalThis.clearTimeout = function(_) {};
    """

    static let bootstrap = """
    globalThis.__codemode = globalThis.__codemode || {};
    globalThis.__codemode.state = 'idle';
    globalThis.__codemode.result = null;
    globalThis.__codemode.error = null;

    function __invoke(capability, args) {
        const payload = JSON.stringify(args ?? {});
        const raw = __bridgeInvokeSync(String(capability), payload);
        const envelope = JSON.parse(String(raw || '{}'));
        if (!envelope.ok) {
            const error = new Error(envelope.error && envelope.error.message ? envelope.error.message : 'Bridge call failed');
            error.code = envelope.error && envelope.error.code ? envelope.error.code : 'BRIDGE_ERROR';
            error.capability = envelope.error && envelope.error.capability ? envelope.error.capability : null;
            throw error;
        }
        return envelope.value;
    }

    function __invokeAsync(capability, args) {
        return Promise.resolve().then(function(){ return __invoke(capability, args); });
    }

    function __codemodeResolveBinding(jsPath) {
        const segments = String(jsPath).split('.').filter(function(segment){ return segment.length > 0; });
        if (segments.length === 0) {
            throw new Error('Invalid CodeMode JS path');
        }
        let target = globalThis;
        for (let i = 0; i < segments.length - 1; i++) {
            const segment = segments[i];
            if (!target[segment] || typeof target[segment] !== 'object') {
                target[segment] = {};
            }
            target = target[segment];
        }
        return { target: target, property: segments[segments.length - 1] };
    }

    function __codemodeInstallResolvedBinding(binding, capability) {
        binding.target[binding.property] = function(args) {
            return __invokeAsync(capability, args || {});
        };
    }

    function __codemodeInstallBinding(jsPath, capability) {
        __codemodeInstallResolvedBinding(__codemodeResolveBinding(jsPath), capability);
    }

    function __codemodeInstallBindingIfMissing(jsPath, capability) {
        const binding = __codemodeResolveBinding(jsPath);
        if (typeof binding.target[binding.property] === 'undefined') {
            __codemodeInstallResolvedBinding(binding, capability);
        }
    }

    globalThis.console = {
        log: function(){ __nativeConsoleLog(Array.from(arguments).map(function(v){ return String(v); }).join(' ')); },
        info: function(){ __nativeConsoleLog(Array.from(arguments).map(function(v){ return String(v); }).join(' ')); },
        warn: function(){ __nativeConsoleLog(Array.from(arguments).map(function(v){ return String(v); }).join(' ')); },
        error: function(){ __nativeConsoleLog(Array.from(arguments).map(function(v){ return String(v); }).join(' ')); }
    };

    globalThis.setTimeout = function(fn, delay) {
        if (typeof fn === 'function') {
            fn();
        }
        return 0;
    };
    globalThis.clearTimeout = function(_) {};

    if (typeof URLSearchParams === 'undefined') {
        globalThis.URLSearchParams = function(initial){
            this._value = initial || {};
            this.toString = function(){
                if (typeof this._value === 'string') return this._value;
                const keys = Object.keys(this._value || {});
                return keys.map(function(k){ return encodeURIComponent(k) + '=' + encodeURIComponent(String(this._value[k])); }, this).join('&');
            };
        };
    }

    if (typeof URL === 'undefined') {
        globalThis.URL = function(url){
            this.href = String(url);
            this.toString = function(){ return this.href; };
            this.valueOf = function(){ return this.href; };
        };
    }

    function __response(payload) {
        const bodyText = payload && payload.bodyText ? String(payload.bodyText) : '';
        const bodyBase64 = payload && payload.bodyBase64 ? String(payload.bodyBase64) : '';
        const headerValues = payload && payload.headers ? payload.headers : {};
        const headers = Object.assign({}, headerValues);
        headers.get = function(name) {
            const target = String(name || '').toLowerCase();
            const keys = Object.keys(headerValues);
            for (let i = 0; i < keys.length; i++) {
                if (String(keys[i]).toLowerCase() === target) {
                    return headerValues[keys[i]];
                }
            }
            return null;
        };
        return {
            ok: !!(payload && payload.ok),
            status: payload && payload.status ? Number(payload.status) : 0,
            statusText: payload && payload.statusText ? String(payload.statusText) : '',
            headers: headers,
            text: function(){ return Promise.resolve(bodyText); },
            json: function(){ return Promise.resolve(bodyText.length ? JSON.parse(bodyText) : null); },
            base64: function(){ return Promise.resolve(bodyBase64); }
        };
    }

    globalThis.fetch = function(url, options) {
        return __invokeAsync('network.fetch', { url: String(url), options: options || {} }).then(__response);
    };

    globalThis.apple = globalThis.apple || {};
    globalThis.apple.keychain = {
        get: function(key) { return __invokeAsync('keychain.read', { key: String(key) }); },
        set: function(key, value) { return __invokeAsync('keychain.write', { key: String(key), value: String(value) }); },
        delete: function(key) { return __invokeAsync('keychain.delete', { key: String(key) }); }
    };

    globalThis.apple.location = {
        getPermissionStatus: function() { return __invokeAsync('location.read', { mode: 'permissionStatus' }); },
        requestPermission: function() { return __invokeAsync('location.permission.request', {}); },
        getCurrentPosition: function() { return __invokeAsync('location.read', { mode: 'current' }); }
    };

    globalThis.apple.weather = {
        getCurrentWeather: function(coords) { return __invokeAsync('weather.read', coords || {}); }
    };

    globalThis.apple.calendar = {
        listEvents: function(args) { return __invokeAsync('calendar.read', args || {}); },
        createEvent: function(args) { return __invokeAsync('calendar.write', Object.assign({}, args || {}, { operation: 'create' })); },
        updateEvent: function(args) { return __invokeAsync('calendar.write', Object.assign({}, args || {}, { operation: 'update' })); },
        deleteEvent: function(args) { return __invokeAsync('calendar.delete', args || {}); },
        pickCalendar: function(args) { return __invokeAsync('calendar.ui.pickCalendar', args || {}); },
        presentEvent: function(args) { return __invokeAsync('calendar.ui.presentEvent', args || {}); },
        presentNewEvent: function(args) { return __invokeAsync('calendar.ui.presentNewEvent', args || {}); }
    };

    globalThis.apple.reminders = {
        listReminders: function(args) { return __invokeAsync('reminders.read', args || {}); },
        createReminder: function(args) { return __invokeAsync('reminders.write', Object.assign({}, args || {}, { operation: 'create' })); },
        updateReminder: function(args) { return __invokeAsync('reminders.write', Object.assign({}, args || {}, { operation: 'update' })); },
        completeReminder: function(args) { return __invokeAsync('reminders.write', Object.assign({ isCompleted: true }, args || {}, { operation: 'complete' })); },
        deleteReminder: function(args) { return __invokeAsync('reminders.delete', args || {}); }
    };

    globalThis.apple.contacts = {
        list: function(args) { return __invokeAsync('contacts.read', args || {}); },
        search: function(args) { return __invokeAsync('contacts.search', args || {}); },
        pick: function(args) { return __invokeAsync('contacts.ui.pick', args || {}); },
        presentContact: function(args) { return __invokeAsync('contacts.ui.presentContact', args || {}); },
        presentNewContact: function(args) { return __invokeAsync('contacts.ui.presentNewContact', args || {}); }
    };

    globalThis.apple.photos = {
        list: function(args) { return __invokeAsync('photos.read', args || {}); },
        export: function(args) { return __invokeAsync('photos.export', args || {}); },
        pick: function(args) { return __invokeAsync('photos.ui.pick', args || {}); },
        presentLimitedLibraryPicker: function(args) { return __invokeAsync('photos.ui.presentLimitedLibraryPicker', args || {}); }
    };

    globalThis.apple.documents = {
        pick: function(args) { return __invokeAsync('documents.ui.pick', args || {}); },
        export: function(args) { return __invokeAsync('documents.ui.export', args || {}); },
        save: function(args) { return __invokeAsync('documents.ui.export', args || {}); },
        openIn: function(args) { return __invokeAsync('documents.ui.openIn', args || {}); },
        scan: function(args) { return __invokeAsync('documents.ui.scan', args || {}); }
    };

    globalThis.apple.share = {
        present: function(args) { return __invokeAsync('share.ui.present', args || {}); }
    };

    globalThis.apple.quicklook = {
        preview: function(args) { return __invokeAsync('quicklook.ui.preview', args || {}); }
    };

    globalThis.apple.camera = {
        capture: function(args) { return __invokeAsync('camera.ui.capture', args || {}); },
        scanData: function(args) { return __invokeAsync('camera.ui.scanData', args || {}); }
    };

    globalThis.apple.mail = {
        compose: function(args) { return __invokeAsync('mail.ui.compose', args || {}); }
    };

    globalThis.apple.messages = {
        compose: function(args) { return __invokeAsync('messages.ui.compose', args || {}); }
    };

    globalThis.apple.print = {
        present: function(args) { return __invokeAsync('print.ui.present', args || {}); }
    };

    globalThis.apple.web = {
        present: function(args) { return __invokeAsync('web.ui.present', args || {}); }
    };

    globalThis.apple.auth = {
        webAuthenticate: function(args) { return __invokeAsync('auth.ui.webAuthenticate', args || {}); }
    };

    globalThis.apple.ui = {
        presentAlert: function(args) { return __invokeAsync('ui.alert.present', args || {}); },
        presentPrompt: function(args) { return __invokeAsync('ui.prompt.present', args || {}); }
    };

    globalThis.apple.settings = {
        open: function(args) { return __invokeAsync('settings.ui.open', args || {}); }
    };

    globalThis.apple.vision = {
        analyzeImage: function(args) { return __invokeAsync('vision.image.analyze', args || {}); }
    };

    globalThis.apple.notifications = {
        requestPermission: function() { return __invokeAsync('notifications.permission.request', {}); },
        schedule: function(args) { return __invokeAsync('notifications.schedule', args || {}); },
        listPending: function(args) { return __invokeAsync('notifications.pending.read', args || {}); },
        cancelPending: function(args) { return __invokeAsync('notifications.pending.delete', args || {}); },
        listDelivered: function(args) { return __invokeAsync('notifications.delivered.read', args || {}); },
        removeDelivered: function(args) { return __invokeAsync('notifications.delivered.delete', args || {}); },
        registerRemote: function(args) { return __invokeAsync('notifications.remote.register', args || {}); },
        getRemoteToken: function(args) { return __invokeAsync('notifications.remote.token.read', args || {}); },
        getSettings: function(args) { return __invokeAsync('notifications.settings.read', args || {}); },
        setCategories: function(args) { return __invokeAsync('notifications.categories.set', args || {}); },
        listResponses: function(args) { return __invokeAsync('notifications.responses.read', args || {}); }
    };

    globalThis.ios = globalThis.ios || {};
    globalThis.ios.alarm = {
        requestPermission: function() { return __invokeAsync('alarm.permission.request', {}); },
        list: function(args) { return __invokeAsync('alarm.read', args || {}); },
        schedule: function(args) { return __invokeAsync('alarm.schedule', args || {}); },
        cancel: function(args) { return __invokeAsync('alarm.cancel', args || {}); }
    };

    globalThis.apple.health = {
        requestPermission: function(args) { return __invokeAsync('health.permission.request', args || {}); },
        read: function(args) { return __invokeAsync('health.read', args || {}); },
        write: function(args) { return __invokeAsync('health.write', args || {}); }
    };

    globalThis.apple.home = {
        list: function(args) { return __invokeAsync('home.read', args || {}); },
        writeCharacteristic: function(args) { return __invokeAsync('home.write', args || {}); }
    };

    globalThis.apple.media = {
        metadata: function(args) { return __invokeAsync('media.metadata.read', args || {}); },
        extractFrame: function(args) { return __invokeAsync('media.frame.extract', args || {}); },
        transcode: function(args) { return __invokeAsync('media.transcode', args || {}); }
    };

    globalThis.apple.cloudkit = {
        getAccountStatus: function(args) { return __invokeAsync('cloudkit.account.status', args || {}); },
        queryRecords: function(args) { return __invokeAsync('cloudkit.records.query', args || {}); },
        saveRecord: function(args) { return __invokeAsync('cloudkit.record.save', args || {}); },
        deleteRecord: function(args) { return __invokeAsync('cloudkit.record.delete', args || {}); },
        subscribe: function(args) { return __invokeAsync('cloudkit.subscription.save', args || {}); },
        listEvents: function(args) { return __invokeAsync('cloudkit.subscriptionEvents.read', args || {}); }
    };

    globalThis.apple.speech = {
        requestPermission: function() { return __invokeAsync('speech.permission.request', {}); },
        getStatus: function() { return __invokeAsync('speech.status', {}); },
        transcribeFile: function(args) { return __invokeAsync('speech.file.transcribe', args || {}); },
        transcribeMicrophone: function(args) { return __invokeAsync('speech.microphone.transcribe', args || {}); }
    };

    globalThis.apple.appIntents = {
        list: function(args) { return __invokeAsync('appintents.list', args || {}); },
        run: function(args) { return __invokeAsync('appintents.run', args || {}); },
        donate: function(args) { return __invokeAsync('appintents.donate', args || {}); },
        open: function(args) { return __invokeAsync('appintents.open', args || {}); },
        listHandoffs: function(args) { return __invokeAsync('appintents.handoffs.read', args || {}); }
    };

    globalThis.apple.foundationModels = {
        getStatus: function(args) { return __invokeAsync('foundationModels.status', args || {}); },
        generate: function(args) { return __invokeAsync('foundationModels.generate', args || {}); },
        extract: function(args) { return __invokeAsync('foundationModels.extract', args || {}); }
    };

    globalThis.apple.activity = {
        list: function(args) { return __invokeAsync('activity.list', args || {}); },
        start: function(args) { return __invokeAsync('activity.start', args || {}); },
        update: function(args) { return __invokeAsync('activity.update', args || {}); },
        end: function(args) { return __invokeAsync('activity.end', args || {}); },
        getPushToken: function(args) { return __invokeAsync('activity.pushToken.read', args || {}); }
    };

    globalThis.apple.maps = {
        geocode: function(args) { return __invokeAsync('maps.geocode', args || {}); },
        reverseGeocode: function(args) { return __invokeAsync('maps.reverseGeocode', args || {}); },
        search: function(args) { return __invokeAsync('maps.search', args || {}); },
        routeEstimate: function(args) { return __invokeAsync('maps.route.estimate', args || {}); },
        open: function(args) { return __invokeAsync('maps.open', args || {}); }
    };

    globalThis.apple.music = {
        requestPermission: function() { return __invokeAsync('music.permission.request', {}); },
        getSubscriptionStatus: function(args) { return __invokeAsync('music.subscription.status', args || {}); },
        search: function(args) { return __invokeAsync('music.catalog.search', args || {}); },
        getDetails: function(args) { return __invokeAsync('music.catalog.details', args || {}); },
        readLibrary: function(args) { return __invokeAsync('music.library.read', args || {}); },
        writePlaylist: function(args) { return __invokeAsync('music.playlist.write', args || {}); },
        play: function(args) { return __invokeAsync('music.playback.control', args || {}); }
    };

    globalThis.apple.wallet = {
        getStatus: function(args) { return __invokeAsync('passkit.wallet.status', args || {}); },
        listPasses: function(args) { return __invokeAsync('passkit.passes.read', args || {}); },
        addPass: function(args) { return __invokeAsync('passkit.pass.add', args || {}); },
        presentPass: function(args) { return __invokeAsync('passkit.pass.present', args || {}); },
        canMakePayments: function(args) { return __invokeAsync('passkit.applePay.status', args || {}); },
        presentPayment: function(args) { return __invokeAsync('passkit.applePay.present', args || {}); }
    };

    globalThis.apple.storekit = {
        listProducts: function(args) { return __invokeAsync('storekit.products.read', args || {}); },
        listEntitlements: function(args) { return __invokeAsync('storekit.entitlements.read', args || {}); },
        purchase: function(args) { return __invokeAsync('storekit.purchase', args || {}); },
        restore: function(args) { return __invokeAsync('storekit.restore', args || {}); },
        listTransactions: function(args) { return __invokeAsync('storekit.transactions.read', args || {}); }
    };

    globalThis.apple.fs = {
        list: function(args) { return __invokeAsync('fs.list', args || {}); },
        read: function(args) { return __invokeAsync('fs.read', args || {}); },
        write: function(args) { return __invokeAsync('fs.write', args || {}); },
        move: function(args) { return __invokeAsync('fs.move', args || {}); },
        copy: function(args) { return __invokeAsync('fs.copy', args || {}); },
        delete: function(args) { return __invokeAsync('fs.delete', args || {}); },
        stat: function(args) { return __invokeAsync('fs.stat', args || {}); },
        mkdir: function(args) { return __invokeAsync('fs.mkdir', args || {}); },
        exists: function(args) { return __invokeAsync('fs.exists', args || {}); },
        access: function(args) { return __invokeAsync('fs.access', args || {}); }
    };

    globalThis.fs = {
        promises: {
            readFile: function(path, options) {
                const args = { path: String(path) };
                if (typeof options === 'string') args.encoding = options;
                if (options && typeof options === 'object' && options.encoding) args.encoding = String(options.encoding);
                return __invokeAsync('fs.read', args).then(function(value) {
                    return value.text;
                });
            },
            writeFile: function(path, data, options) {
                const args = { path: String(path), data: String(data) };
                if (typeof options === 'string') args.encoding = options;
                if (options && typeof options === 'object' && options.encoding) args.encoding = String(options.encoding);
                return __invokeAsync('fs.write', args);
            },
            readdir: function(path) { return __invokeAsync('fs.list', { path: String(path) }); },
            stat: function(path) { return __invokeAsync('fs.stat', { path: String(path) }); },
            access: function(path) { return __invokeAsync('fs.access', { path: String(path) }); },
            mkdir: function(path, options) {
                return __invokeAsync('fs.mkdir', { path: String(path), recursive: !!(options && options.recursive) });
            },
            rm: function(path, options) {
                return __invokeAsync('fs.delete', { path: String(path), recursive: !!(options && options.recursive) });
            },
            rename: function(from, to) { return __invokeAsync('fs.move', { from: String(from), to: String(to) }); },
            copyFile: function(from, to) { return __invokeAsync('fs.copy', { from: String(from), to: String(to) }); }
        }
    };

    globalThis.path = {
        join: function() {
            return Array.from(arguments)
                .map(function(part) { return String(part || '').replace(/^\\/+|\\/+$/g, ''); })
                .filter(function(part) { return part.length > 0; })
                .join('/');
        }
    };
    """
}
