/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for FavoriteId::normalized — the rule that decides under which id a
    favourite is stored (#64). The crux: a jump-list action id is kept verbatim
    (so the action persists, unlike Kicker which drops it), while a plain app id
    is canonicalised to "applications:<menuId>". The menu-id lookup is injected,
    so this is pure — no KService, no KActivities.
*/

#include "favoriteid.h"

#include <QTest>

class TestFavoriteId : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    // A resolver that must never be consulted for action ids — asserts the
    // action branch returns before touching it.
    void actionIdKeptVerbatim()
    {
        const auto resolver = [](const QString &) -> QString {
            return QStringLiteral("should.not.be.used.desktop");
        };
        const QString id = QStringLiteral("applications:org.kde.spectacle.desktop?action=RecordScreen");
        QCOMPARE(FavoriteId::normalized(id, resolver), id);
    }

    void bareActionIdKeptVerbatim()
    {
        const auto resolver = [](const QString &) {
            return QStringLiteral("org.kde.spectacle.desktop");
        };
        const QString id = QStringLiteral("org.kde.spectacle.desktop?action=RecordScreen");
        QCOMPARE(FavoriteId::normalized(id, resolver), id);
    }

    // A plain app is canonicalised to applications:<menuId>, whatever id form
    // came in (a .desktop path here).
    void plainAppCanonicalised()
    {
        QString seen;
        const auto resolver = [&seen](const QString &storageId) -> QString {
            seen = storageId;
            return QStringLiteral("org.kde.dolphin.desktop");
        };
        const QString result = FavoriteId::normalized(QStringLiteral("/usr/share/applications/org.kde.dolphin.desktop"), resolver);
        QCOMPARE(seen, QStringLiteral("/usr/share/applications/org.kde.dolphin.desktop"));
        QCOMPARE(result, QStringLiteral("applications:org.kde.dolphin.desktop"));
    }

    void alreadyPrefixedPlainAppIsStable()
    {
        const auto resolver = [](const QString &) {
            return QStringLiteral("org.kde.dolphin.desktop");
        };
        const QString id = QStringLiteral("applications:org.kde.dolphin.desktop");
        QCOMPARE(FavoriteId::normalized(id, resolver), id);
    }

    // An unresolvable plain id (resolver returns empty) is left as-is rather
    // than being rewritten to "applications:".
    void unresolvedPlainIdUntouched()
    {
        const auto resolver = [](const QString &) {
            return QString();
        };
        const QString id = QStringLiteral("preferred://browser");
        QCOMPARE(FavoriteId::normalized(id, resolver), id);
    }

    void emptyId()
    {
        const auto resolver = [](const QString &) {
            return QStringLiteral("x.desktop");
        };
        QVERIFY(FavoriteId::normalized(QString(), resolver).isEmpty());
    }

    void classifiesDocuments_data()
    {
        QTest::addColumn<QString>("id");
        QTest::addColumn<bool>("isDocument");

        QTest::newRow("plain app") << QStringLiteral("org.kde.dolphin.desktop") << false;
        QTest::newRow("prefixed app") << QStringLiteral("applications:org.kde.dolphin.desktop") << false;
        QTest::newRow("app action") << QStringLiteral("applications:org.kde.spectacle.desktop?action=RecordScreen") << false;
        QTest::newRow("preferred") << QStringLiteral("preferred://browser") << false;
        QTest::newRow("file url") << QStringLiteral("file:///home/u/pic.png") << true;
        QTest::newRow("local path") << QStringLiteral("/home/u/pic.png") << true;
        QTest::newRow("remote url") << QStringLiteral("smb://host/share/x.txt") << true;
        QTest::newRow("empty") << QString() << false;
    }

    void classifiesDocuments()
    {
        QFETCH(QString, id);
        QFETCH(bool, isDocument);
        QCOMPARE(FavoriteId::isDocument(id), isDocument);
    }

    // An app favourited by an older version can be stored bare and prefixed at
    // once; both are the same favourite, so removing it must find both.
    void variantsOfFindsLegacyAndPrefixedEntries()
    {
        const auto resolver = [](const QString &storageId) -> QString {
            return storageId.endsWith(QLatin1String(".desktop")) ? storageId : QString();
        };
        const auto normalize = [&](const QString &id) {
            return FavoriteId::normalized(id, resolver);
        };
        const QStringList stored{
            QStringLiteral("claude-desktop.desktop"),
            QStringLiteral("applications:claude-desktop.desktop"),
            QStringLiteral("applications:org.kde.kate.desktop"),
            QStringLiteral("applications:claude-desktop.desktop?action=new-window"),
            QStringLiteral("/home/user/notes.pdf"),
        };
        const QStringList both{QStringLiteral("claude-desktop.desktop"), QStringLiteral("applications:claude-desktop.desktop")};
        // Found from either spelling of the id.
        QCOMPARE(FavoriteId::variantsOf(stored, QStringLiteral("claude-desktop.desktop"), normalize), both);
        QCOMPARE(FavoriteId::variantsOf(stored, QStringLiteral("applications:claude-desktop.desktop"), normalize), both);
        // A jump-list action is its own favourite.
        QCOMPARE(FavoriteId::variantsOf(stored, QStringLiteral("applications:claude-desktop.desktop?action=new-window"), normalize),
                 QStringList{QStringLiteral("applications:claude-desktop.desktop?action=new-window")});
        // Unrelated and unknown ids.
        QCOMPARE(FavoriteId::variantsOf(stored, QStringLiteral("org.kde.kate.desktop"), normalize),
                 QStringList{QStringLiteral("applications:org.kde.kate.desktop")});
        QVERIFY(FavoriteId::variantsOf(stored, QStringLiteral("gone.desktop"), normalize).isEmpty());
        QVERIFY(FavoriteId::variantsOf(stored, QString(), normalize).isEmpty());
    }
};

QTEST_MAIN(TestFavoriteId)
#include "test_favoriteid.moc"
