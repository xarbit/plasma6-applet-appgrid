/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QAbstractListModel>
#include <QList>
#include <QStringList>
#include <QVariantList>

/**
 * Pure row layout for the By Category view: each category becomes a header
 * row followed by rows of at most @c columns apps. Rows instead of one block
 * per category let a ListView create (and reuse) only the rows on screen.
 */
namespace CategoryRows
{
enum class Kind {
    Header,
    Apps,
};

struct Row {
    Kind kind = Kind::Header;
    int section = 0;
    // First app of the row within its section, and how many apps it holds
    // (0 for a header).
    int first = 0;
    int count = 0;
    // Flat index (across all sections) of the row's first app; for a header,
    // of its section's first app.
    int flatIndex = 0;

    bool operator==(const Row &) const = default;
};

/** Rows for sections of @p sectionSizes apps, @p columns apps per row (at least 1). */
[[nodiscard]] QList<Row> build(const QList<int> &sectionSizes, int columns);
}

/**
 * @brief The By Category view's rows over AppFilterModel::groupedByCategory.
 *
 * QML sets the grouped sections ([{category, apps:[...]}]) and the column
 * count; each row is a category header or one grid row of app maps.
 */
class CategoryRowsModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(QVariantList groupedApps READ groupedApps WRITE setGroupedApps NOTIFY groupedAppsChanged)
    Q_PROPERTY(int columns READ columns WRITE setColumns NOTIFY columnsChanged)

public:
    enum Roles {
        KindRole = Qt::UserRole + 1,
        CategoryRole,
        SectionRole,
        FirstIndexRole,
        AppsRole,
    };

    explicit CategoryRowsModel(QObject *parent = nullptr);

    [[nodiscard]] int rowCount(const QModelIndex &parent = {}) const override;
    [[nodiscard]] QVariant data(const QModelIndex &index, int role) const override;
    [[nodiscard]] QHash<int, QByteArray> roleNames() const override;

    [[nodiscard]] QVariantList groupedApps() const;
    void setGroupedApps(const QVariantList &sections);
    [[nodiscard]] int columns() const;
    void setColumns(int count);

    /** The row holding the app at @p flatIndex, or -1. */
    Q_INVOKABLE int rowForFlatIndex(int flatIndex) const;
    /** The header row of @p category, or -1. */
    Q_INVOKABLE int rowForCategory(const QString &category) const;

Q_SIGNALS:
    void groupedAppsChanged();
    void columnsChanged();

private:
    void rebuild();

    QVariantList m_groupedApps;
    QStringList m_categories;
    QList<QVariantList> m_apps;
    int m_columns = 1;
    QList<CategoryRows::Row> m_rows;
};
