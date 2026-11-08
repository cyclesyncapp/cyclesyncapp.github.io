// CycleSync service worker.
// 1. Shows reminder notifications sent by web push (text is always neutral).
// 2. Caches the app's own files so it opens faster, uses less data and still
//    starts without signal. Personal data (Supabase requests) is never cached.

var CACHE = 'cyclesync-app-v1';

self.addEventListener('install', function () {
  self.skipWaiting();
});

self.addEventListener('activate', function (event) {
  event.waitUntil(
    caches.keys().then(function (keys) {
      return Promise.all(keys.filter(function (k) {
        return k.indexOf('cyclesync-app-') === 0 && k !== CACHE;
      }).map(function (k) { return caches.delete(k); }));
    }).then(function () { return self.clients.claim(); })
  );
});

function isAppFile(url) {
  // Same-origin app files, or Flutter's versioned engine files on gstatic.
  if (url.origin === self.location.origin) return true;
  return url.hostname === 'www.gstatic.com' &&
      url.pathname.indexOf('/flutter-canvaskit/') === 0;
}

function isVersioned(url) {
  // Engine files live under a version hash and never change.
  return url.pathname.indexOf('/flutter-canvaskit/') === 0 ||
      /\/(canvaskit|assets\/fonts|assets\/assets\/fonts|icons)\//.test(url.pathname);
}

self.addEventListener('fetch', function (event) {
  var req = event.request;
  if (req.method !== 'GET') return;
  var url = new URL(req.url);
  if (!isAppFile(url)) return; // never touch API or other requests

  if (isVersioned(url)) {
    // Cache first: these never change for a given version.
    event.respondWith(
      caches.open(CACHE).then(function (cache) {
        return cache.match(req).then(function (hit) {
          return hit || fetch(req).then(function (res) {
            if (res.ok) cache.put(req, res.clone());
            return res;
          });
        });
      })
    );
    return;
  }

  // Everything else (index.html, main.dart.js, manifest…): network first so
  // updates arrive straight away, cached copy when offline.
  event.respondWith(
    fetch(req).then(function (res) {
      if (res.ok) {
        var copy = res.clone();
        caches.open(CACHE).then(function (cache) { cache.put(req, copy); });
      }
      return res;
    }).catch(function () {
      return caches.match(req).then(function (hit) {
        return hit || caches.match('./');
      });
    })
  );
});

self.addEventListener('push', function (event) {
  var data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (e) {
    data = {};
  }
  var options = {
    body: data.body || 'You have a CycleSync reminder',
    icon: 'icons/Icon-192.png',
    badge: 'icons/Icon-192.png',
    tag: 'cyclesync',
    renotify: true,
  };
  event.waitUntil(
    self.registration.showNotification(data.title || 'CycleSync', options)
  );
});

self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true })
      .then(function (clients) {
        for (var i = 0; i < clients.length; i++) {
          if ('focus' in clients[i]) return clients[i].focus();
        }
        return self.clients.openWindow(self.registration.scope);
      })
  );
});
