/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Regression guard for issue #103: AppModel must not refresh icons via
    QIcon::setThemeName(QIcon::themeName()). That was the old fix for #86
    (icon file replaced on disk), but it sets a *global* override on Qt's
    icon engine, locking the theme name across the whole plasmashell process
    and blocking subsequent system icon-theme switches from propagating.

    The icon-theme / icon-file refresh now lives in AppFilterModel (an
    iconGeneration counter the delegates watch to force an in-place reload);
    see tst_appfiltermodel. This file only guards that the discarded
    setThemeName hammer doesn't return.
*/

#include "appfiltermodel.h"
#include "appmodel.h"

#include <KSycoca>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTest>

class AppModelTest : public QObject
{
    Q_OBJECT
private Q_SLOTS:
    /// Issue #103 regression guard: appmodel.cpp must not call
    /// QIcon::setThemeName again. The bug it caused — global theme-name
    /// override locking the whole plasmashell process — is not directly
    /// observable from a unit test (platform theme detection is not
    /// mockable here), so we guard the source rather than the
    /// behaviour. Comments are stripped before matching so the
    /// explanatory comment that mentions the removed API by name does
    /// not register as a re-introduction.
    void sourceDoesNotCallSetThemeName();

    void initTestCase();
    void cleanupTestCase();
    /// The grid follows the menu: an app the menu doesn't list stays out.
    void appTheMenuLeavesOutIsNotListed();
    /// Issue #224: a favourite the menu doesn't list (a Brave webapp with no
    /// Categories= under a menu without a catch-all) is still served, flagged
    /// as outside the menu, as soon as it becomes a favourite.
    void favouriteTheMenuLeavesOutIsServed();
    /// ...and the filter model shows it among the favourites only.
    void favouriteOutsideTheMenuShowsOnlyInFavourites();

private:
    [[nodiscard]] static int rowOf(const AppModel &model, const QString &storageId);
    QString m_applicationsDir;
};

namespace
{
const QString kUncategorisedId = QStringLiteral("appgrid-test-webapp.desktop");
const QString kCategorisedId = QStringLiteral("appgrid-test-tool.desktop");

void writeDesktopFile(const QString &path, const QByteArray &extraLines)
{
    QFile file(path);
    QVERIFY(file.open(QIODevice::WriteOnly | QIODevice::Truncate));
    file.write("[Desktop Entry]\nType=Application\nName=AppGrid Test App\nExec=true\n" + extraLines);
}
}

void AppModelTest::initTestCase()
{
    // A menu file that doesn't exist: the menu places no app at all, the way a
    // distro menu without an "Unallocated" catch-all leaves out an app with no
    // categories (#224).
    qputenv("XDG_MENU_PREFIX", "appgrid-test-nonexistent-");

    m_applicationsDir = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/applications");
    QVERIFY(QDir().mkpath(m_applicationsDir));
    writeDesktopFile(m_applicationsDir + QLatin1Char('/') + kUncategorisedId, QByteArray());
    writeDesktopFile(m_applicationsDir + QLatin1Char('/') + kCategorisedId, "Categories=Utility;\n");
    KSycoca::self()->ensureCacheValid();
}

void AppModelTest::cleanupTestCase()
{
    QFile::remove(m_applicationsDir + QLatin1Char('/') + kUncategorisedId);
    QFile::remove(m_applicationsDir + QLatin1Char('/') + kCategorisedId);
}

int AppModelTest::rowOf(const AppModel &model, const QString &storageId)
{
    for (int row = 0; row < model.rowCount(); ++row) {
        if (model.index(row).data(AppModel::StorageIdRole).toString() == storageId) {
            return row;
        }
    }
    return -1;
}

void AppModelTest::appTheMenuLeavesOutIsNotListed()
{
    AppModel model;
    QVERIFY(QMetaObject::invokeMethod(&model, "reload"));
    QCOMPARE(rowOf(model, kUncategorisedId), -1);
    QCOMPARE(rowOf(model, kCategorisedId), -1);
}

void AppModelTest::favouriteTheMenuLeavesOutIsServed()
{
    AppModel model;
    QVERIFY(QMetaObject::invokeMethod(&model, "reload"));
    model.setFavoriteApps({kUncategorisedId, QStringLiteral("not-installed.desktop")});

    const int row = rowOf(model, kUncategorisedId);
    QVERIFY2(row >= 0, "a favourite the menu leaves out must be served");
    QVERIFY(model.index(row).data(AppModel::OutsideMenuRole).toBool());
    QCOMPARE(rowOf(model, QStringLiteral("not-installed.desktop")), -1);
    QVERIFY(!model.categories().contains(QStringLiteral("Other")));

    model.setFavoriteApps({});
    QCOMPARE(rowOf(model, kUncategorisedId), -1);
}

void AppModelTest::favouriteOutsideTheMenuShowsOnlyInFavourites()
{
    AppModel model;
    QVERIFY(QMetaObject::invokeMethod(&model, "reload"));
    AppFilterModel filter;
    filter.setSourceModel(&model);
    filter.setFavoriteApps({kUncategorisedId});

    const auto shown = [&filter] {
        for (int row = 0; row < filter.rowCount(); ++row) {
            if (filter.index(row, 0).data(AppModel::StorageIdRole).toString() == kUncategorisedId) {
                return true;
            }
        }
        return false;
    };
    QVERIFY(!shown());
    filter.setShowFavoritesOnly(true);
    QVERIFY(shown());
    filter.setSortFavoritesAlphabetically(true);
    QVERIFY(shown());
}

void AppModelTest::sourceDoesNotCallSetThemeName()
{
    const QString path = QFINDTESTDATA("../src/appmodel.cpp");
    QVERIFY2(!path.isEmpty(), "Could not locate appmodel.cpp via QFINDTESTDATA");
    QFile f(path);
    QVERIFY(f.open(QIODevice::ReadOnly));
    QString src = QString::fromUtf8(f.readAll());
    // Strip comments before grepping so the explanatory comment that
    // references the removed API by name doesn't count as a call.
    src.remove(QRegularExpression(QStringLiteral("//[^\n]*")));
    src.remove(QRegularExpression(QStringLiteral("/\\*.*?\\*/"), QRegularExpression::DotMatchesEverythingOption));

    QVERIFY2(!src.contains(QLatin1String("setThemeName")),
             "appmodel.cpp must not call QIcon::setThemeName — it sets a "
             "global override that blocks subsequent system icon-theme "
             "changes from propagating to this process (issue #103). "
             "Subscribe to KIconLoader::iconChanged instead.");
}

// Custom main because QTEST_MAIN selects QApplication when QtWidgets is
// linked; we only need QGuiApplication (KIconLoader requires Gui, not
// Widgets) and want zero link-time dependency on QtWidgets.
int main(int argc, char *argv[])
{
    QStandardPaths::setTestModeEnabled(true);
    QGuiApplication app(argc, argv);
    AppModelTest test;
    return QTest::qExec(&test, argc, argv);
}

#include "test_appmodel.moc"
