/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "appgridpanelplugin.h"

#include <KConfigGroup>
#include <QTimer>

namespace
{
QString ownerTag(int w, int h)
{
    return QStringLiteral("appgrid:%1x%2").arg(w).arg(h);
}
}

AppGridPanelPlugin::AppGridPanelPlugin(QObject *parent, const KPluginMetaData &data, const QVariantList &args)
    : AppGridPlugin(parent, data, args)
{
    m_useNativeActivation = true;

    // Deferred to ctor-completion so Plasma has finished wiring this applet
    // into its containment slot's config space before we read or write it.
    QTimer::singleShot(0, this, &AppGridPanelPlugin::restorePopupSizeIfStranger);
}

AppGridPanelPlugin::~AppGridPanelPlugin()
{
    // Alternatives-switch destroys the applet synchronously without firing
    // the expanded=false path that QML hooks into. Persist here so the
    // user's current size always reaches globalConfig before instance
    // death, no matter how the destruction was triggered.
    persistPopupSize();
}

void AppGridPanelPlugin::restorePopupSizeIfStranger()
{
    auto inst = config();
    auto global = globalConfig();

    const int instW = inst.readEntry(QStringLiteral("popupWidth"), -1);
    const int instH = inst.readEntry(QStringLiteral("popupHeight"), -1);
    const QString tag = inst.readEntry(QStringLiteral("popupSizeOwner"), QString());

    // "Ours" requires both pieces: the tag identifies the writer, and the
    // size in the tag identifies what we last wrote. Another launcher (e.g.
    // Kicker after an alternatives switch) writes popupWidth/popupHeight
    // without touching the tag — leaving a stale tag attached to a
    // foreign size. Detect that by comparing.
    if (instW > 0 && instH > 0 && tag == ownerTag(instW, instH))
        return;

    const int globalW = global.readEntry(QStringLiteral("appgridPopupWidth"), -1);
    const int globalH = global.readEntry(QStringLiteral("appgridPopupHeight"), -1);
    if (globalW > 0 && globalH > 0) {
        inst.writeEntry(QStringLiteral("popupWidth"), globalW);
        inst.writeEntry(QStringLiteral("popupHeight"), globalH);
        inst.writeEntry(QStringLiteral("popupSizeOwner"), ownerTag(globalW, globalH));
    } else {
        // No saved AppGrid size — clear the foreign keys so AppletPopup
        // falls back to GridPanel's implicitWidth/Height instead of
        // inheriting the previous launcher's geometry.
        inst.deleteEntry(QStringLiteral("popupWidth"));
        inst.deleteEntry(QStringLiteral("popupHeight"));
        inst.deleteEntry(QStringLiteral("popupSizeOwner"));
    }
    inst.sync();
}

void AppGridPanelPlugin::persistPopupSize()
{
    auto inst = config();
    auto global = globalConfig();

    const int w = inst.readEntry(QStringLiteral("popupWidth"), 0);
    const int h = inst.readEntry(QStringLiteral("popupHeight"), 0);
    if (w <= 0 || h <= 0)
        return;

    global.writeEntry(QStringLiteral("appgridPopupWidth"), w);
    global.writeEntry(QStringLiteral("appgridPopupHeight"), h);
    global.sync();

    inst.writeEntry(QStringLiteral("popupSizeOwner"), ownerTag(w, h));
    inst.sync();
}

K_PLUGIN_CLASS_WITH_JSON(AppGridPanelPlugin, "metadata-panel.json")

#include "appgridpanelplugin.moc"
