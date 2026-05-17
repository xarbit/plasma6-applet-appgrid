/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QDateTime>
#include <QObject>
#include <QTimer>

class QNetworkAccessManager;

/**
 * Polls the AppGrid website's static `latest.json` to decide whether an
 * update is available. Notify-only — never installs anything, the user
 * clicks the indicator to open the release page in a browser.
 *
 * Only compiled when APPGRID_UNIVERSAL_BUILD is set. Distros that ship
 * AppGrid via their package manager don't include this class — their
 * package manager already handles updates.
 *
 * Privacy posture: opt-in (settings checkbox), throttled to one request
 * per 24 hours, anonymous GET with an If-None-Match header so unchanged
 * responses cost zero bandwidth beyond the request line.
 */
class UpdateChecker : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool hasUpdate READ hasUpdate NOTIFY hasUpdateChanged)
    Q_PROPERTY(QString latestVersion READ latestVersion NOTIFY latestVersionChanged)
    Q_PROPERTY(QString releaseUrl READ releaseUrl NOTIFY releaseUrlChanged)
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)

public:
    explicit UpdateChecker(const QString &currentVersion, QObject *parent = nullptr);
    ~UpdateChecker() override;

    bool hasUpdate() const { return m_hasUpdate; }
    QString latestVersion() const { return m_latestVersion; }
    QString releaseUrl() const { return m_releaseUrl; }
    bool enabled() const { return m_enabled; }
    void setEnabled(bool enabled);

    /** Force a check now, ignoring the 24-hour throttle. */
    Q_INVOKABLE void checkNow();

    /** Open the release page in the user's default browser. */
    Q_INVOKABLE void openReleasePage();

    // --- Pure helpers, exposed for unit testing ---

    /// True if `candidate` is strictly newer than `current` (semver-ish).
    static bool isNewer(const QString &candidate, const QString &current);

    /// True if the URL is non-empty, well-formed, and uses http or https.
    /// Used on both network input and cache load to keep the release URL
    /// from being weaponized into a non-web scheme (file://, javascript:, …).
    static bool isAllowedReleaseScheme(const class QUrl &url);

    /// True if `v` looks like a sane version string: optional leading 'v',
    /// numeric dotted segments (up to 4), optional pre-release / build tail.
    static bool isValidVersionString(const QString &v);

Q_SIGNALS:
    void hasUpdateChanged();
    void latestVersionChanged();
    void releaseUrlChanged();
    void enabledChanged();

private:
    void runCheck(bool force);
    void handleReply(class QNetworkReply *reply);
    void loadState();
    void saveState();

    QString m_currentVersion;
    QString m_latestVersion;
    QString m_releaseUrl;
    QDateTime m_lastCheck;
    QString m_etag;          // for If-None-Match caching
    bool m_hasUpdate = false;
    bool m_enabled = false;
    // Anonymity hygiene: count saves so we can drop the ETag periodically.
    // ETag is a stable per-release server identifier; never rotating it
    // would turn it into a long-term user identifier across IP changes.
    int m_etagAge = 0;
    // Parent-owned (we pass `this` as parent on construction), so plain
    // pointer is enough — lifetime ends with the UpdateChecker. We tear it
    // down + rebuild on every check so TLS session tickets can't fingerprint
    // us across runs.
    QNetworkAccessManager *m_network = nullptr;
    // Periodic re-check while enabled — fires every ~24h (with jitter) so
    // long-running sessions still pick up new releases. Stopped on
    // setEnabled(false), restarted on setEnabled(true).
    QTimer m_periodicTimer;
};
