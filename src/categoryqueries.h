/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <functional>

#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

class QAbstractItemModel;
class QModelIndex;

/**
 * Pure read-only category navigation over an app model, extracted from
 * AppFilterModel so the grouping is testable with a stub model and kept off the
 * filter/sort hot path. Mirrors the SearchRanking / FavoritesFolderLogic
 * pure-helper pattern.
 */
namespace CategoryQueries
{
/** The app fields a row exposes to QML (name, iconName, desktopFile, storageId,
 *  comment, installSource). Callers add their own extra keys on top. */
[[nodiscard]] QVariantMap appDataMap(const QModelIndex &index);

/** The categories of @p model's rows that @p isHidden(storageId) keeps out
 *  are skipped: the categories with at least one shown app. Unordered. */
[[nodiscard]] QStringList nonEmptyCategories(const QAbstractItemModel *model, const std::function<bool(const QString &)> &isHidden);

/** Group @p model's rows into [{category, apps:[appDataMap + proxyIndex]}],
 *  one section per category an app declares (categories sorted by QMap). */
[[nodiscard]] QVariantList groupByCategory(const QAbstractItemModel *model);
}
