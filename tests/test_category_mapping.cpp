/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Tests for the freedesktop-token → bucket mapping. Pins each
    bucket assignment and the previously-ambiguous tokens that the
    pre-extraction map silently duplicated (DiscBurning, Emulator).
*/

#include <QTest>

#include "categorymapping.h"

class TestCategoryMapping : public QObject {
    Q_OBJECT

private Q_SLOTS:
    void unknownTokenReturnsEmpty()
    {
        QVERIFY(mapCategoryToken(QStringLiteral("DoesNotExist")).isEmpty());
        QVERIFY(mapCategoryToken(QString()).isEmpty());
    }

    void utilityTokensMapToUtilities()
    {
        QCOMPARE(mapCategoryToken(QStringLiteral("Utility")), QStringLiteral("Utilities"));
        QCOMPARE(mapCategoryToken(QStringLiteral("TextEditor")), QStringLiteral("Utilities"));
        QCOMPARE(mapCategoryToken(QStringLiteral("FileManager")), QStringLiteral("Utilities"));
        QCOMPARE(mapCategoryToken(QStringLiteral("TerminalEmulator")), QStringLiteral("Utilities"));
        QCOMPARE(mapCategoryToken(QStringLiteral("Calculator")), QStringLiteral("Utilities"));
    }

    void developmentTokensMapToDevelopment()
    {
        QCOMPARE(mapCategoryToken(QStringLiteral("IDE")), QStringLiteral("Development"));
        QCOMPARE(mapCategoryToken(QStringLiteral("Debugger")), QStringLiteral("Development"));
        QCOMPARE(mapCategoryToken(QStringLiteral("RevisionControl")), QStringLiteral("Development"));
    }

    void internetTokensMapToInternet()
    {
        QCOMPARE(mapCategoryToken(QStringLiteral("WebBrowser")), QStringLiteral("Internet"));
        QCOMPARE(mapCategoryToken(QStringLiteral("Email")), QStringLiteral("Internet"));
        QCOMPARE(mapCategoryToken(QStringLiteral("Chat")), QStringLiteral("Internet"));
    }

    void multimediaTokensMapToMultimedia()
    {
        QCOMPARE(mapCategoryToken(QStringLiteral("AudioVideo")), QStringLiteral("Multimedia"));
        QCOMPARE(mapCategoryToken(QStringLiteral("Player")), QStringLiteral("Multimedia"));
        QCOMPARE(mapCategoryToken(QStringLiteral("Recorder")), QStringLiteral("Multimedia"));
    }

    void officeTokensMapToOffice()
    {
        QCOMPARE(mapCategoryToken(QStringLiteral("Spreadsheet")), QStringLiteral("Office"));
        QCOMPARE(mapCategoryToken(QStringLiteral("WordProcessor")), QStringLiteral("Office"));
        QCOMPARE(mapCategoryToken(QStringLiteral("Calendar")), QStringLiteral("Office"));
    }

    void gameTokensMapToGames()
    {
        QCOMPARE(mapCategoryToken(QStringLiteral("Game")), QStringLiteral("Games"));
        QCOMPARE(mapCategoryToken(QStringLiteral("StrategyGame")), QStringLiteral("Games"));
    }

    void systemTokensMapToSystem()
    {
        QCOMPARE(mapCategoryToken(QStringLiteral("Settings")), QStringLiteral("System"));
        QCOMPARE(mapCategoryToken(QStringLiteral("Monitor")), QStringLiteral("System"));
        QCOMPARE(mapCategoryToken(QStringLiteral("Virtualization")), QStringLiteral("System"));
    }

    void educationTokensMapToEducation()
    {
        QCOMPARE(mapCategoryToken(QStringLiteral("Science")), QStringLiteral("Education"));
        QCOMPARE(mapCategoryToken(QStringLiteral("Math")), QStringLiteral("Education"));
    }

    void graphicsTokensMapToGraphics()
    {
        QCOMPARE(mapCategoryToken(QStringLiteral("2DGraphics")), QStringLiteral("Graphics"));
        QCOMPARE(mapCategoryToken(QStringLiteral("Photography")), QStringLiteral("Graphics"));
        QCOMPARE(mapCategoryToken(QStringLiteral("OCR")), QStringLiteral("Graphics"));
    }

    // --- previously-duplicated keys ---

    void discBurningResolvesToMultimedia()
    {
        // Before the dedup: appeared as both Utilities and Multimedia,
        // QHash last-write-wins gave Multimedia. Pin that as the
        // intentional choice now that the duplicate is removed.
        QCOMPARE(mapCategoryToken(QStringLiteral("DiscBurning")),
                 QStringLiteral("Multimedia"));
    }

    void emulatorResolvesToGames()
    {
        // Before the dedup: appeared as both Games and System, QHash
        // gave System. Now pinned to Games — most apps that tag only
        // "Emulator" are game emulators (RetroArch, MAME, Dolphin).
        // Virtualisation apps tag "System;Emulator" and hit System on
        // the first token, so they still bucket correctly.
        QCOMPARE(mapCategoryToken(QStringLiteral("Emulator")),
                 QStringLiteral("Games"));
    }

    // --- table integrity ---

    void allValuesAreKnownBuckets()
    {
        // QHash deduplicates by key automatically, but a key collision
        // in the source file would silently shadow the earlier entry.
        // Sanity-check: every value is one of the known buckets.
        static const QSet<QString> validBuckets = {
            QStringLiteral("Utilities"),
            QStringLiteral("Development"),
            QStringLiteral("Graphics"),
            QStringLiteral("Internet"),
            QStringLiteral("Multimedia"),
            QStringLiteral("Office"),
            QStringLiteral("Games"),
            QStringLiteral("Education"),
            QStringLiteral("System"),
        };
        const auto &map = categoryMap();
        for (auto it = map.constBegin(); it != map.constEnd(); ++it) {
            QVERIFY2(validBuckets.contains(it.value()),
                     qPrintable(QStringLiteral("Unexpected bucket '%1' for key '%2'")
                                    .arg(it.value(), it.key())));
        }
    }

    void tableHasReasonableSize()
    {
        // Smoke check — the source file holds ~100 entries; an
        // accidental wipe (e.g. botched edit) would show up here.
        QVERIFY(categoryMap().size() > 80);
    }
};

QTEST_MAIN(TestCategoryMapping)
#include "test_category_mapping.moc"
