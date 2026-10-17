/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "settingswindow.h"

#include "appgridconfig.h"
#include "appgridcontroller.h"

#include <KAboutData>
#include <KLocalizedQmlContext>

#include <QQmlApplicationEngine>
#include <QQuickWindow>

SettingsWindow::SettingsWindow(AppGridConfig *config, AppGridConfig *buffer, AppGridController *controller)
    : m_config(config)
    , m_buffer(buffer)
    , m_controller(controller)
{
}

SettingsWindow::~SettingsWindow()
{
    // Declared after the QApplication in main(), so destroyed before it while
    // the QQC2 style is still alive — a clean window teardown. Null first: the
    // delete hides the window, re-entering destroy() via visibleChanged.
    QQmlApplicationEngine *engine = m_engine;
    m_engine = nullptr;
    delete engine;
}

void SettingsWindow::show()
{
    if (!m_engine) {
        load();
    }
    if (QQuickWindow *w = window()) {
        w->show();
        w->raise();
        w->requestActivate();
    }
}

QQuickWindow *SettingsWindow::window() const
{
    if (!m_engine) {
        return nullptr;
    }
    const QList<QObject *> roots = m_engine->rootObjects();
    return roots.isEmpty() ? nullptr : qobject_cast<QQuickWindow *>(roots.first());
}

QStringList SettingsWindow::editableKeys() const
{
    static const QStringList buttonKeys{
        QStringLiteral("icon"),
        QStringLiteral("useCustomButtonImage"),
        QStringLiteral("customButtonImage"),
        QStringLiteral("menuLabel"),
    };
    QStringList keys;
    const auto items = m_buffer->items();
    for (const KConfigSkeletonItem *item : items) {
        if (!buttonKeys.contains(item->name())) {
            keys.append(item->name());
        }
    }
    return keys;
}

void SettingsWindow::load()
{
    m_engine = new QQmlApplicationEngine;
    // Sets the localized context as the root context object (and honours
    // the TRANSLATION_DOMAIN macro, which the standalone target defines).
    KLocalization::setupLocalizedContext(m_engine);
    // Fail-loud contract: ConfigWindow.qml declares these `required`, so a
    // missing injection errors at load instead of silently undefined (#6).
    m_engine->setInitialProperties({
        {QStringLiteral("appGridConfig"), QVariant::fromValue(m_config)},
        {QStringLiteral("appGridConfigBuffer"), QVariant::fromValue(m_buffer)},
        {QStringLiteral("appGridController"), QVariant::fromValue(m_controller)},
        {QStringLiteral("aboutData"), QVariant::fromValue(KAboutData::applicationData())},
        {QStringLiteral("editableKeys"), editableKeys()},
    });
    m_engine->load(QUrl(QStringLiteral("qrc:/qt/qml/appgrid/ConfigWindow.qml")));
    if (const QQuickWindow *w = window()) {
        QObject::connect(w, &QWindow::visibleChanged, m_engine, [this](bool visible) {
            if (!visible) {
                destroy();
            }
        });
    }
}

void SettingsWindow::destroy()
{
    if (!m_engine) {
        return;
    }
    m_engine->deleteLater();
    m_engine = nullptr;
}
