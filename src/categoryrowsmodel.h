/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QAbstractListModel>
#include <QList>
#include <QPointer>
#include <QStringList>
#include <QTimer>
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
 * @brief The By Category view: the filtered apps grouped by category, as rows.
 *
 * Groups the source model (AppFilterModel) with CategoryQueries::groupByCategory
 * while active, and lays the sections out as header and app rows of
 * @c columns apps. The view navigates by flat app index (all sections in
 * order); the lookups below map it to an app, a row or a category.
 */
class CategoryRowsModel : public QAbstractListModel
{
    Q_OBJECT
    // Only an active model groups the source; an inactive one is empty, so a
    // hidden view holds no rows.
    Q_PROPERTY(bool active READ isActive WRITE setActive NOTIFY activeChanged)
    Q_PROPERTY(int columns READ columns WRITE setColumns NOTIFY columnsChanged)
    Q_PROPERTY(int appCount READ appCount NOTIFY sectionsChanged)

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

    /** The apps to group; changes to it regroup on the next event-loop turn. */
    void setSourceModel(QAbstractItemModel *source);

    [[nodiscard]] bool isActive() const;
    void setActive(bool active);
    [[nodiscard]] int columns() const;
    void setColumns(int count);
    [[nodiscard]] int appCount() const;

    /** The storage id of the app at @p flatIndex, or an empty string. */
    Q_INVOKABLE QString storageIdAt(int flatIndex) const;
    /** The source row of the app at @p flatIndex, or -1. */
    Q_INVOKABLE int proxyIndexAt(int flatIndex) const;
    /** The row holding the app at @p flatIndex, or -1. */
    Q_INVOKABLE int rowForFlatIndex(int flatIndex) const;
    /** The header row of @p category, or -1. */
    Q_INVOKABLE int rowForCategory(const QString &category) const;
    /** The flat index of the first app in @p category, or -1. */
    Q_INVOKABLE int flatIndexOfCategory(const QString &category) const;

Q_SIGNALS:
    void activeChanged();
    void columnsChanged();
    /** The grouping changed (not just the column count). */
    void sectionsChanged();

private:
    void refresh();
    void setSections(const QVariantList &sections);
    void rebuildRows();
    [[nodiscard]] QVariantMap appAt(int flatIndex) const;

    QPointer<QAbstractItemModel> m_source;
    QTimer m_refreshTimer;
    bool m_active = false;
    int m_columns = 1;
    QStringList m_categories;
    QList<QVariantList> m_apps;
    QList<int> m_sectionStarts;
    int m_appCount = 0;
    QList<CategoryRows::Row> m_rows;
};
