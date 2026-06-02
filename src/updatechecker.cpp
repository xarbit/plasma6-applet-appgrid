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

namespace
{
// Static JSON manifest, served from GitHub Pages — no GitHub API rate
// limit. Updated automatically by the website on each AppGrid release.
constexpr auto kManifestUrl = QLatin1StringView("https://appgrid.xarbit.dev/api/latest.json");

// Jitter the cadence so the endpoint can't fingerprint users by always
// seeing the same wall-clock minute every day.
constexpr int kPeriodicCheckMs = 24 * 60 * 60 * 1000;
constexpr int kJitterCheckMs = 2 * 60 * 60 * 1000;

// Rotate the saved ETag every N saves so it can't act as a long-term
// per-user identifier across IP rotations.
constexpr int kEtagResetEvery = 7;

constexpr qint64 kMaxResponseBytes = qint64{16} * 1024;
constexpr int kRequestTimeoutMs = 10 * 1000;

// AppGrid ships two plasmoid variants (center + panel); both run in
// plasmashell + write the same cache. If either wrote it within this
// window, skip the network and reload from disk so startup double-fire
// collapses to one request.
constexpr qint64 kFreshenWindowMs = qint64{60} * 1000;

// Bump whenever the parsing logic changes in a way that older cached
// state could cause the new code to miss data on the next 304 short-circuit
// (e.g. when a new field starts contributing to m_latestVersion). loadState
// discards a cached ETag from any older schema → next periodic check is a
// full 200 + re-parse, so the new logic can populate its fields.
//
// Schema log:
//   1 — original (pre-1.8.0; not written into the cache, so missing/0 ⇒ 1)
//   2 — 1.8.0+ : handleReply also reads "prerelease" block
constexpr int kCacheSchema = 2;

class NoCookieJar : public QNetworkCookieJar
{
public:
    using QNetworkCookieJar::QNetworkCookieJar;
    bool setCookiesFromUrl(const QList<QNetworkCookie> &, const QUrl &) override
    {
        return false;
    }
    QList<QNetworkCookie> cookiesForUrl(const QUrl &) const override
    {
        return {};
    }
};

} // namespace

// http / https only — treat the release URL as untrusted on every code
// path so a compromised endpoint can never dispatch QDesktopServices into
// file://, mailto:, javascript:, etc.
bool UpdateChecker::isAllowedReleaseScheme(const QUrl &url)
{
    if (!url.isValid() || url.host().isEmpty())
        return false;
    const QString scheme = url.scheme().toLower();
    return scheme == QLatin1String("http") || scheme == QLatin1String("https");
}

// Semver-ish: optional v prefix, 1-4 numeric segments, optional
// `-prerelease` and `+build` tails. Accepts "1.8.0-dev.42+g1a2b3c4".
bool UpdateChecker::isValidVersionString(const QString &v)
{
    if (v.isEmpty() || v.size() > 64)
        return false;
    static const QRegularExpression re(QStringLiteral("^v?\\d+(\\.\\d+){0,3}(-[0-9A-Za-z.\\-]+)?(\\+[0-9A-Za-z.\\-]+)?$"));
    return re.match(v).hasMatch();
}

// Both plasmoid variants (center + panel) share this one cache file —
// a check by either satisfies both via runCheck()'s freshen window.
static QString stateFilePath()
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    return dir + QStringLiteral("/dev.xarbit.appgrid.update-checker.json");
}

static int nextPeriodicInterval()
{
    const int jitter = QRandomGenerator::global()->bounded(-kJitterCheckMs, kJitterCheckMs + 1);
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
        if (m_enabled)
            m_periodicTimer.start(nextPeriodicInterval());
    });
}

UpdateChecker::~UpdateChecker() = default;

void UpdateChecker::setEnabled(bool enabled)
{
    if (m_enabled == enabled)
        return;
    m_enabled = enabled;
    Q_EMIT enabledChanged();
    if (enabled) {
        runCheck(/*force=*/true);
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
        qWarning("AppGrid update check: refusing release URL with scheme %s", qPrintable(url.scheme()));
        return;
    }
    QDesktopServices::openUrl(url);
}

void UpdateChecker::runCheck(bool force)
{
    if (!force && !m_enabled)
        return;
    // Already checking — let the in-flight reply finish before rebuilding
    // the QNAM. Avoids parenting a fresh request to a QNAM that's about to
    // delete a still-pending reply.
    if (m_replyInFlight)
        return;

    // Sibling-plasmoid de-dup: cache freshly written by the other variant
    // means we can just reload + emit instead of hitting the network.
    const QFileInfo cache(stateFilePath());
    if (cache.exists()) {
        const qint64 ageMs = cache.lastModified().msecsTo(QDateTime::currentDateTime());
        if (ageMs >= 0 && ageMs < kFreshenWindowMs) {
            const bool wasAvailable = m_hasUpdate;
            const QString prevVersion = m_latestVersion;
            const QString prevUrl = m_releaseUrl;
            loadState();
            if (m_latestVersion != prevVersion)
                Q_EMIT latestVersionChanged();
            if (m_releaseUrl != prevUrl)
                Q_EMIT releaseUrlChanged();
            if (m_hasUpdate != wasAvailable)
                Q_EMIT hasUpdateChanged();
            return;
        }
    }

    // Rebuild the QNAM each check so TLS session tickets don't act as a
    // cross-session/cross-IP fingerprint. One handshake per ~24h is invisible.
    if (m_network) {
        m_network->deleteLater();
        m_network = nullptr;
    }
    m_network = new QNetworkAccessManager(this);
    m_network->setCookieJar(new NoCookieJar(m_network));
    // Hostile proxy would otherwise pop a system password prompt.
    connect(m_network, &QNetworkAccessManager::proxyAuthenticationRequired, this, [](const QNetworkProxy &, QAuthenticator *) { });

    QNetworkRequest req{QUrl(kManifestUrl)};
    // Minimal headers: no version-in-UA, no language leak, hint that
    // intermediaries shouldn't cache, no socket reuse across checks.
    req.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("AppGrid"));
    req.setRawHeader("Accept-Language", QByteArray());
    req.setRawHeader("Cache-Control", "no-store");
    req.setRawHeader("Connection", "close");

    if (!force && !m_etag.isEmpty())
        req.setRawHeader("If-None-Match", m_etag.toUtf8());

    req.setTransferTimeout(kRequestTimeoutMs);

    // No redirects: endpoint is hardcoded HTTPS to a domain we own. Any 3xx
    // is either misconfig or a downgrade attempt; handleReply rejects it.
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::ManualRedirectPolicy);

    QSslConfiguration tls = QSslConfiguration::defaultConfiguration();
    tls.setProtocol(QSsl::TlsV1_2OrLater);
    req.setSslConfiguration(tls);

    QNetworkReply *reply = m_network->get(req);
    m_replyInFlight = true;
    // Size cap: catch over-large Content-Length up front AND a server that
    // streams more than it advertised.
    connect(reply, &QNetworkReply::metaDataChanged, this, [reply]() {
        const auto cl = reply->header(QNetworkRequest::ContentLengthHeader);
        if (cl.isValid() && cl.toLongLong() > kMaxResponseBytes) {
            qWarning("AppGrid update check: Content-Length %lld exceeds cap, aborting", cl.toLongLong());
            reply->abort();
        }
    });
    connect(reply, &QNetworkReply::downloadProgress, this, [reply](qint64 bytesReceived, qint64 /*bytesTotal*/) {
        if (bytesReceived > kMaxResponseBytes) {
            qWarning("AppGrid update check: response exceeded %lld bytes, aborting", static_cast<long long>(kMaxResponseBytes));
            reply->abort();
        }
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        handleReply(reply);
        m_replyInFlight = false;
    });
}

UpdateChecker::ManifestResult UpdateChecker::parseManifest(const QByteArray &bytes)
{
    ManifestResult result;

    QJsonParseError err{};
    const auto doc = QJsonDocument::fromJson(bytes, &err);
    if (err.error != QJsonParseError::NoError || !doc.isObject()) {
        qWarning("AppGrid update check: malformed JSON");
        return result;
    }

    const auto obj = doc.object();

    // Top-level "version" / "release_notes_url" fields are the stable
    // release (legacy + back-compat target for AppGrid <= 1.8.0-rc.1).
    const auto stableVersion = obj.value(QStringLiteral("version")).toString();
    const auto stableUrl = obj.value(QStringLiteral("release_notes_url")).toString();

    if (!isValidVersionString(stableVersion)) {
        qWarning("AppGrid update check: rejecting malformed version string");
        return result;
    }
    if (!stableUrl.isEmpty() && !isAllowedReleaseScheme(QUrl(stableUrl))) {
        qWarning("AppGrid update check: rejecting release URL with disallowed scheme");
        return result;
    }

    result.stableVersion = stableVersion;
    result.stableUrl = stableUrl;

    // Optional "prerelease" block carries the latest -rc / -beta / -alpha
    // (added in 1.8.0). Pre-release fields are optional; either piece may
    // be cleared independently if validation fails so the stable side of
    // the result still surfaces.
    const auto prereleaseValue = obj.value(QStringLiteral("prerelease"));
    if (prereleaseValue.isObject()) {
        const auto pre = prereleaseValue.toObject();
        QString preVersion = pre.value(QStringLiteral("version")).toString();
        QString preUrl = pre.value(QStringLiteral("release_notes_url")).toString();
        if (!preVersion.isEmpty() && !isValidVersionString(preVersion)) {
            qWarning("AppGrid update check: rejecting malformed prerelease version");
            preVersion.clear();
            preUrl.clear();
        }
        if (!preUrl.isEmpty() && !isAllowedReleaseScheme(QUrl(preUrl))) {
            qWarning("AppGrid update check: rejecting prerelease URL with disallowed scheme");
            preVersion.clear();
            preUrl.clear();
        }
        result.prereleaseVersion = preVersion;
        result.prereleaseUrl = preUrl;
    }

    result.valid = true;
    return result;
}

void UpdateChecker::handleReply(QNetworkReply *reply)
{
    reply->deleteLater();
    m_lastCheck = QDateTime::currentDateTimeUtc();

    // Capture ETag even on errors — server may have set one.
    const QByteArray etag = reply->rawHeader("ETag");
    if (!etag.isEmpty())
        m_etag = QString::fromLatin1(etag);

    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();

    if (status == 304) {
        saveState();
        return;
    }

    if (reply->error() != QNetworkReply::NoError || status != 200) {
        qWarning("AppGrid update check: %s (HTTP %d)", qPrintable(reply->errorString()), status);
        saveState();
        return;
    }

    const auto manifest = parseManifest(reply->readAll());
    if (!manifest.valid) {
        saveState();
        return;
    }

    // Pick which advertised version to surface to the user:
    //   - stable users (no "-" in current version) only see stable
    //   - pre-release users (e.g. "1.8.0-rc.1") see the higher of stable
    //     or prerelease; either path is a legit upgrade for them
    const bool currentIsPrerelease = m_currentVersion.contains(QChar(u'-'));
    QString chosenVersion = manifest.stableVersion;
    QString chosenUrl = manifest.stableUrl;
    if (currentIsPrerelease && !manifest.prereleaseVersion.isEmpty() && isNewer(manifest.prereleaseVersion, manifest.stableVersion)) {
        chosenVersion = manifest.prereleaseVersion;
        chosenUrl = manifest.prereleaseUrl;
    }

    const bool wasAvailable = m_hasUpdate;
    const QString prevVersion = m_latestVersion;
    const QString prevUrl = m_releaseUrl;

    m_latestVersion = chosenVersion;
    m_releaseUrl = chosenUrl;
    m_hasUpdate = isNewer(chosenVersion, m_currentVersion);

    if (m_latestVersion != prevVersion)
        Q_EMIT latestVersionChanged();
    if (m_releaseUrl != prevUrl)
        Q_EMIT releaseUrlChanged();
    if (m_hasUpdate != wasAvailable)
        Q_EMIT hasUpdateChanged();

    saveState();
}

void UpdateChecker::loadState()
{
    QFile f(stateFilePath());
    if (!f.open(QIODevice::ReadOnly))
        return;
    // Treat the cache as untrusted — could have been tampered with.
    const auto bytes = f.read(kMaxResponseBytes);
    const auto doc = QJsonDocument::fromJson(bytes);
    if (!doc.isObject())
        return;
    const auto obj = doc.object();

    const QString version = obj.value(QStringLiteral("latestVersion")).toString();
    if (isValidVersionString(version))
        m_latestVersion = version;

    const QString rel = obj.value(QStringLiteral("releaseUrl")).toString();
    if (!rel.isEmpty() && isAllowedReleaseScheme(QUrl(rel)))
        m_releaseUrl = rel;

    // Schema-aware ETag load: a cache from an older parser version may
    // not have populated all current fields. Holding onto that ETag would
    // make the server keep responding 304 → handleReply skips re-parse →
    // new fields stay empty forever. Drop the ETag so the next check is a
    // full fetch + fresh parse under the current schema.
    const int cachedSchema = obj.value(QStringLiteral("schema")).toInt();
    if (cachedSchema < kCacheSchema) {
        m_etag.clear();
        m_etagAge = 0;
    } else {
        m_etag = obj.value(QStringLiteral("etag")).toString();
        const int etagAge = obj.value(QStringLiteral("etagAge")).toInt();
        if (etagAge >= 0 && etagAge < kEtagResetEvery)
            m_etagAge = etagAge;
    }

    // Reject future lastCheck — clock skew or tampering. Otherwise the
    // periodic timer could be tricked into believing we already checked.
    const auto lc = QDateTime::fromString(obj.value(QStringLiteral("lastCheck")).toString(), Qt::ISODate);
    if (lc.isValid() && lc <= QDateTime::currentDateTimeUtc().addDays(1))
        m_lastCheck = lc;

    m_hasUpdate = !m_latestVersion.isEmpty() && isNewer(m_latestVersion, m_currentVersion);
}

void UpdateChecker::saveState()
{
    if (++m_etagAge >= kEtagResetEvery) {
        m_etag.clear();
        m_etagAge = 0;
    }

    const QString finalPath = stateFilePath();
    const QString tmpPath = finalPath + QStringLiteral(".tmp");

    QFile f(tmpPath);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        QDir().mkpath(QFileInfo(f).absolutePath());
        if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
            return;
    }
    QJsonObject obj{
        {QStringLiteral("schema"), kCacheSchema},
        {QStringLiteral("latestVersion"), m_latestVersion},
        {QStringLiteral("releaseUrl"), m_releaseUrl},
        {QStringLiteral("etag"), m_etag},
        {QStringLiteral("lastCheck"), m_lastCheck.toString(Qt::ISODate)},
        {QStringLiteral("etagAge"), m_etagAge},
    };
    f.write(QJsonDocument(obj).toJson(QJsonDocument::Compact));
    f.close();
    f.setPermissions(QFile::ReadOwner | QFile::WriteOwner);

    // Atomic replace so a reader never sees a half-written file when both
    // plasmoid variants race a save.
    QFile::remove(finalPath);
    if (!QFile::rename(tmpPath, finalPath))
        QFile::remove(tmpPath);
}

bool UpdateChecker::isNewer(const QString &candidate, const QString &current)
{
    auto strip = [](const QString &s) {
        return s.startsWith(QLatin1Char('v')) ? s.mid(1) : s;
    };
    // Split into <core>, <pre-release>, <build>. Per semver, build is
    // ignored for ordering and pre-release ranks below the matching core.
    auto split = [](const QString &s) -> std::tuple<QString, QString, QString> {
        const int plus = s.indexOf(QLatin1Char('+'));
        const QString head = (plus < 0) ? s : s.left(plus);
        const QString build = (plus < 0) ? QString() : s.mid(plus + 1);
        const int dash = head.indexOf(QLatin1Char('-'));
        const QString core = (dash < 0) ? head : head.left(dash);
        const QString pre = (dash < 0) ? QString() : head.mid(dash + 1);
        return {core, pre, build};
    };
    const auto [aCore, aPre, aBuild] = split(strip(candidate));
    const auto [bCore, bPre, bBuild] = split(strip(current));
    Q_UNUSED(aBuild)
    Q_UNUSED(bBuild)

    const auto pa = aCore.split(QLatin1Char('.'));
    const auto pb = bCore.split(QLatin1Char('.'));
    const int n = qMax(pa.size(), pb.size());
    for (int i = 0; i < n; ++i) {
        const int ia = i < pa.size() ? pa[i].toInt() : 0;
        const int ib = i < pb.size() ? pb[i].toInt() : 0;
        if (ia != ib)
            return ia > ib;
    }
    if (aPre.isEmpty() && !bPre.isEmpty())
        return true;
    if (!aPre.isEmpty() && bPre.isEmpty())
        return false;
    return QString::compare(aPre, bPre) > 0;
}
