/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QSortFilterProxyModel>

/**
 * A QSortFilterProxyModel with a filter-only refresh that works across Qt
 * versions. Base of AppGrid's filtering proxies; it adds no signals, slots or
 * properties.
 */
class FilterProxyModel : public QSortFilterProxyModel
{
public:
    using QSortFilterProxyModel::QSortFilterProxyModel;

protected:
    /** Re-run only the filter, not the sort. Qt 6.13 replaced
     *  invalidateFilter() with begin/endFilterChange(); call this instead of
     *  invalidate() when only the filter changed. */
    void refilter()
    {
#if QT_VERSION >= QT_VERSION_CHECK(6, 13, 0)
        beginFilterChange();
        endFilterChange();
#else
        QT_WARNING_PUSH
        QT_WARNING_DISABLE_DEPRECATED
        invalidateFilter();
        QT_WARNING_POP
#endif
    }
};
