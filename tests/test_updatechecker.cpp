/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Unit tests for UpdateChecker. Pure-logic only — version comparison,
    input validation, cache round-trip, on-disk hardening. No network,
    no QML, no plasmashell process.
*/

#include "updatechecker.h"

#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTest>
#include <QUrl>

class TestUpdateChecker : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase()
    {
        // Sandbox QStandardPaths so cache lands in a throwaway dir, not
        // ~/.cache/<actual-app>. Tests must not touch the real user state.
        QStandardPaths::setTestModeEnabled(true);
    }

    void cleanup()
    {
        // Each test starts with no cache file.
        QFile::remove(stateFile());
    }

    // --- isNewer ---------------------------------------------------------

    void isNewer_data()
    {
        QTest::addColumn<QString>("candidate");
        QTest::addColumn<QString>("current");
        QTest::addColumn<bool>("expected");

        QTest::newRow("strict newer")          << "1.9.0" << "1.8.0" << true;
        QTest::newRow("equal")                 << "1.8.0" << "1.8.0" << false;
        QTest::newRow("older")                 << "1.7.9" << "1.8.0" << false;
        QTest::newRow("numeric ordering")      << "1.10.0" << "1.9.9" << true;
        QTest::newRow("v prefix on candidate") << "v2.0.0" << "1.9.0" << true;
        QTest::newRow("v prefix on current")   << "2.0.0" << "v1.9.0" << true;
        QTest::newRow("v on both")             << "v2.0.0" << "v1.9.0" << true;
        QTest::newRow("patch increment")       << "1.8.1" << "1.8.0" << true;
        QTest::newRow("minor increment")       << "1.9.0" << "1.8.99" << true;
        QTest::newRow("major increment")       << "2.0.0" << "1.99.99" << true;
        QTest::newRow("trailing zero ignored") << "1.8.0" << "1.8" << false;
        QTest::newRow("longer is newer")       << "1.8.0.1" << "1.8.0" << true;
        QTest::newRow("pre-release older")     << "1.8.0-rc1" << "1.8.0" << false;

        // --- Dev-build cases (CMake adds -dev.N+g<sha> when not on a tag) ---
        QTest::newRow("release > dev")
            << "1.8.0" << "1.8.0-dev.42" << true;
        QTest::newRow("release > dev with build")
            << "1.8.0" << "1.8.0-dev.42+g1a2b3c4" << true;
        QTest::newRow("dev higher rev count")
            << "1.8.0-dev.42" << "1.8.0-dev.41" << true;
        QTest::newRow("dev build metadata ignored")
            << "1.8.0-dev.42+gabcdefg" << "1.8.0-dev.42+gzzzzzzz" << false;
        QTest::newRow("build metadata ignored for release")
            << "1.8.0+build.99" << "1.8.0" << false;
        QTest::newRow("build metadata ignored both")
            << "1.8.0+build.99" << "1.8.0+build.1" << false;
        QTest::newRow("rc1 < rc2")
            << "1.8.0-rc2" << "1.8.0-rc1" << true;
        QTest::newRow("git-describe style")
            << "1.8.1" << "1.8.0-5-g1a2b3c4" << true;
    }

    void isNewer()
    {
        QFETCH(QString, candidate);
        QFETCH(QString, current);
        QFETCH(bool, expected);
        QCOMPARE(UpdateChecker::isNewer(candidate, current), expected);
    }

    // --- isAllowedReleaseScheme -----------------------------------------

    void scheme_data()
    {
        QTest::addColumn<QString>("url");
        QTest::addColumn<bool>("allowed");

        QTest::newRow("https")            << "https://example.com/r"        << true;
        QTest::newRow("http")             << "http://example.com/r"         << true;
        QTest::newRow("HTTPS uppercase")  << "HTTPS://example.com/r"        << true;
        QTest::newRow("file scheme")      << "file:///etc/passwd"           << false;
        QTest::newRow("javascript")       << "javascript:alert(1)"          << false;
        QTest::newRow("mailto")           << "mailto:x@example.com"         << false;
        QTest::newRow("data url")         << "data:text/html,<h1>x</h1>"    << false;
        QTest::newRow("ftp")              << "ftp://example.com/r"          << false;
        QTest::newRow("ssh")              << "ssh://example.com/r"          << false;
        QTest::newRow("empty url")        << ""                             << false;
        QTest::newRow("garbage")          << "not a url at all"             << false;
        QTest::newRow("scheme only")      << "https:"                       << false;
    }

    void scheme()
    {
        QFETCH(QString, url);
        QFETCH(bool, allowed);
        QCOMPARE(UpdateChecker::isAllowedReleaseScheme(QUrl(url)), allowed);
    }

    // --- isValidVersionString -------------------------------------------

    void version_data()
    {
        QTest::addColumn<QString>("version");
        QTest::addColumn<bool>("valid");

        QTest::newRow("plain semver")       << "1.8.0"               << true;
        QTest::newRow("with v prefix")      << "v1.8.0"              << true;
        QTest::newRow("two segments")       << "1.8"                 << true;
        QTest::newRow("four segments")      << "1.8.0.1"             << true;
        QTest::newRow("prerelease")         << "1.8.0-rc1"           << true;
        QTest::newRow("build metadata")     << "1.8.0+build.42"      << true;
        QTest::newRow("dotted prerelease")  << "1.8.0-rc.1"          << true;
        QTest::newRow("dev with sha build") << "1.8.0-dev.42+g1a2b3c4" << true;
        QTest::newRow("git-describe style") << "1.8.0-5-g1a2b3c4"    << true;
        QTest::newRow("build metadata only")<< "1.8.0+build.42"      << true;
        QTest::newRow("rc + build")         << "1.8.0-rc1+build.42"  << true;

        QTest::newRow("empty")              << ""                    << false;
        QTest::newRow("garbage")            << "not.a.version"       << false;
        QTest::newRow("trailing junk")      << "1.8.0; rm -rf /"     << false;
        QTest::newRow("format string bait") << "1.8.0%s%n"           << false;
        QTest::newRow("newline injection")  << "1.8.0\nMallory"      << false;
        QTest::newRow("oversize")           << QString(200, QLatin1Char('1')) << false;
        QTest::newRow("five segments")      << "1.2.3.4.5"           << false;
        QTest::newRow("negative")           << "-1.0.0"              << false;
        QTest::newRow("leading dot")        << ".1.0.0"              << false;
        QTest::newRow("double v")           << "vv1.0.0"             << false;
    }

    void version()
    {
        QFETCH(QString, version);
        QFETCH(bool, valid);
        QCOMPARE(UpdateChecker::isValidVersionString(version), valid);
    }

    // --- Cache round-trip + hardening -----------------------------------

    void cacheRoundtrip()
    {
        // Construct a checker, push a known state through saveState by
        // toggling enabled (which kicks runCheck, which writes), then read
        // the file back manually. Avoid networking by using runCheck's
        // file-write side via a constructed-then-saved checker instead.
        {
            UpdateChecker uc(QStringLiteral("1.0.0"));
            // No public setters for cache fields — exercise through the
            // file format directly: write our own JSON, load it, verify
            // it round-trips through validation.
            writeCacheFile(QJsonObject{
                {QStringLiteral("latestVersion"), QStringLiteral("1.8.0")},
                {QStringLiteral("releaseUrl"), QStringLiteral("https://example.com/r")},
                {QStringLiteral("etag"), QStringLiteral("abc")},
                {QStringLiteral("lastCheck"), QStringLiteral("2026-01-01T00:00:00Z")},
                {QStringLiteral("etagAge"), 2},
            });
        }
        // Re-construct so loadState runs against the file we just wrote.
        UpdateChecker uc(QStringLiteral("1.0.0"));
        QCOMPARE(uc.latestVersion(), QStringLiteral("1.8.0"));
        QCOMPARE(uc.releaseUrl(),    QStringLiteral("https://example.com/r"));
        // 1.8.0 > 1.0.0, hasUpdate should be true coming straight from cache.
        QVERIFY(uc.hasUpdate());
    }

    void cacheRejectsFutureTimestamp()
    {
        writeCacheFile(QJsonObject{
            {QStringLiteral("latestVersion"), QStringLiteral("1.8.0")},
            {QStringLiteral("releaseUrl"),    QStringLiteral("https://example.com/r")},
            {QStringLiteral("etag"),          QStringLiteral("abc")},
            // Far future — should be ignored; no way to verify this directly
            // through the API, but the resulting checker should still behave
            // (the load just silently discards the lastCheck field).
            {QStringLiteral("lastCheck"), QStringLiteral("2099-01-01T00:00:00Z")},
        });
        UpdateChecker uc(QStringLiteral("1.0.0"));
        // Version + URL still load; only lastCheck is rejected. The visible
        // effect is that the periodic timer won't be silently skipped on
        // next enable because of a poisoned "we already checked tomorrow".
        QCOMPARE(uc.latestVersion(), QStringLiteral("1.8.0"));
    }

    void cacheRejectsBadScheme()
    {
        writeCacheFile(QJsonObject{
            {QStringLiteral("latestVersion"), QStringLiteral("1.8.0")},
            {QStringLiteral("releaseUrl"),    QStringLiteral("javascript:alert(1)")},
            {QStringLiteral("etag"),          QString()},
            {QStringLiteral("lastCheck"),     QStringLiteral("2026-01-01T00:00:00Z")},
        });
        UpdateChecker uc(QStringLiteral("1.0.0"));
        // Bad URL must NOT survive into m_releaseUrl. The checker should
        // expose an empty string so openReleasePage() has nothing to dispatch.
        QCOMPARE(uc.releaseUrl(), QString());
    }

    void cacheRejectsBadVersion()
    {
        writeCacheFile(QJsonObject{
            {QStringLiteral("latestVersion"), QStringLiteral("1.8.0; rm -rf /")},
            {QStringLiteral("releaseUrl"),    QStringLiteral("https://example.com/r")},
            {QStringLiteral("etag"),          QString()},
            {QStringLiteral("lastCheck"),     QStringLiteral("2026-01-01T00:00:00Z")},
        });
        UpdateChecker uc(QStringLiteral("1.0.0"));
        // Malformed version must not land in state — no update should appear.
        QVERIFY(!uc.hasUpdate());
        QCOMPARE(uc.latestVersion(), QString());
    }

    void cacheRejectsOversizeFile()
    {
        // Pad with whitespace inside a valid-ish JSON envelope until the
        // file is larger than our 16 KiB read cap. loadState should refuse
        // to interpret the truncated tail and bail out cleanly.
        QJsonObject obj{
            {QStringLiteral("latestVersion"), QStringLiteral("1.8.0")},
            {QStringLiteral("releaseUrl"),    QStringLiteral("https://example.com/r")},
            {QStringLiteral("padding"),       QString(20 * 1024, QLatin1Char('x'))},
            {QStringLiteral("lastCheck"),     QStringLiteral("2026-01-01T00:00:00Z")},
        };
        writeCacheFile(obj);
        UpdateChecker uc(QStringLiteral("1.0.0"));
        // The 20 KiB padding pushes the file past the 16 KiB read cap, so
        // loadState's f.read(kMaxResponseBytes) gets a truncated head that
        // can't parse as JSON → nothing is loaded. The cache is rejected
        // outright: no version, no update.
        QVERIFY(!uc.hasUpdate());
        QVERIFY(uc.latestVersion().isEmpty());
    }

    // --- parseManifest (pure JSON → struct) -----------------------------

    void parseManifest_data()
    {
        QTest::addColumn<QByteArray>("json");
        QTest::addColumn<bool>("valid");
        QTest::addColumn<QString>("stableVersion");
        QTest::addColumn<QString>("stableUrl");
        QTest::addColumn<QString>("prereleaseVersion");

        QTest::newRow("stable only")
            << QByteArray("{\"version\":\"1.8.0\",\"release_notes_url\":\"https://example.com/r\"}")
            << true << "1.8.0" << "https://example.com/r" << "";

        QTest::newRow("with prerelease")
            << QByteArray("{\"version\":\"1.8.0\",\"release_notes_url\":\"https://example.com/r\","
                          "\"prerelease\":{\"version\":\"1.9.0-rc.1\","
                          "\"release_notes_url\":\"https://example.com/p\"}}")
            << true << "1.8.0" << "https://example.com/r" << "1.9.0-rc.1";

        QTest::newRow("missing version")
            << QByteArray("{\"release_notes_url\":\"https://example.com/r\"}")
            << false << "" << "" << "";

        QTest::newRow("malformed version")
            << QByteArray("{\"version\":\"1.8.0; rm -rf /\"}")
            << false << "" << "" << "";

        QTest::newRow("bad url scheme")
            << QByteArray("{\"version\":\"1.8.0\",\"release_notes_url\":\"javascript:alert(1)\"}")
            << false << "" << "" << "";

        QTest::newRow("prerelease bad version drops only that side")
            << QByteArray("{\"version\":\"1.8.0\",\"release_notes_url\":\"https://example.com/r\","
                          "\"prerelease\":{\"version\":\"not.a.version\","
                          "\"release_notes_url\":\"https://example.com/p\"}}")
            << true << "1.8.0" << "https://example.com/r" << "";

        QTest::newRow("prerelease bad url drops only that side")
            << QByteArray("{\"version\":\"1.8.0\",\"release_notes_url\":\"https://example.com/r\","
                          "\"prerelease\":{\"version\":\"1.9.0-rc.1\","
                          "\"release_notes_url\":\"javascript:alert(1)\"}}")
            << true << "1.8.0" << "https://example.com/r" << "";

        QTest::newRow("garbage json")
            << QByteArray("not json at all")
            << false << "" << "" << "";

        QTest::newRow("not an object")
            << QByteArray("[1, 2, 3]")
            << false << "" << "" << "";
    }

    void parseManifest()
    {
        QFETCH(QByteArray, json);
        QFETCH(bool, valid);
        QFETCH(QString, stableVersion);
        QFETCH(QString, stableUrl);
        QFETCH(QString, prereleaseVersion);

        const auto result = UpdateChecker::parseManifest(json);
        QCOMPARE(result.valid, valid);
        QCOMPARE(result.stableVersion, stableVersion);
        QCOMPARE(result.stableUrl, stableUrl);
        QCOMPARE(result.prereleaseVersion, prereleaseVersion);
    }

    // --- chooseRelease (channel selection) -------------------------------

    void chooseRelease_data()
    {
        QTest::addColumn<QString>("current");
        QTest::addColumn<QString>("stableV");
        QTest::addColumn<QString>("preV");
        QTest::addColumn<QString>("expectedV");

        QTest::newRow("stable user ignores prerelease")
            << "1.8.0" << "1.8.0" << "1.9.0-rc.1" << "1.8.0";
        QTest::newRow("prerelease user takes newer prerelease")
            << "1.8.0-rc.5" << "1.8.0" << "1.9.0-rc.1" << "1.9.0-rc.1";
        QTest::newRow("prerelease user keeps stable when prerelease older")
            << "1.9.0-rc.1" << "1.9.0" << "1.8.0-rc.1" << "1.9.0";
        QTest::newRow("prerelease user, no prerelease offered")
            << "1.8.0-rc.1" << "1.8.0" << "" << "1.8.0";
    }

    void chooseRelease()
    {
        QFETCH(QString, current);
        QFETCH(QString, stableV);
        QFETCH(QString, preV);
        QFETCH(QString, expectedV);

        UpdateChecker::ManifestResult m;
        m.valid = true;
        m.stableVersion = stableV;
        m.stableUrl = QStringLiteral("https://example.com/stable");
        m.prereleaseVersion = preV;
        m.prereleaseUrl = preV.isEmpty() ? QString() : QStringLiteral("https://example.com/pre");

        const auto chosen = UpdateChecker::chooseRelease(current, m);
        QCOMPARE(chosen.version, expectedV);
        // The URL travels with the chosen version.
        QCOMPARE(chosen.url,
                 expectedV == preV ? QStringLiteral("https://example.com/pre")
                                   : QStringLiteral("https://example.com/stable"));
    }

    // (Removed cacheFilePermissions: saveState() is private and only reachable
    // via the async network reply path, so an offline unit test can't exercise
    // the real permission-tightening — the old test only asserted the perms it
    // set itself. The hardening needs a networked/integration test.)

private:
    static QString stateFile()
    {
        return QStandardPaths::writableLocation(QStandardPaths::CacheLocation)
               + QStringLiteral("/dev.xarbit.appgrid.update-checker.json");
    }

    static void writeCacheFile(const QJsonObject &obj)
    {
        const QString path = stateFile();
        QFileInfo(path).absoluteDir().mkpath(QStringLiteral("."));
        QFile f(path);
        QVERIFY2(f.open(QIODevice::WriteOnly | QIODevice::Truncate),
                 "could not open test cache file for writing");
        f.write(QJsonDocument(obj).toJson(QJsonDocument::Compact));
    }
};

QTEST_MAIN(TestUpdateChecker)
#include "test_updatechecker.moc"
