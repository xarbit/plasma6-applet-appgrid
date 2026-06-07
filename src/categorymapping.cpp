/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "categorymapping.h"

// freedesktop category tokens → AppGrid display buckets. Each token
// appears at most once; previously this table had silent duplicates
// (DiscBurning and Emulator) that QHash's last-insert-wins semantics
// resolved to whichever entry happened to come second in the file.
const QHash<QString, QString> &categoryMap()
{
    static const QHash<QString, QString> map = {
        // Utilities
        {QStringLiteral("Utility"), QStringLiteral("Utilities")},
        {QStringLiteral("Accessibility"), QStringLiteral("Utilities")},
        {QStringLiteral("Core"), QStringLiteral("Utilities")},
        {QStringLiteral("Legacy"), QStringLiteral("Utilities")},
        {QStringLiteral("Tools"), QStringLiteral("Utilities")},
        {QStringLiteral("TextEditor"), QStringLiteral("Utilities")},
        {QStringLiteral("TextTools"), QStringLiteral("Utilities")},
        {QStringLiteral("Archiving"), QStringLiteral("Utilities")},
        {QStringLiteral("Compression"), QStringLiteral("Utilities")},
        {QStringLiteral("FileManager"), QStringLiteral("Utilities")},
        {QStringLiteral("TerminalEmulator"), QStringLiteral("Utilities")},
        {QStringLiteral("FileTools"), QStringLiteral("Utilities")},
        {QStringLiteral("Filesystem"), QStringLiteral("Utilities")},
        {QStringLiteral("Calculator"), QStringLiteral("Utilities")},
        {QStringLiteral("Clock"), QStringLiteral("Utilities")},
        {QStringLiteral("ConsoleOnly"), QStringLiteral("Utilities")},
        {QStringLiteral("Viewer"), QStringLiteral("Utilities")},
        // Development
        {QStringLiteral("Development"), QStringLiteral("Development")},
        {QStringLiteral("IDE"), QStringLiteral("Development")},
        {QStringLiteral("Debugger"), QStringLiteral("Development")},
        {QStringLiteral("RevisionControl"), QStringLiteral("Development")},
        {QStringLiteral("WebDevelopment"), QStringLiteral("Development")},
        {QStringLiteral("Building"), QStringLiteral("Development")},
        {QStringLiteral("Translation"), QStringLiteral("Development")},
        {QStringLiteral("GUIDesigner"), QStringLiteral("Development")},
        {QStringLiteral("Profiling"), QStringLiteral("Development")},
        // Graphics
        {QStringLiteral("Graphics"), QStringLiteral("Graphics")},
        {QStringLiteral("2DGraphics"), QStringLiteral("Graphics")},
        {QStringLiteral("3DGraphics"), QStringLiteral("Graphics")},
        {QStringLiteral("RasterGraphics"), QStringLiteral("Graphics")},
        {QStringLiteral("VectorGraphics"), QStringLiteral("Graphics")},
        {QStringLiteral("Photography"), QStringLiteral("Graphics")},
        {QStringLiteral("ImageProcessing"), QStringLiteral("Graphics")},
        {QStringLiteral("Scanning"), QStringLiteral("Graphics")},
        {QStringLiteral("OCR"), QStringLiteral("Graphics")},
        {QStringLiteral("Publishing"), QStringLiteral("Graphics")},
        {QStringLiteral("Art"), QStringLiteral("Graphics")},
        // Internet
        {QStringLiteral("Network"), QStringLiteral("Internet")},
        {QStringLiteral("WebBrowser"), QStringLiteral("Internet")},
        {QStringLiteral("Email"), QStringLiteral("Internet")},
        {QStringLiteral("Chat"), QStringLiteral("Internet")},
        {QStringLiteral("InstantMessaging"), QStringLiteral("Internet")},
        {QStringLiteral("IRCClient"), QStringLiteral("Internet")},
        {QStringLiteral("FileTransfer"), QStringLiteral("Internet")},
        {QStringLiteral("P2P"), QStringLiteral("Internet")},
        {QStringLiteral("RemoteAccess"), QStringLiteral("Internet")},
        {QStringLiteral("News"), QStringLiteral("Internet")},
        {QStringLiteral("Feed"), QStringLiteral("Internet")},
        {QStringLiteral("Telephony"), QStringLiteral("Internet")},
        {QStringLiteral("VideoConference"), QStringLiteral("Internet")},
        // Multimedia
        // DiscBurning lives here (Brasero, K3b, GNOME-Disks) — most
        // disc-burning workflows are media-authoring, not utility.
        {QStringLiteral("AudioVideo"), QStringLiteral("Multimedia")},
        {QStringLiteral("Audio"), QStringLiteral("Multimedia")},
        {QStringLiteral("Video"), QStringLiteral("Multimedia")},
        {QStringLiteral("Music"), QStringLiteral("Multimedia")},
        {QStringLiteral("Player"), QStringLiteral("Multimedia")},
        {QStringLiteral("Recorder"), QStringLiteral("Multimedia")},
        {QStringLiteral("Midi"), QStringLiteral("Multimedia")},
        {QStringLiteral("Mixer"), QStringLiteral("Multimedia")},
        {QStringLiteral("Sequencer"), QStringLiteral("Multimedia")},
        {QStringLiteral("TV"), QStringLiteral("Multimedia")},
        {QStringLiteral("Tuner"), QStringLiteral("Multimedia")},
        {QStringLiteral("DiscBurning"), QStringLiteral("Multimedia")},
        // Office
        {QStringLiteral("Office"), QStringLiteral("Office")},
        {QStringLiteral("Calendar"), QStringLiteral("Office")},
        {QStringLiteral("ContactManagement"), QStringLiteral("Office")},
        {QStringLiteral("Database"), QStringLiteral("Office")},
        {QStringLiteral("Dictionary"), QStringLiteral("Office")},
        {QStringLiteral("Finance"), QStringLiteral("Office")},
        {QStringLiteral("Presentation"), QStringLiteral("Office")},
        {QStringLiteral("ProjectManagement"), QStringLiteral("Office")},
        {QStringLiteral("Spreadsheet"), QStringLiteral("Office")},
        {QStringLiteral("WordProcessor"), QStringLiteral("Office")},
        {QStringLiteral("Documentation"), QStringLiteral("Office")},
        {QStringLiteral("Chart"), QStringLiteral("Office")},
        {QStringLiteral("FlowChart"), QStringLiteral("Office")},
        // Games
        // Emulator lives here (RetroArch, MAME, Dolphin) — game
        // emulators are the common case. Virtualisation engines tag
        // System;Emulator so they resolve to System on first hit.
        {QStringLiteral("Game"), QStringLiteral("Games")},
        {QStringLiteral("ActionGame"), QStringLiteral("Games")},
        {QStringLiteral("AdventureGame"), QStringLiteral("Games")},
        {QStringLiteral("ArcadeGame"), QStringLiteral("Games")},
        {QStringLiteral("BoardGame"), QStringLiteral("Games")},
        {QStringLiteral("BlocksGame"), QStringLiteral("Games")},
        {QStringLiteral("CardGame"), QStringLiteral("Games")},
        {QStringLiteral("LogicGame"), QStringLiteral("Games")},
        {QStringLiteral("Simulation"), QStringLiteral("Games")},
        {QStringLiteral("SportsGame"), QStringLiteral("Games")},
        {QStringLiteral("StrategyGame"), QStringLiteral("Games")},
        {QStringLiteral("RolePlaying"), QStringLiteral("Games")},
        {QStringLiteral("Emulator"), QStringLiteral("Games")},
        {QStringLiteral("KidsGame"), QStringLiteral("Games")},
        // Education & Science
        {QStringLiteral("Education"), QStringLiteral("Education")},
        {QStringLiteral("Science"), QStringLiteral("Education")},
        {QStringLiteral("Math"), QStringLiteral("Education")},
        {QStringLiteral("Astronomy"), QStringLiteral("Education")},
        {QStringLiteral("Chemistry"), QStringLiteral("Education")},
        {QStringLiteral("Geography"), QStringLiteral("Education")},
        {QStringLiteral("Languages"), QStringLiteral("Education")},
        {QStringLiteral("Engineering"), QStringLiteral("Education")},
        {QStringLiteral("Physics"), QStringLiteral("Education")},
        {QStringLiteral("Biology"), QStringLiteral("Education")},
        {QStringLiteral("Geology"), QStringLiteral("Education")},
        {QStringLiteral("Electronics"), QStringLiteral("Education")},
        {QStringLiteral("Robotics"), QStringLiteral("Education")},
        {QStringLiteral("DataVisualization"), QStringLiteral("Education")},
        {QStringLiteral("Economy"), QStringLiteral("Education")},
        {QStringLiteral("Electricity"), QStringLiteral("Education")},
        {QStringLiteral("History"), QStringLiteral("Education")},
        {QStringLiteral("Literature"), QStringLiteral("Education")},
        {QStringLiteral("Construction"), QStringLiteral("Education")},
        // System
        {QStringLiteral("System"), QStringLiteral("System")},
        {QStringLiteral("Settings"), QStringLiteral("System")},
        {QStringLiteral("Monitor"), QStringLiteral("System")},
        {QStringLiteral("Security"), QStringLiteral("System")},
        {QStringLiteral("PackageManager"), QStringLiteral("System")},
        {QStringLiteral("HardwareSettings"), QStringLiteral("System")},
        {QStringLiteral("Printing"), QStringLiteral("System")},
        {QStringLiteral("Virtualization"), QStringLiteral("System")},
    };
    return map;
}

QString mapCategoryToken(const QString &token)
{
    return categoryMap().value(token);
}

// AppGrid display buckets → freedesktop menu-category icons. The -symbolic
// variants are the monochrome icons KDE's own menu (.directory files) ship and
// Kickoff renders for these categories, so the simple-mode bar matches it. Keys
// are the untranslated buckets produced by categoryMap() plus "Other".
const QHash<QString, QString> &bucketIconMap()
{
    static const QHash<QString, QString> map = {
        {QStringLiteral("Utilities"), QStringLiteral("applications-utilities-symbolic")},
        {QStringLiteral("Development"), QStringLiteral("applications-development-symbolic")},
        {QStringLiteral("Graphics"), QStringLiteral("applications-graphics-symbolic")},
        {QStringLiteral("Internet"), QStringLiteral("applications-internet-symbolic")},
        {QStringLiteral("Multimedia"), QStringLiteral("applications-multimedia-symbolic")},
        {QStringLiteral("Office"), QStringLiteral("applications-office-symbolic")},
        {QStringLiteral("Games"), QStringLiteral("applications-games-symbolic")},
        {QStringLiteral("Education"), QStringLiteral("applications-education-symbolic")},
        {QStringLiteral("System"), QStringLiteral("applications-system-symbolic")},
        {QStringLiteral("Other"), QStringLiteral("applications-other-symbolic")},
    };
    return map;
}

QString bucketIcon(const QString &bucket)
{
    return bucketIconMap().value(bucket, QStringLiteral("applications-other-symbolic"));
}
