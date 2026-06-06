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
 * Polls the AppGrid website's static `latest.json` to flag updates.
 * Notify-only; click opens the release page. Opt-in via settings.
 *
 * Only compiled when APPGRID_UNIVERSAL_BUILD is set — distro packages
 * leave update handling to their package manager.
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

    [[nodiscard]] bool hasUpdate() const
    {
        return m_hasUpdate;
    }
    [[nodiscard]] QString latestVersion() const
    {
        return m_latestVersion;
    }
    [[nodiscard]] QString releaseUrl() const
    {
        return m_releaseUrl;
    }
    [[nodiscard]] bool enabled() const
    {
        return m_enabled;
    }
    void setEnabled(bool enable);

    Q_INVOKABLE void checkNow();
    Q_INVOKABLE void openReleasePage();

    // Pure helpers — public for unit testing.
    [[nodiscard]] static bool isNewer(const QString &candidate, const QString &current);
    [[nodiscard]] static bool isAllowedReleaseScheme(const class QUrl &url);
    [[nodiscard]] static bool isValidVersionString(const QString &v);

    // Decoded latest.json. `valid` is true when the JSON parsed and the
    // mandatory stable version cleared validation; the prerelease pair
    // is optional and may be empty even on a valid result.
    struct ManifestResult {
        bool valid = false;
        QString stableVersion;
        QString stableUrl;
        QString prereleaseVersion;
        QString prereleaseUrl;
    };
    [[nodiscard]] static ManifestResult parseManifest(const QByteArray &bytes);

    // The release to surface for a given installed version.
    struct ChosenRelease {
        QString version;
        QString url;
    };
    // Channel selection: stable users (no "-" in their version) only ever see
    // the stable release; pre-release users see the prerelease when it is newer
    // than stable, else stable. Pure — depends only on the inputs.
    [[nodiscard]] static ChosenRelease chooseRelease(const QString &currentVersion, const ManifestResult &manifest);

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
    QString m_etag;
    bool m_hasUpdate = false;
    bool m_enabled = false;
    // ETag rotates every kEtagResetEvery saves to prevent long-term tracking.
    int m_etagAge = 0;
    // Parent-owned, torn down + rebuilt each check (TLS session ticket reset).
    QNetworkAccessManager *m_network = nullptr;
    // Re-entrancy guard: rapid runCheck() calls (config toggle + periodic
    // timer firing close together) would otherwise tear down the QNAM while
    // a reply is still parented to it, dropping the in-flight check silently.
    bool m_replyInFlight = false;
    QTimer m_periodicTimer;
};
