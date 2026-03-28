(function () {
    if (window.__ihpHtmxInstantClickInitialized) {
        return;
    }
    window.__ihpHtmxInstantClickInitialized = true;

    var PREFETCH_TTL_MS = 30000;
    var NAVIGATION_ARM_MS = 1000;
    var prefetchCache = Object.create(null);
    var pendingNavigation = null;

    function now() {
        return Date.now();
    }

    function toAbsoluteUrl(href) {
        try {
            return new URL(href, window.location.href).href;
        } catch (error) {
            return null;
        }
    }

    function getClosestAttribute(node, attribute) {
        if (!node || !node.getAttribute) {
            return null;
        }

        return (
            node.getAttribute(attribute) ||
            node.getAttribute('data-' + attribute) ||
            getClosestAttribute(node.parentElement, attribute)
        );
    }

    function preloadAttributeEnabled(link) {
        var value =
            getClosestAttribute(link, 'hx-preload') ||
            getClosestAttribute(link, 'turbolinks-preload');

        return value !== 'false';
    }

    function getPreloadKey(link) {
        if (!(link instanceof HTMLAnchorElement)) {
            return null;
        }

        return toAbsoluteUrl(link.getAttribute('href'));
    }

    function getFreshCacheEntry(key) {
        var entry = key ? prefetchCache[key] : null;

        if (!entry) {
            return null;
        }

        if (entry.expiresAt <= now()) {
            delete prefetchCache[key];
            return null;
        }

        return entry;
    }

    function clearPendingNavigation() {
        pendingNavigation = null;
    }

    function isPreloadableLink(link) {
        if (!(link instanceof HTMLAnchorElement)) {
            return false;
        }

        if (getClosestAttribute(link, 'hx-boost') !== 'true') {
            return false;
        }

        if (!preloadAttributeEnabled(link)) {
            return false;
        }

        if (
            link.classList.contains('js-delete') ||
            link.hasAttribute('hx-delete') ||
            link.hasAttribute('data-hx-delete') ||
            link.hasAttribute('hx-post') ||
            link.hasAttribute('data-hx-post') ||
            link.hasAttribute('hx-put') ||
            link.hasAttribute('data-hx-put') ||
            link.hasAttribute('hx-patch') ||
            link.hasAttribute('data-hx-patch')
        ) {
            return false;
        }

        if (link.hasAttribute('download')) {
            return false;
        }

        var target = link.getAttribute('target');
        if (target && target !== '_self') {
            return false;
        }

        var href = link.getAttribute('href');
        var preloadKey = getPreloadKey(link);
        if (!href || !preloadKey) {
            return false;
        }

        try {
            var url = new URL(href, window.location.href);
            return (
                url.origin === window.location.origin &&
                !url.hash &&
                !href.match(/#$/) &&
                url.href !== window.location.href
            );
        } catch (error) {
            return false;
        }
    }

    function parseResponseHeaders(rawHeaders) {
        var headers = Object.create(null);

        if (!rawHeaders) {
            return headers;
        }

        rawHeaders
            .trim()
            .split(/[\r\n]+/)
            .forEach(function (line) {
                var separatorIndex = line.indexOf(':');
                if (separatorIndex <= 0) {
                    return;
                }

                var key = line.slice(0, separatorIndex).trim().toLowerCase();
                var value = line.slice(separatorIndex + 1).trim();
                if (key) {
                    headers[key] = value;
                }
            });

        return headers;
    }

    function buildProgressEvent(name, loaded, total) {
        if (typeof window.ProgressEvent === 'function') {
            return new ProgressEvent(name, {
                lengthComputable: true,
                loaded: loaded,
                total: total,
            });
        }

        return new Event(name);
    }

    function emitXhrEvent(xhr, name, event) {
        var handler = xhr['on' + name];

        if (xhr.dispatchEvent) {
            xhr.dispatchEvent(event);
            return;
        }

        if (typeof handler === 'function') {
            handler.call(xhr, event);
        }
    }

    function defineXhrValue(xhr, property, value) {
        Object.defineProperty(xhr, property, {
            configurable: true,
            get: function () {
                return value;
            },
        });
    }

    function deliverPrefetchedResponse(xhr, entry) {
        var bodyLength = entry.responseText ? entry.responseText.length : 0;
        var statusText = entry.status >= 200 && entry.status < 400 ? 'OK' : '';

        defineXhrValue(xhr, 'readyState', 4);
        defineXhrValue(xhr, 'status', entry.status);
        defineXhrValue(xhr, 'statusText', statusText);
        defineXhrValue(xhr, 'responseText', entry.responseText);
        defineXhrValue(xhr, 'response', entry.responseText);
        defineXhrValue(xhr, 'responseURL', entry.responseURL);

        xhr.getResponseHeader = function (name) {
            if (!name) {
                return null;
            }

            return entry.headers[String(name).toLowerCase()] || null;
        };

        xhr.getAllResponseHeaders = function () {
            return entry.rawHeaders;
        };

        window.setTimeout(function () {
            emitXhrEvent(xhr, 'readystatechange', new Event('readystatechange'));
            emitXhrEvent(xhr, 'loadstart', buildProgressEvent('loadstart', 0, bodyLength));
            emitXhrEvent(xhr, 'progress', buildProgressEvent('progress', bodyLength, bodyLength));
            emitXhrEvent(xhr, 'load', buildProgressEvent('load', bodyLength, bodyLength));
            emitXhrEvent(xhr, 'loadend', buildProgressEvent('loadend', bodyLength, bodyLength));
        }, 0);
    }

    function findPreloadableLink(target) {
        var link = target && target.closest ? target.closest('a[href]') : null;

        return isPreloadableLink(link) ? link : null;
    }

    function prefetchLink(link) {
        var preloadKey = getPreloadKey(link);
        var existingEntry = getFreshCacheEntry(preloadKey);
        var xhr;

        if (!preloadKey) {
            return;
        }

        if (existingEntry && (existingEntry.state === 'loading' || existingEntry.state === 'ready')) {
            return;
        }

        prefetchCache[preloadKey] = {
            state: 'loading',
            expiresAt: now() + PREFETCH_TTL_MS,
        };

        xhr = new XMLHttpRequest();

        xhr.open('GET', preloadKey, true);
        xhr.overrideMimeType('text/html');
        xhr.setRequestHeader('HX-Request', 'true');
        xhr.setRequestHeader('HX-Boosted', 'true');
        xhr.setRequestHeader('HX-Current-URL', window.location.href);
        xhr.setRequestHeader('HX-Preloaded', 'true');

        xhr.onload = function () {
            if (
                xhr.status >= 200 &&
                xhr.status < 400 &&
                xhr.status !== 204 &&
                typeof xhr.responseText === 'string' &&
                xhr.responseText.length > 0
            ) {
                prefetchCache[preloadKey] = {
                    state: 'ready',
                    status: xhr.status,
                    responseText: xhr.responseText,
                    responseURL: xhr.responseURL || preloadKey,
                    rawHeaders: xhr.getAllResponseHeaders() || '',
                    headers: parseResponseHeaders(xhr.getAllResponseHeaders() || ''),
                    expiresAt: now() + PREFETCH_TTL_MS,
                };
                return;
            }

            delete prefetchCache[preloadKey];
        };

        xhr.onerror = function () {
            delete prefetchCache[preloadKey];
        };

        xhr.onabort = function () {
            delete prefetchCache[preloadKey];
        };

        xhr.ontimeout = function () {
            delete prefetchCache[preloadKey];
        };

        try {
            xhr.send();
        } catch (error) {
            delete prefetchCache[preloadKey];
            console.error('Failed to preload boosted link', link, error);
        }
    }

    var originalOpen = XMLHttpRequest.prototype.open;
    var originalSend = XMLHttpRequest.prototype.send;
    var originalSetRequestHeader = XMLHttpRequest.prototype.setRequestHeader;

    XMLHttpRequest.prototype.open = function () {
        this.__ihpInstantClickMethod = arguments[0]
            ? String(arguments[0]).toUpperCase()
            : '';
        this.__ihpInstantClickUrl = toAbsoluteUrl(arguments[1]);
        this.__ihpInstantClickHeaders = Object.create(null);

        return originalOpen.apply(this, arguments);
    };

    XMLHttpRequest.prototype.setRequestHeader = function (name, value) {
        if (!this.__ihpInstantClickHeaders) {
            this.__ihpInstantClickHeaders = Object.create(null);
        }

        this.__ihpInstantClickHeaders[String(name).toLowerCase()] = String(value);

        return originalSetRequestHeader.apply(this, arguments);
    };

    XMLHttpRequest.prototype.send = function () {
        var entry;
        var requestHeaders = this.__ihpInstantClickHeaders || Object.create(null);

        if (pendingNavigation && pendingNavigation.expiresAt <= now()) {
            clearPendingNavigation();
        }

        if (
            pendingNavigation &&
            this.__ihpInstantClickMethod === 'GET' &&
            requestHeaders['hx-boosted'] === 'true' &&
            requestHeaders['hx-preloaded'] !== 'true' &&
            this.__ihpInstantClickUrl === pendingNavigation.key
        ) {
            entry = getFreshCacheEntry(pendingNavigation.key);
            clearPendingNavigation();

            if (entry && entry.state === 'ready') {
                delete prefetchCache[this.__ihpInstantClickUrl];
                deliverPrefetchedResponse(this, entry);
                return;
            }
        }

        return originalSend.apply(this, arguments);
    };

    document.addEventListener(
        'mouseover',
        function (event) {
            var link = findPreloadableLink(event.target);

            if (link) {
                prefetchLink(link);
            }
        },
        { passive: true }
    );

    document.addEventListener(
        'touchstart',
        function (event) {
            var link = findPreloadableLink(event.target);

            if (link) {
                prefetchLink(link);
            }
        },
        { passive: true }
    );

    document.addEventListener(
        'click',
        function (event) {
            var link;
            var preloadKey;
            var entry;

            if (event.defaultPrevented || event.button !== 0) {
                return;
            }

            if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) {
                return;
            }

            link = findPreloadableLink(event.target);
            if (!link) {
                return;
            }

            preloadKey = getPreloadKey(link);
            entry = getFreshCacheEntry(preloadKey);

            if (!entry || entry.state !== 'ready') {
                return;
            }

            pendingNavigation = {
                key: preloadKey,
                expiresAt: now() + NAVIGATION_ARM_MS,
            };

            window.setTimeout(function () {
                if (pendingNavigation && pendingNavigation.key === preloadKey) {
                    clearPendingNavigation();
                }
            }, NAVIGATION_ARM_MS);
        },
        true
    );
})();
