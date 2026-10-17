/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    AppSearch and AppRowIndex: matching a query against a row's roles, the
    inline completion, and the storage-id / haystack lookups over a model.
*/

#include "approwindex.h"
#include "appsearch.h"
#include "stubappmodel.h"

#include <QTest>

class TestAppSearch : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void queryMatchesFoldedAndSingular()
    {
        const QString hay = QStringLiteral("kate\nadvanced text editor\neditor\nutility\n\nsystem");
        QVERIFY(AppSearch::Query::of(QStringLiteral("KATE")).matches(hay));
        QVERIFY(AppSearch::Query::of(QStringLiteral("editors")).matches(hay));
        QVERIFY(!AppSearch::Query::of(QStringLiteral("browser")).matches(hay));
        QVERIFY(AppSearch::Query::of(QString()).matches(hay));
        QVERIFY(AppSearch::Query::of(QString()).isEmpty());
    }

    void haystackFoldsEverySearchedRole()
    {
        StubAppModel model;
        model.setApps({{QStringLiteral("Kate"),
                        {},
                        {},
                        {QStringLiteral("Utility")},
                        QStringLiteral("Text Editor"),
                        QStringLiteral("org.kde.kate.desktop"),
                        {QStringLiteral("Notepad")},
                        QStringLiteral("Edit files"),
                        QStringLiteral("Flatpak")}});
        const QString hay = AppSearch::haystack(model.index(0, 0));
        for (const char *part : {"kate", "text editor", "notepad", "utility", "edit files", "flatpak"}) {
            QVERIFY2(hay.contains(QLatin1String(part)), part);
        }
        QVERIFY(!hay.contains(QLatin1String("org.kde")));
    }

    void completionPrefersANameThenAWord()
    {
        StubAppModel model;
        model.setApps({
            {QStringLiteral("Ghostty"), {}, {}, {}, QStringLiteral("Terminal emulator"), QStringLiteral("g"), {}, {}, {}},
            {QStringLiteral("Visual Studio Code"), {}, {}, {}, {}, QStringLiteral("v"), {QStringLiteral("vscode")}, {}, {}},
        });
        QCOMPARE(AppSearch::completion(model, QStringLiteral("vi"), 25), QStringLiteral("Visual Studio Code"));
        QCOMPARE(AppSearch::completion(model, QStringLiteral("te"), 25), QStringLiteral("Terminal"));
        QCOMPARE(AppSearch::completion(model, QStringLiteral("vs"), 25), QStringLiteral("vscode"));
        QVERIFY(AppSearch::completion(model, QStringLiteral("vs"), 1).isEmpty());
        QVERIFY(AppSearch::completion(model, QString(), 25).isEmpty());
    }

    void rowIndexFollowsTheModel()
    {
        StubAppModel model;
        model.setApps({
            {QStringLiteral("A"), {}, {}, {}, {}, QStringLiteral("a.desktop"), {}, {}, {}},
            {QStringLiteral("B"), {}, {}, {}, {}, QStringLiteral("b.desktop"), {}, {}, {}},
        });
        AppRowIndex index;
        QCOMPARE(index.rowOf(QStringLiteral("a.desktop")), -1);
        index.setModel(&model);
        QCOMPARE(index.rowOf(QStringLiteral("b.desktop")), 1);
        QVERIFY(!index.contains(QStringLiteral("c.desktop")));
        QVERIFY(index.haystack(0).startsWith(QLatin1String("a\n")));

        model.setApps({{QStringLiteral("C"), {}, {}, {}, {}, QStringLiteral("c.desktop"), {}, {}, {}}});
        QCOMPARE(index.rowOf(QStringLiteral("b.desktop")), 1);
        index.invalidate();
        QCOMPARE(index.rowOf(QStringLiteral("b.desktop")), -1);
        QCOMPARE(index.rowOf(QStringLiteral("c.desktop")), 0);
        QVERIFY(index.haystack(0).startsWith(QLatin1String("c\n")));
    }
};

QTEST_GUILESS_MAIN(TestAppSearch)

#include "test_appsearch.moc"
