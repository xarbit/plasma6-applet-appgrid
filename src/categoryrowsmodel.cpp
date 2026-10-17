/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "categoryrowsmodel.h"

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

QVariantList CategoryRowsModel::groupedApps() const
{
    return m_groupedApps;
}

void CategoryRowsModel::setGroupedApps(const QVariantList &sections)
{
    m_groupedApps = sections;
    m_categories.clear();
    m_apps.clear();
    for (const QVariant &section : sections) {
        const QVariantMap map = section.toMap();
        m_categories.append(map.value(QStringLiteral("category")).toString());
        m_apps.append(map.value(QStringLiteral("apps")).toList());
    }
    rebuild();
    Q_EMIT groupedAppsChanged();
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
    rebuild();
    Q_EMIT columnsChanged();
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

void CategoryRowsModel::rebuild()
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
