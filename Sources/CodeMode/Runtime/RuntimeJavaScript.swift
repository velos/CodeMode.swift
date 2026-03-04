import Foundation

enum RuntimeJavaScript {
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
            throw error;
        }
        return envelope.value;
    }

    function __invokeAsync(capability, args) {
        return Promise.resolve().then(function(){ return __invoke(capability, args); });
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
        globalThis.URL = function(url){ this.href = String(url); };
    }

    function __response(payload) {
        const bodyText = payload && payload.bodyText ? String(payload.bodyText) : '';
        return {
            ok: !!(payload && payload.ok),
            status: payload && payload.status ? Number(payload.status) : 0,
            statusText: payload && payload.statusText ? String(payload.statusText) : '',
            headers: payload && payload.headers ? payload.headers : {},
            text: function(){ return Promise.resolve(bodyText); },
            json: function(){ return Promise.resolve(bodyText.length ? JSON.parse(bodyText) : null); }
        };
    }

    globalThis.fetch = function(url, options) {
        return __invokeAsync('network.fetch', { url: String(url), options: options || {} }).then(__response);
    };

    globalThis.ios = globalThis.ios || {};
    globalThis.ios.keychain = {
        get: function(key) { return __invokeAsync('keychain.read', { key: String(key) }); },
        set: function(key, value) { return __invokeAsync('keychain.write', { key: String(key), value: String(value) }); },
        delete: function(key) { return __invokeAsync('keychain.delete', { key: String(key) }); }
    };

    globalThis.ios.location = {
        getPermissionStatus: function() { return __invokeAsync('location.read', { mode: 'permissionStatus' }); },
        requestPermission: function() { return __invokeAsync('location.permission.request', {}); },
        getCurrentPosition: function() { return __invokeAsync('location.read', { mode: 'current' }); }
    };

    globalThis.ios.weather = {
        getCurrentWeather: function(coords) { return __invokeAsync('weather.read', coords || {}); }
    };

    globalThis.ios.calendar = {
        listEvents: function(args) { return __invokeAsync('calendar.read', args || {}); },
        createEvent: function(args) { return __invokeAsync('calendar.write', args || {}); }
    };

    globalThis.ios.reminders = {
        listReminders: function(args) { return __invokeAsync('reminders.read', args || {}); },
        createReminder: function(args) { return __invokeAsync('reminders.write', args || {}); }
    };

    globalThis.ios.contacts = {
        list: function(args) { return __invokeAsync('contacts.read', args || {}); },
        search: function(args) { return __invokeAsync('contacts.search', args || {}); }
    };

    globalThis.ios.photos = {
        list: function(args) { return __invokeAsync('photos.read', args || {}); },
        export: function(args) { return __invokeAsync('photos.export', args || {}); }
    };

    globalThis.ios.vision = {
        analyzeImage: function(args) { return __invokeAsync('vision.image.analyze', args || {}); }
    };

    globalThis.ios.notifications = {
        requestPermission: function() { return __invokeAsync('notifications.permission.request', {}); },
        schedule: function(args) { return __invokeAsync('notifications.schedule', args || {}); },
        listPending: function(args) { return __invokeAsync('notifications.pending.read', args || {}); },
        cancelPending: function(args) { return __invokeAsync('notifications.pending.delete', args || {}); }
    };

    globalThis.ios.alarm = {
        requestPermission: function() { return __invokeAsync('alarm.permission.request', {}); },
        list: function(args) { return __invokeAsync('alarm.read', args || {}); },
        schedule: function(args) { return __invokeAsync('alarm.schedule', args || {}); },
        cancel: function(args) { return __invokeAsync('alarm.cancel', args || {}); }
    };

    globalThis.ios.home = {
        list: function(args) { return __invokeAsync('home.read', args || {}); },
        writeCharacteristic: function(args) { return __invokeAsync('home.write', args || {}); }
    };

    globalThis.ios.media = {
        metadata: function(args) { return __invokeAsync('media.metadata.read', args || {}); },
        extractFrame: function(args) { return __invokeAsync('media.frame.extract', args || {}); },
        transcode: function(args) { return __invokeAsync('media.transcode', args || {}); }
    };

    globalThis.ios.fs = {
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
