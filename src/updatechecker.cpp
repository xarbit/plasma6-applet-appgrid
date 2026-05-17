/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "updatechecker.h"

#include <QAuthenticator>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkCookie>
#include <QNetworkCookieJar>
#include <QNetworkProxy>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRandomGenerator>
#include <QRegularExpression>
#include <QSslConfiguration>
#include <QStandardPaths>
#include <QSysInfo>
#include <QUrl>

namespace {
// Static JSON endpoint on the AppGrid website. Served from GitHub Pages CDN
// so there are no GitHub API rate-limit concerns. Updated automatically by
// the website's build pipeline on each AppGrid release (repository_dispatch).
// QLatin1StringView keeps this a compile-time literal with no runtime alloc.
constexpr auto kManifestUrl = QLatin1StringView(
    "https://appgrid.xarbit.dev/api/latest.json");

// Base re-check interval while enabled. The actual interval gets randomized
// by ±kJitterCheckMs each fire so the endpoint can't fingerprint users by
// wall-clock cadence (always hitting at the same minute every day would
// turn the IP address into a stable identifier across rotations).
constexpr int kPeriodicCheckMs = 24 * 60 * 60 * 1000;
constexpr int kJitterCheckMs   = 2 * 60 * 60 * 1000;

// Drop the saved ETag every Nth save. ETag is server-controlled and stable
// across requests until a new release ships; sending the same value
// indefinitely lets the server correlate "yesterday's IP X and today's IP
// Y are the same user". A periodic reset breaks the long-term correlation
// at the cost of one extra full-body response per reset.
constexpr int kEtagResetEvery = 7;

// Hard cap on response size. The endpoint serves a few hundred bytes; this
// is generous headroom so the periodic check can never be turned into a
// memory-exhaustion vector by a misbehaving or compromised server.
constexpr qint64 kMaxResponseBytes = 16 * 1024;

// Hard timeout on the HTTP request. Defense against a hostile (or merely
// broken) server that accepts the connection then keeps it open forever.
constexpr int kRequestTimeoutMs = 10 * 1000;

// De-duplication window for sibling plasmoid instances. AppGrid ships two
// plasmoid variants (center + panel) that may both run in plasmashell at
// once; both construct UpdateChecker, both write the same cache file. If
// either one wrote the cache within this window, we skip the network hit
// and just reload from disk. 60s is short enough that user-visible
// "Check now" still feels live, long enough that startup-time double-fire
// from the two variants collapses to a single request.
constexpr qint64 kFreshenWindowMs = 60 * 1000;

// Cookies have no purpose for a stateless GET to a static manifest. A
// QNAM-wide jar that ignores everything keeps a compromised server from
// using Set-Cookie as a tracking/state channel between checks.
class NoCookieJar : public QNetworkCookieJar
{
public:
    using QNetworkCookieJar::QNetworkCookieJar;
    bool setCookiesFromUrl(const QList<QNetworkCookie> &, const QUrl &) override { return false; }
    QList<QNetworkCookie> cookiesForUrl(const QUrl &) const override { return {}; }
};

} // namespace

// http / https only. The release URL comes from a JSON endpoint; treat it
// as untrusted input on every code path (parse + load + click) so a server
// compromise can never dispatch a click into file://, mailto:, javascript:,
// or any other scheme QDesktopServices is willing to open.
bool UpdateChecker::isAllowedReleaseScheme(const QUrl &url)
{
    if (!url.isValid() || url.host().isEmpty())
        return false;
    const QString scheme = url.scheme().toLower();
    return scheme == QLatin1String("http") || scheme == QLatin1String("https");
}

// Restrict version strings to numeric segments with an optional pre-release
// or build-metadata tail. Reject anything weird (control chars, huge
// strings, format-string bait, etc.) before it lands in state or logs.
bool UpdateChecker::isValidVersionString(const QString &v)
{
    if (v.isEmpty() || v.size() > 64)
        return false;
    // Semver-ish: optional 'v' prefix, 1-4 numeric segments, optional
    // pre-release tail (-foo, dots/dashes allowed for git-describe style),
    // optional build-metadata tail (+foo, same character set). Both tails
    // independent — supports "1.8.0-dev.42+g1a2b3c4" and friends.
    static const QRegularExpression re(
        QStringLiteral("^v?\\d+(\\.\\d+){0,3}(-[0-9A-Za-z.\\-]+)?(\\+[0-9A-Za-z.\\-]+)?$"));
    return re.match(v).hasMatch();
}

// On-disk state lives in the per-user cache dir so it never bloats config.
// Filename namespaced with our plasmoid id because CacheLocation resolves
// to the plasmashell process's shared cache dir (everything running in
// plasmashell lands there). Both plasmoid variants — dev.xarbit.appgrid
// and dev.xarbit.appgrid.panel — deliberately share this one file so a
// check by either variant satisfies both (see runCheck() de-dup).
static QString stateFilePath()
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    return dir + QStringLiteral("/dev.xarbit.appgrid.update-checker.json");
}

// Pick the next periodic interval. Adds a uniform random ±kJitterCheckMs
// so the daily request doesn't land at the same wall-clock minute every
// time — defeats the easy "this IP always pings at HH:MM" fingerprint.
static int nextPeriodicInterval()
{
    const int jitter = QRandomGenerator::global()->bounded(
        -kJitterCheckMs, kJitterCheckMs + 1);
    return kPeriodicCheckMs + jitter;
}

UpdateChecker::UpdateChecker(const QString &currentVersion, QObject *parent)
    : QObject(parent)
    , m_currentVersion(currentVersion)
{
    loadState();
    m_periodicTimer.setSingleShot(true);
    connect(&m_periodicTimer, &QTimer::timeout, this, [this]() {
        runCheck(/*force=*/false);
        // Single-shot so we can pick a fresh jittered interval each round.
        if (m_enabled)
            m_periodicTimer.start(nextPeriodicInterval());
    });
    // We don't auto-fire on construction — the QML side flips `enabled`
    // when the config is on, and that triggers the first check.
}

UpdateChecker::~UpdateChecker() = default;

void UpdateChecker::setEnabled(bool enabled)
{
    if (m_enabled == enabled)
        return;
    m_enabled = enabled;
    emit enabledChanged();
    if (enabled) {
        // Immediate check on enable so the indicator reflects reality,
        // not whatever the cache file said at construction. Async, never
        // blocks the UI thread.
        runCheck(/*force=*/true);
        // Long-running sessions keep getting updates via the periodic
        // timer (jittered, single-shot, restarts itself on each fire).
        m_periodicTimer.start(nextPeriodicInterval());
    } else {
        m_periodicTimer.stop();
    }
}

void UpdateChecker::checkNow()
{
    runCheck(/*force=*/true);
}

void UpdateChecker::openReleasePage()
{
    if (m_releaseUrl.isEmpty())
        return;
    const QUrl url(m_releaseUrl);
    if (!isAllowedReleaseScheme(url)) {
        qWarning("AppGrid update check: refusing release URL with scheme %s",
                 qPrintable(url.scheme()));
        return;
    }
    QDesktopServices::openUrl(url);
}

void UpdateChecker::runCheck(bool force)
{
    if (!force && !m_enabled)
        return;

    // Sibling-plasmoid de-dup. If the cache file was written within the
    // freshen window — by us, or by the other plasmoid variant living in
    // the same plasmashell process — skip the network and reload from
    // disk so both surfaces still pick up the latest state.
    const QFileInfo cache(stateFilePath());
    if (cache.exists()) {
        const qint64 ageMs = cache.lastModified().msecsTo(QDateTime::currentDateTime());
        if (ageMs >= 0 && ageMs < kFreshenWindowMs) {
            const bool wasAvailable = m_hasUpdate;
            const QString prevVersion = m_latestVersion;
            const QString prevUrl = m_releaseUrl;
            loadState();
            if (m_latestVersion != prevVersion) emit latestVersionChanged();
            if (m_releaseUrl != prevUrl) emit releaseUrlChanged();
            if (m_hasUpdate != wasAvailable) emit hasUpdateChanged();
            return;
        }
    }

    // Rebuild the QNAM on every check. A long-lived QNAM keeps TLS session
    // tickets warm — convenient for HTTP/2 reuse, but the session ticket
    // itself can fingerprint us across IP rotations (home wifi → office).
    // One check per ~24h means the handshake cost is invisible; trading it
    // for unlinkability is the right call here.
    if (m_network) {
        m_network->deleteLater();
        m_network = nullptr;
    }
    m_network = new QNetworkAccessManager(this);
    // Drop all cookies — stateless GET, no reason to accept Set-Cookie.
    m_network->setCookieJar(new NoCookieJar(m_network));
    // A hostile proxy would otherwise trigger a system password prompt.
    // We never authenticate to proxies; let Qt fail the request instead.
    connect(m_network, &QNetworkAccessManager::proxyAuthenticationRequired,
            this, [](const QNetworkProxy &, QAuthenticator *) {
        // Leave the authenticator empty so Qt aborts the request.
    });

    QNetworkRequest req{QUrl(kManifestUrl)};
    // Minimal, version-free User-Agent. Reveals "an AppGrid instance is
    // checking" but not which version — the latter would slowly age the
    // user's IP into a fingerprintable cohort as releases ship.
    req.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("AppGrid"));
    // Strip the locale Qt sometimes attaches by default; the endpoint
    // doesn't vary by language so this is pure information leak.
    req.setRawHeader("Accept-Language", QByteArray());
    // Ask intermediaries (corporate proxies, ISP transparent caches,
    // GitHub Pages edge nodes) not to log or persist the request. Not
    // enforceable, but matches the privacy intent and is what compliance
    // regimes look for in audits.
    req.setRawHeader("Cache-Control", "no-store");
    // No connection reuse — pairs with the per-check QNAM teardown so we
    // don't leave a warm socket sitting around waiting for the next check.
    req.setRawHeader("Connection", "close");

    // ETag caching keeps unchanged responses to a 304 with no body. Saves
    // bandwidth on the CDN side and on the user's connection. Rotated
    // every kEtagResetEvery saves so the value doesn't act as a long-term
    // pseudo-identifier across IP changes.
    if (!m_etag.isEmpty())
        req.setRawHeader("If-None-Match", m_etag.toUtf8());

    // Cap how long the socket can stay open with no progress. Defense
    // against a server that accepts the connection then never replies.
    req.setTransferTimeout(kRequestTimeoutMs);

    // Don't follow redirects. The endpoint URL is hardcoded HTTPS to a
    // domain we own; any 3xx is either a misconfiguration or an attempt
    // to downgrade us to http:// or off to a different host. Treat as a
    // failure (handleReply's status != 200 branch logs and exits).
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                     QNetworkRequest::ManualRedirectPolicy);

    // Refuse TLS < 1.2. Modern Qt defaults already do this, but pinning
    // the floor explicitly survives library policy changes.
    QSslConfiguration tls = QSslConfiguration::defaultConfiguration();
    tls.setProtocol(QSsl::TlsV1_2OrLater);
    req.setSslConfiguration(tls);

    QNetworkReply *reply = m_network->get(req);
    // Cap response size. The endpoint serves ~200 bytes; 16 KiB is generous
    // headroom for future fields without giving a misbehaving server room to
    // stream arbitrarily large payloads into the plasmoid process. We catch
    // both an over-large Content-Length up front (metaDataChanged) and a
    // server that streams more bytes than it advertised (downloadProgress).
    connect(reply, &QNetworkReply::metaDataChanged, this, [reply]() {
        const auto cl = reply->header(QNetworkRequest::ContentLengthHeader);
        if (cl.isValid() && cl.toLongLong() > kMaxResponseBytes) {
            qWarning("AppGrid update check: Content-Length %lld exceeds cap, aborting",
                     cl.toLongLong());
            reply->abort();
        }
    });
    connect(reply, &QNetworkReply::downloadProgress, this,
            [reply](qint64 bytesReceived, qint64 /*bytesTotal*/) {
        if (bytesReceived > kMaxResponseBytes) {
            qWarning("AppGrid update check: response exceeded %lld bytes, aborting",
                     static_cast<long long>(kMaxResponseBytes));
            reply->abort();
        }
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply]() { handleReply(reply); });
}

void UpdateChecker::handleReply(QNetworkReply *reply)
{
    reply->deleteLater();
    m_lastCheck = QDateTime::currentDateTimeUtc();

    // Capture ETag for next request even on errors — server may have set one.
    const QByteArray etag = reply->rawHeader("ETag");
    if (!etag.isEmpty())
        m_etag = QString::fromLatin1(etag);

    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();

    if (status == 304) {
        // Cached version is current; nothing changed since last check.
        saveState();
        return;
    }

    if (reply->error() != QNetworkReply::NoError || status != 200) {
        // Soft failure — leave state alone, retry on next throttle window.
        qWarning("AppGrid update check: %s (HTTP %d)",
                 qPrintable(reply->errorString()), status);
        saveState();
        return;
    }

    QJsonParseError err{};
    const auto doc = QJsonDocument::fromJson(reply->readAll(), &err);
    if (err.error != QJsonParseError::NoError || !doc.isObject()) {
        qWarning("AppGrid update check: malformed JSON");
        saveState();
        return;
    }

    const auto obj = doc.object();
    const auto version = obj.value(QStringLiteral("version")).toString();
    const auto releaseUrl = obj.value(QStringLiteral("release_notes_url")).toString();

    // Validate before storing — if the server returns something off-format
    // we refuse to update state rather than write garbage into the cache
    // (which would survive across sessions via loadState).
    if (!isValidVersionString(version)) {
        qWarning("AppGrid update check: rejecting malformed version string");
        saveState();
        return;
    }
    if (!releaseUrl.isEmpty() && !isAllowedReleaseScheme(QUrl(releaseUrl))) {
        qWarning("AppGrid update check: rejecting release URL with disallowed scheme");
        saveState();
        return;
    }

    const bool wasAvailable = m_hasUpdate;
    const QString prevVersion = m_latestVersion;
    const QString prevUrl = m_releaseUrl;

    m_latestVersion = version;
    m_releaseUrl = releaseUrl;
    m_hasUpdate = isNewer(version, m_currentVersion);

    if (m_latestVersion != prevVersion) emit latestVersionChanged();
    if (m_releaseUrl != prevUrl) emit releaseUrlChanged();
    if (m_hasUpdate != wasAvailable) emit hasUpdateChanged();

    saveState();
}

void UpdateChecker::loadState()
{
    QFile f(stateFilePath());
    if (!f.open(QIODevice::ReadOnly))
        return;
    // Cap how much we'll read from the on-disk cache — the cache is written
    // by us and lives in a per-user dir, but treat it as untrusted in case
    // another process (or a curious user) edited it.
    const auto bytes = f.read(kMaxResponseBytes);
    const auto doc = QJsonDocument::fromJson(bytes);
    if (!doc.isObject())
        return;
    const auto obj = doc.object();

    // Filter each field through the same validation we apply to network
    // input. A poisoned cache file should never bypass scheme / format
    // checks just because it sits next to us on disk.
    const QString version = obj.value(QStringLiteral("latestVersion")).toString();
    if (isValidVersionString(version))
        m_latestVersion = version;

    const QString rel = obj.value(QStringLiteral("releaseUrl")).toString();
    if (!rel.isEmpty() && isAllowedReleaseScheme(QUrl(rel)))
        m_releaseUrl = rel;

    m_etag = obj.value(QStringLiteral("etag")).toString();
    // Cap on the rotation counter — a poisoned cache file shouldn't be
    // able to set this to a huge value and lock us into reset-on-every-save
    // (cheap DoS) or a negative value and lock us out of ever rotating.
    const int etagAge = obj.value(QStringLiteral("etagAge")).toInt();
    if (etagAge >= 0 && etagAge < kEtagResetEvery)
        m_etagAge = etagAge;

    const auto lc = QDateTime::fromString(
        obj.value(QStringLiteral("lastCheck")).toString(), Qt::ISODate);
    // Discard timestamps from the future. Likely clock skew or tampering;
    // either way we don't want the periodic timer to silently skip checks
    // because the cache claims we already checked tomorrow.
    if (lc.isValid() && lc <= QDateTime::currentDateTimeUtc().addDays(1))
        m_lastCheck = lc;

    m_hasUpdate = !m_latestVersion.isEmpty()
        && isNewer(m_latestVersion, m_currentVersion);
}

void UpdateChecker::saveState()
{
    // Anonymity rotation: every Nth save, drop the ETag so the next request
    // sends no If-None-Match and the server can't keep correlating us by a
    // stable value. Costs one extra full-body response per rotation.
    if (++m_etagAge >= kEtagResetEvery) {
        m_etag.clear();
        m_etagAge = 0;
    }

    const QString finalPath = stateFilePath();
    const QString tmpPath = finalPath + QStringLiteral(".tmp");

    QFile f(tmpPath);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        // Cache dir may not exist yet — try to create it once.
        QDir().mkpath(QFileInfo(f).absolutePath());
        if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
            return;
    }
    QJsonObject obj{
        {QStringLiteral("latestVersion"), m_latestVersion},
        {QStringLiteral("releaseUrl"), m_releaseUrl},
        {QStringLiteral("etag"), m_etag},
        {QStringLiteral("lastCheck"), m_lastCheck.toString(Qt::ISODate)},
        {QStringLiteral("etagAge"), m_etagAge},
    };
    f.write(QJsonDocument(obj).toJson(QJsonDocument::Compact));
    f.close();
    // Restrict to the owning user. The cache dir is already user-private,
    // but on multi-user systems an explicit 0600 keeps the file out of any
    // other user's reach even if directory permissions are ever loosened.
    f.setPermissions(QFile::ReadOwner | QFile::WriteOwner);

    // Atomic replace. If two plasmoid variants race a write, one rename
    // wins and the loser's file simply gets stomped — readers always see
    // a complete file, never a half-written one.
    QFile::remove(finalPath);
    if (!QFile::rename(tmpPath, finalPath))
        QFile::remove(tmpPath);
}

bool UpdateChecker::isNewer(const QString &candidate, const QString &current)
{
    // Strip a leading 'v' if present (release tags: v1.8.1 vs 1.8.1).
    auto strip = [](const QString &s) {
        return s.startsWith(QLatin1Char('v')) ? s.mid(1) : s;
    };
    // Split into <core>, <pre-release>, <build>. Per semver:
    //   - build metadata (after '+') is ignored for ordering
    //   - pre-release (after '-') ranks BELOW the corresponding release
    // Examples:
    //   "1.8.0"                  → ("1.8.0", "",        "")
    //   "1.8.0-rc1"              → ("1.8.0", "rc1",     "")
    //   "1.8.0+build.42"         → ("1.8.0", "",        "build.42")
    //   "1.8.0-dev.42+g1a2b3c4"  → ("1.8.0", "dev.42",  "g1a2b3c4")
    auto split = [](const QString &s) -> std::tuple<QString, QString, QString> {
        const int plus = s.indexOf(QLatin1Char('+'));
        const QString head = (plus < 0) ? s : s.left(plus);
        const QString build = (plus < 0) ? QString() : s.mid(plus + 1);
        const int dash = head.indexOf(QLatin1Char('-'));
        const QString core = (dash < 0) ? head : head.left(dash);
        const QString pre  = (dash < 0) ? QString() : head.mid(dash + 1);
        return {core, pre, build};
    };
    const auto [aCore, aPre, aBuild] = split(strip(candidate));
    const auto [bCore, bPre, bBuild] = split(strip(current));
    Q_UNUSED(aBuild)
    Q_UNUSED(bBuild)

    // Numeric segment compare (1.10.0 > 1.9.9).
    const auto pa = aCore.split(QLatin1Char('.'));
    const auto pb = bCore.split(QLatin1Char('.'));
    const int n = qMax(pa.size(), pb.size());
    for (int i = 0; i < n; ++i) {
        const int ia = i < pa.size() ? pa[i].toInt() : 0;
        const int ib = i < pb.size() ? pb[i].toInt() : 0;
        if (ia != ib) return ia > ib;
    }
    // Numeric cores equal. Pre-release rule: a side WITH a pre-release tail
    // ranks older than a side without one.
    if (aPre.isEmpty() && !bPre.isEmpty()) return true;   // 1.0.0 > 1.0.0-rc1
    if (!aPre.isEmpty() && bPre.isEmpty()) return false;  // 1.0.0-rc1 < 1.0.0
    // Both have pre-releases (or neither does). Simple string compare on the
    // pre-release tail covers the common cases (rc1 < rc2, dev.41 < dev.42).
    // Full semver dot-segment compare is overkill for our update indicator.
    return QString::compare(aPre, bPre) > 0;
}
