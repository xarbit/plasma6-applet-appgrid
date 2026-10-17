/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "categoryrowsmodel.h"

#include "categoryqueries.h"

#include <QVariantMap>

#include <algorithm>

namespace CategoryRows
{
QList<Row> build(const QList<int> &sectionSizes, int columns)
{
    const int perRow = std::max(columns, 1);
    QList<Row> rows;
    int flatIndex = 0;
    for (int section = 0; section < sectionSizes.size(); ++section) {
        const int size = sectionSizes.at(section);
        rows.append({Kind::Header, section, 0, 0, flatIndex});
        for (int first = 0; first < size; first += perRow) {
            rows.append({Kind::Apps, section, first, std::min(perRow, size - first), flatIndex + first});
        }
        flatIndex += size;
    }
    return rows;
}
}

CategoryRowsModel::CategoryRowsModel(QObject *parent)
    : QAbstractListModel(parent)
{
    // One source change arrives as a burst of row signals; group once after it.
    m_refreshTimer.setSingleShot(true);
    m_refreshTimer.setInterval(0);
    connect(&m_refreshTimer, &QTimer::timeout, this, &CategoryRowsModel::refresh);
}

int CategoryRowsModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_rows.size();
}

QVariant CategoryRowsModel::data(const QModelIndex &index, int role) const
{
    if (!checkIndex(index, CheckIndexOption::IndexIsValid)) {
        return {};
    }
    const CategoryRows::Row &row = m_rows.at(index.row());
    switch (role) {
    case KindRole:
        return row.kind == CategoryRows::Kind::Header ? QStringLiteral("header") : QStringLiteral("apps");
    case CategoryRole:
        return m_categories.at(row.section);
    case SectionRole:
        return row.section;
    case FirstIndexRole:
        return row.flatIndex;
    case AppsRole:
        return m_apps.at(row.section).mid(row.first, row.count);
    default:
        return {};
    }
}

QHash<int, QByteArray> CategoryRowsModel::roleNames() const
{
    return {
        {KindRole, QByteArrayLiteral("kind")},
        {CategoryRole, QByteArrayLiteral("category")},
        {SectionRole, QByteArrayLiteral("section")},
        {FirstIndexRole, QByteArrayLiteral("firstIndex")},
        {AppsRole, QByteArrayLiteral("apps")},
    };
}

void CategoryRowsModel::setSourceModel(QAbstractItemModel *source)
{
    if (m_source) {
        disconnect(m_source, nullptr, this, nullptr);
    }
    m_source = source;
    if (source) {
        const auto schedule = [this]() {
            if (m_active) {
                m_refreshTimer.start();
            }
        };
        connect(source, &QAbstractItemModel::modelReset, this, schedule);
        connect(source, &QAbstractItemModel::layoutChanged, this, schedule);
        connect(source, &QAbstractItemModel::rowsInserted, this, schedule);
        connect(source, &QAbstractItemModel::rowsRemoved, this, schedule);
        connect(source, &QAbstractItemModel::dataChanged, this, schedule);
    }
    refresh();
}

bool CategoryRowsModel::isActive() const
{
    return m_active;
}

void CategoryRowsModel::setActive(bool active)
{
    if (active == m_active) {
        return;
    }
    m_active = active;
    // Group right away, so a view that just became visible starts with rows.
    refresh();
    Q_EMIT activeChanged();
}

int CategoryRowsModel::columns() const
{
    return m_columns;
}

void CategoryRowsModel::setColumns(int count)
{
    count = std::max(count, 1);
    if (count == m_columns) {
        return;
    }
    m_columns = count;
    rebuildRows();
    Q_EMIT columnsChanged();
}

int CategoryRowsModel::appCount() const
{
    return m_appCount;
}

QString CategoryRowsModel::storageIdAt(int flatIndex) const
{
    return appAt(flatIndex).value(QStringLiteral("storageId")).toString();
}

int CategoryRowsModel::proxyIndexAt(int flatIndex) const
{
    return appAt(flatIndex).value(QStringLiteral("proxyIndex"), -1).toInt();
}

int CategoryRowsModel::rowForFlatIndex(int flatIndex) const
{
    for (int i = 0; i < m_rows.size(); ++i) {
        const CategoryRows::Row &row = m_rows.at(i);
        if (row.kind == CategoryRows::Kind::Apps && flatIndex >= row.flatIndex && flatIndex < row.flatIndex + row.count) {
            return i;
        }
    }
    return -1;
}

int CategoryRowsModel::rowForCategory(const QString &category) const
{
    const int section = m_categories.indexOf(category);
    if (section < 0) {
        return -1;
    }
    for (int i = 0; i < m_rows.size(); ++i) {
        if (m_rows.at(i).kind == CategoryRows::Kind::Header && m_rows.at(i).section == section) {
            return i;
        }
    }
    return -1;
}

int CategoryRowsModel::flatIndexOfCategory(const QString &category) const
{
    const int section = m_categories.indexOf(category);
    return section < 0 ? -1 : m_sectionStarts.at(section);
}

void CategoryRowsModel::refresh()
{
    m_refreshTimer.stop();
    setSections(m_active && m_source ? CategoryQueries::groupByCategory(m_source) : QVariantList());
}

void CategoryRowsModel::setSections(const QVariantList &sections)
{
    m_categories.clear();
    m_apps.clear();
    m_sectionStarts.clear();
    m_appCount = 0;
    for (const QVariant &section : sections) {
        const QVariantMap map = section.toMap();
        m_categories.append(map.value(QStringLiteral("category")).toString());
        m_apps.append(map.value(QStringLiteral("apps")).toList());
        m_sectionStarts.append(m_appCount);
        m_appCount += m_apps.constLast().size();
    }
    rebuildRows();
    Q_EMIT sectionsChanged();
}

void CategoryRowsModel::rebuildRows()
{
    QList<int> sizes;
    sizes.reserve(m_apps.size());
    for (const QVariantList &apps : std::as_const(m_apps)) {
        sizes.append(apps.size());
    }
    beginResetModel();
    m_rows = CategoryRows::build(sizes, m_columns);
    endResetModel();
}

QVariantMap CategoryRowsModel::appAt(int flatIndex) const
{
    if (flatIndex < 0 || flatIndex >= m_appCount) {
        return {};
    }
    // The last section starting at or before flatIndex holds it.
    const auto next = std::upper_bound(m_sectionStarts.cbegin(), m_sectionStarts.cend(), flatIndex);
    const int section = int(std::distance(m_sectionStarts.cbegin(), next)) - 1;
    return m_apps.at(section).at(flatIndex - m_sectionStarts.at(section)).toMap();
}
