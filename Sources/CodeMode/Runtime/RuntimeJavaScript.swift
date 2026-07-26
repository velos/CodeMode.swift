import Foundation

enum RuntimeJavaScript {
    /// Shared by the execution and search runtimes.
    private static let timerRuntime = """
    // A real timer queue, drained by the host between JavaScript turns.
    //
    // `setTimeout` used to invoke its callback synchronously and ignore the
    // delay, which made three things wrong at once: `clearTimeout` could never
    // cancel, an error thrown by the callback propagated to setTimeout's *caller*
    // rather than being an uncaught task error, and
    // `await new Promise(r => setTimeout(r, 2000))` — the standard backoff — was
    // a hot loop that hammered remote APIs through `fetch`.
    globalThis.__codemode.timers = { nextID: 1, entries: [] };

    globalThis.setTimeout = function(fn, delay) {
        if (typeof fn !== 'function') {
            return 0;
        }
        const timers = globalThis.__codemode.timers;
        const id = timers.nextID++;
        timers.entries.push({
            id: id,
            fn: fn,
            args: Array.prototype.slice.call(arguments, 2),
            dueIn: Math.max(0, Number(delay) || 0)
        });
        return id;
    };

    globalThis.clearTimeout = function(id) {
        const timers = globalThis.__codemode.timers;
        timers.entries = timers.entries.filter(function(entry){ return entry.id !== id; });
    };

    // Milliseconds until the earliest pending timer, or -1 when none are queued.
    // -1 means nothing can advance the program: under this runtime's synchronous
    // bridge there is no other source of asynchrony.
    globalThis.__codemode.nextTimerDelay = function() {
        const entries = globalThis.__codemode.timers.entries;
        if (entries.length === 0) {
            return -1;
        }
        return entries.reduce(function(min, entry){ return Math.min(min, entry.dueIn); }, Infinity);
    };

    globalThis.__codemode.advanceTimers = function(elapsedMs) {
        const timers = globalThis.__codemode.timers;
        const due = [];
        const remaining = [];
        timers.entries.forEach(function(entry){
            entry.dueIn -= elapsedMs;
            if (entry.dueIn <= 0) { due.push(entry); } else { remaining.push(entry); }
        });
        timers.entries = remaining;
        // Registration order breaks ties, matching a real event loop.
        due.sort(function(a, b){ return a.id - b.id; });
        const errors = [];
        due.forEach(function(entry){
            try {
                entry.fn.apply(null, entry.args);
            } catch (error) {
                // An uncaught error in a task cannot propagate to whoever called
                // setTimeout; the host reports it as a diagnostic instead.
                errors.push(String(error));
            }
        });
        // Returned rather than buffered, so the host needs one round trip per
        // tick instead of two.
        return errors;
    };
    """

    static func pruningScript(removingJavaScriptNames names: some Sequence<String>) -> String {
        let bindingsToRemove = Array(Set(names)).sorted()

        guard bindingsToRemove.isEmpty == false else {
            return ""
        }

        let deleteCalls = bindingsToRemove.map { name in
            "__codemodeDeletePath(\(jsonString(name)));"
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

        let groupCleanupCalls = groupPaths.sorted(by: { lhs, rhs in
            lhs.components(separatedBy: ".").count > rhs.components(separatedBy: ".").count
        }).map { path in
            "__codemodeDeleteIfEmpty(\(jsonString(path)));"
        }

        let rootCleanupCalls = ["apple", "ios", "fs"].map { root in
            "__codemodeDeleteIfEmpty(\(jsonString(root)));"
        }

        return """
        (function(){
            function __codemodeResolveParent(path) {
                const segments = String(path).split('.').filter(function(segment){ return segment.length > 0; });
                if (segments.length === 0) return null;
                let target = globalThis;
                for (let i = 0; i < segments.length - 1; i++) {
                    if (!target || typeof target[segments[i]] === 'undefined') return null;
                    target = target[segments[i]];
                }
                return { target: target, property: segments[segments.length - 1] };
            }
            function __codemodeDeletePath(path) {
                const binding = __codemodeResolveParent(path);
                if (binding && binding.target) delete binding.target[binding.property];
            }
            function __codemodeResolvePath(path) {
                const segments = String(path).split('.').filter(function(segment){ return segment.length > 0; });
                let target = globalThis;
                for (let i = 0; i < segments.length; i++) {
                    if (!target || typeof target[segments[i]] === 'undefined') return undefined;
                    target = target[segments[i]];
                }
                return target;
            }
            function __codemodeDeleteIfEmpty(path) {
                const value = __codemodeResolvePath(path);
                if (value && typeof value === 'object' && Object.keys(value).length === 0) {
                    __codemodeDeletePath(path);
                }
            }
        \(indent((deleteCalls + groupCleanupCalls + rootCleanupCalls).joined(separator: "\n"), prefix: "    "))
        })();
        """
    }

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

    private static func indent(_ value: String, prefix: String) -> String {
        value
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : prefix + $0 }
            .joined(separator: "\n")
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

    \(timerRuntime)
    """

    static let bootstrap = """
    (function(){
    const __codemodeInvokeSync = globalThis.__bridgeInvokeSync;
    delete globalThis.__bridgeInvokeSync;

    globalThis.__codemode = globalThis.__codemode || {};
    globalThis.__codemode.state = 'idle';
    globalThis.__codemode.result = null;
    globalThis.__codemode.error = null;

    function __invoke(capability, args) {
        const payload = JSON.stringify(args ?? {});
        const raw = __codemodeInvokeSync(String(capability), payload);
        const envelope = JSON.parse(String(raw || '{}'));
        if (!envelope.ok) {
            const error = new Error(envelope.error && envelope.error.message ? envelope.error.message : 'Bridge call failed');
            error.code = envelope.error && envelope.error.code ? envelope.error.code : 'BRIDGE_ERROR';
            error.capability = envelope.error && envelope.error.capability ? envelope.error.capability : null;
            error.suggestions = envelope.error && Array.isArray(envelope.error.suggestions) ? envelope.error.suggestions.map(function(value){ return String(value); }) : [];
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

    \(timerRuntime)

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
    // These accept either the object form the catalog advertises —
    // apple.keychain.get({ key }) — or the positional form the examples have
    // always shown. The catalog described object arguments while the wrapper took
    // a positional string, so code written from the metadata sent "[object
    // Object]" as the key.
    function __keychainArgs(first, value) {
        if (first && typeof first === 'object') {
            const args = { key: String(first.key) };
            if (first.value !== undefined) args.value = String(first.value);
            return args;
        }
        const args = { key: String(first) };
        if (value !== undefined) args.value = String(value);
        return args;
    }

    globalThis.apple.keychain = {
        get: function(key) { return __invokeAsync('keychain.read', __keychainArgs(key)); },
        set: function(key, value) { return __invokeAsync('keychain.write', __keychainArgs(key, value)); },
        delete: function(key) { return __invokeAsync('keychain.delete', __keychainArgs(key)); }
    };

    globalThis.apple.location = {
        getPermissionStatus: function(args) { return __invokeAsync('location.read', Object.assign({ mode: 'permissionStatus' }, args || {})); },
        requestPermission: function() { return __invokeAsync('location.permission.request', {}); },
        getCurrentPosition: function(args) { return __invokeAsync('location.read', Object.assign({ mode: 'current' }, args || {})); }
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

    // fs.move / fs.copy refuse an existing destination without an explicit
    // overwrite, so the Node-style aliases need a way to pass one through.
    function __fsDestinationArgs(from, to, options) {
        const args = { from: String(from), to: String(to) };
        if (options && typeof options === 'object') {
            if (options.overwrite !== undefined) args.overwrite = !!options.overwrite;
            if (options.recursive !== undefined) args.recursive = !!options.recursive;
        }
        return args;
    }

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
            rename: function(from, to, options) {
                return __invokeAsync('fs.move', __fsDestinationArgs(from, to, options));
            },
            copyFile: function(from, to, options) {
                return __invokeAsync('fs.copy', __fsDestinationArgs(from, to, options));
            }
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
    globalThis.__codemodeInstallBinding = __codemodeInstallBinding;
    globalThis.__codemodeInstallBindingIfMissing = __codemodeInstallBindingIfMissing;
    })();
    """
}
