/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "updatechecker.h"

#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QSysInfo>
#include <QTimer>
#include <QUrl>

namespace {
// Static JSON endpoint on the AppGrid website. Served from GitHub Pages CDN
// so there are no GitHub API rate-limit concerns. Updated automatically by
// the website's build pipeline on each AppGrid release (repository_dispatch).
// QLatin1StringView keeps this a compile-time literal with no runtime alloc.
constexpr auto kManifestUrl = QLatin1StringView(
    "https://appgrid.xarbit.dev/api/latest.json");

// Throttle: at most one network request per 24h, even if the user opens the
// grid dozens of times. Forced checks (checkNow) bypass.
constexpr qint64 kThrottleSeconds = 24 * 60 * 60;

// Delay before the first network request after the checker is enabled.
// We want the plasmoid to be up + responsive before any background work
// fires; 30 s is past the typical Plasma startup spike and beyond the
// user's immediate-after-login click window.
constexpr int kInitialDelayMs = 30 * 1000;
} // namespace

// On-disk state lives in the per-user cache dir so it never bloats config.
static QString stateFilePath()
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    return dir + QStringLiteral("/update-checker.json");
}

UpdateChecker::UpdateChecker(const QString &currentVersion, QObject *parent)
    : QObject(parent)
    , m_currentVersion(currentVersion)
{
    loadState();
    // We don't auto-fire on construction — the QML side flips `enabled`
    // when the config is on, and that triggers the first check via
    // scheduleCheckIfDue().
}

UpdateChecker::~UpdateChecker() = default;

void UpdateChecker::setEnabled(bool enabled)
{
    if (m_enabled == enabled)
        return;
    m_enabled = enabled;
    emit enabledChanged();
    if (enabled)
        scheduleCheckIfDue();
}

void UpdateChecker::checkNow()
{
    runCheck(/*force=*/true);
}

void UpdateChecker::openReleasePage()
{
    if (!m_releaseUrl.isEmpty())
        QDesktopServices::openUrl(QUrl(m_releaseUrl));
}

void UpdateChecker::scheduleCheckIfDue()
{
    if (!m_enabled)
        return;
    if (m_lastCheck.isValid()
            && m_lastCheck.secsTo(QDateTime::currentDateTimeUtc()) < kThrottleSeconds) {
        return; // honor the 24h throttle
    }
    // Defer the network request so we never compete with plasmoid load /
    // first-paint. Fires once, asynchronously; the reply itself is handled
    // off the UI thread by QNetworkAccessManager so nothing blocks.
    QTimer::singleShot(kInitialDelayMs, this, [this]() {
        runCheck(/*force=*/false);
    });
}

void UpdateChecker::runCheck(bool force)
{
    if (!force && !m_enabled)
        return;

    if (!m_network)
        m_network = new QNetworkAccessManager(this);

    QNetworkRequest req{QUrl(kManifestUrl)};
    req.setHeader(QNetworkRequest::UserAgentHeader,
                  QStringLiteral("AppGrid/%1 (universal)").arg(m_currentVersion));
    // ETag caching keeps unchanged responses to a 304 with no body. Saves
    // bandwidth on the CDN side and on the user's connection.
    if (!m_etag.isEmpty())
        req.setRawHeader("If-None-Match", m_etag.toUtf8());

    QNetworkReply *reply = m_network->get(req);
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

    if (version.isEmpty()) {
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
    const auto doc = QJsonDocument::fromJson(f.readAll());
    if (!doc.isObject())
        return;
    const auto obj = doc.object();
    m_latestVersion = obj.value(QStringLiteral("latestVersion")).toString();
    m_releaseUrl    = obj.value(QStringLiteral("releaseUrl")).toString();
    m_etag          = obj.value(QStringLiteral("etag")).toString();
    m_lastCheck     = QDateTime::fromString(
        obj.value(QStringLiteral("lastCheck")).toString(), Qt::ISODate);
    m_hasUpdate     = !m_latestVersion.isEmpty()
        && isNewer(m_latestVersion, m_currentVersion);
}

void UpdateChecker::saveState()
{
    QFile f(stateFilePath());
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
    };
    f.write(QJsonDocument(obj).toJson(QJsonDocument::Compact));
}

bool UpdateChecker::isNewer(const QString &candidate, const QString &current)
{
    // Strip a leading 'v' if present (release tags: v1.8.1 vs 1.8.1).
    auto strip = [](const QString &s) {
        return s.startsWith(QLatin1Char('v')) ? s.mid(1) : s;
    };
    const auto a = strip(candidate);
    const auto b = strip(current);

    // Numeric segment compare (1.10.0 > 1.9.9). Non-numeric parts compared as
    // strings, which is enough for stable + simple pre-release strings; if we
    // ever ship complex pre-releases we'll need a proper semver parser.
    const auto pa = a.split(QRegularExpression(QStringLiteral("[.\\-+]")));
    const auto pb = b.split(QRegularExpression(QStringLiteral("[.\\-+]")));
    const int n = qMax(pa.size(), pb.size());
    for (int i = 0; i < n; ++i) {
        const auto sa = i < pa.size() ? pa[i] : QStringLiteral("0");
        const auto sb = i < pb.size() ? pb[i] : QStringLiteral("0");
        bool na = false, nb = false;
        const int ia = sa.toInt(&na);
        const int ib = sb.toInt(&nb);
        if (na && nb) {
            if (ia != ib) return ia > ib;
        } else {
            const int cmp = QString::compare(sa, sb);
            if (cmp != 0) return cmp > 0;
        }
    }
    return false; // equal
}
