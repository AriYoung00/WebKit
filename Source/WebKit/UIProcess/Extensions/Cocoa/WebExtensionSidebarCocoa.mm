/*
 * Copyright (C) 2024 Apple Inc. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE INC. AND ITS CONTRIBUTORS ``AS IS''
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL APPLE INC. OR ITS CONTRIBUTORS
 * BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 * THE POSSIBILITY OF SUCH DAMAGE.
 */

#if !__has_feature(objc_arc)
#error This file requires ARC. Add the "-fobjc-arc" compiler flag for this file.
#endif

#import "config.h"
#import "WebExtensionContext.h"
#import "WebExtensionSidebar.h"
#import "WebExtensionTab.h"
#import "WebExtensionWindow.h"

#if ENABLE(WK_WEB_EXTENSIONS_SIDEBAR)

namespace WebKit {

template<typename T>
using OptRef = optional<reference_wrapper<T>>;

static NSString * const sidebarActionManifestKey = @"sidebar_action";
static NSString * const sidePanelManifestKey = @"side_panel";
static NSString * const sidebarActionTitleKey = @"default_title";
static NSString * const sidebarActionPathKey = @"default_panel";
static NSString * const sidePanelPathKey = @"default_path";

static NSString * const fallbackPath = @"about:blank";
static NSString * const fallbackTitle = @"";

static optional<NSDictionary<NSString *, id> *> ensureDict(id maybeDict)
{
    if (!maybeDict)
        return nullopt;
    if (![maybeDict isKindOfClass:NSDictionary.class])
        return nullopt;
    return (NSDictionary<NSString *, id> *) maybeDict;
}

static optional<NSString *> ensureStringValue(NSDictionary<NSString *, id>* dict, NSString *key)
{
    if (!dict || !key)
        return nullopt;
    id maybeValue = dict[key];
    if (![maybeValue isKindOfClass:NSString.class])
        return nullopt;
    return (NSString *) maybeValue;
}

static optional<String> getDefaultSidebarTitleFromExtension(WebExtension& extension)
{
    id maybeSidebarAction = extension.manifest()[sidebarActionManifestKey];

    // since sidePanel does not have a default title specified in manifest, we only check sidebarAction
    return ensureDict(maybeSidebarAction)
        .and_then([](auto *sidebarAction) { return ensureStringValue(sidebarAction, sidebarActionTitleKey); })
        .value_or(extension.displayName());
}

static optional<String> getDefaultSidebarPathFromExtension(WebExtension& extension) {
    NSDictionary *manifest = extension.manifest();
    auto maybePanelTitle = ensureDict(manifest[sidebarActionManifestKey])
        .and_then([](NSDictionary<NSString *, id> *sidebarAction) { return ensureStringValue(sidebarAction, sidebarActionPathKey); });

    // since optional::or_else cannot change the contained type, we have to early return here rather than
    // continuing to use monadic operations
    if (maybePanelTitle)
        return maybePanelTitle;

    return ensureDict(manifest[sidePanelManifestKey])
        .and_then([](NSDictionary<NSString *, id> *sidePanel) { return ensureStringValue(sidePanel, sidePanelPathKey); })
        .value_or(fallbackPath);
}

static optional<NSDictionary *> getDefaultIconsDictFromExtension(WebExtension& extensions) {
    // FIXME: implement this
    return nullopt;
}

template<typename T>
static optional<T*> nilToNullopt(T *maybeNil) {
    if (maybeNil)
        return maybeNil;
    else
        return nullopt;
}

WebExtensionSidebar::WebExtensionSidebar(WebExtensionContext& context, IsDefaultSidebar isDefault) : WebExtensionSidebar(context, nullopt, nullopt, isDefault) {};

WebExtensionSidebar::WebExtensionSidebar(WebExtensionContext& context, WebExtensionTab& tab) : WebExtensionSidebar(context, tab, nullopt, IsDefaultSidebar::No) {};

WebExtensionSidebar::WebExtensionSidebar(WebExtensionContext& context, WebExtensionWindow& window) : WebExtensionSidebar(context, nullopt, window, IsDefaultSidebar::No) {};

WebExtensionSidebar::WebExtensionSidebar(WebExtensionContext& context, OptRef<WebExtensionTab> tab, OptRef<WebExtensionWindow> window, IsDefaultSidebar isDefault) : m_context(WeakRef(context)), m_tab(tab),
    // for this API, we never want to override both window and tab -- can only do one at a time
    // if we somehow (erroneously) get both, prefer tab (most specific)
    m_window(window && tab ? nullopt : window), m_isDefault(isDefault) {

    // if this is the default action, initialize with default sidebar path / title if present
    if (isDefaultSidebar()) {
        auto& extension = context.extension();
        m_titleOverride = getDefaultSidebarTitleFromExtension(extension);
        m_sidebarPathOverride = getDefaultSidebarPathFromExtension(extension);
        m_iconsOverride = getDefaultIconsDictFromExtension(extension);
    }
}

optional<Ref<WebExtensionContext const>> WebExtensionSidebar::extensionContext() const {
    if (m_context.ptr())
        return m_context.get();
    else
        return nullopt;
}

optional<Ref<WebExtensionContext>> WebExtensionSidebar::extensionContext() {
    return const_cast<WebExtensionSidebar const*>(this)->extensionContext().transform([](auto ctx) -> Ref<WebExtensionContext> {
        return const_cast<WebExtensionContext&>(ctx.get());
    });
}

optional<Ref<WebExtensionTab const>> WebExtensionSidebar::tab() const {
    return m_tab.transform([](auto tab) -> Ref<WebExtensionTab const> {
        return tab.get();
    });
}

optional<Ref<WebExtensionTab>> WebExtensionSidebar::tab() {
    return const_cast<WebExtensionSidebar const*>(this)->tab().transform([](auto tab) -> Ref<WebExtensionTab> {
        return const_cast<WebExtensionTab&>(tab.get());
    });
}

optional<Ref<WebExtensionWindow const>> WebExtensionSidebar::window() const {
    return m_window.transform([](auto window) -> Ref<WebExtensionWindow const> {
        return window.get();
    });
}

optional<Ref<WebExtensionWindow>> WebExtensionSidebar::window() {
    return const_cast<WebExtensionSidebar const*>(this)->window().transform([](auto window) -> Ref<WebExtensionWindow> {
        return const_cast<WebExtensionWindow&>(window.get());
    });
}

optional<Ref<WebExtensionSidebar const>> WebExtensionSidebar::parent() const {
    if (!m_context.ptr() || isDefaultSidebar())
        return nullopt;

    return m_tab
        .and_then([this](auto tab) { return m_context->getSidebar(*tab->window()); })
        .value_or(m_context->defaultSidebar());
}

optional<Ref<WebExtensionSidebar>> WebExtensionSidebar::parent() {
    return const_cast<WebExtensionSidebar const*>(this)->parent().transform([](auto parent) -> Ref<WebExtensionSidebar> {
        return const_cast<WebExtensionSidebar&>(parent.get());
    });
}

void WebExtensionSidebar::propertiesDidChange() {
    // FIXME: <sidebar delegate> notify the delegate that something has changed (implement this)
}

CocoaImage *WebExtensionSidebar::icon(CGSize size) {
    if (!extensionContext())
        return nil;

    const auto largestDim = [](CGSize size) { return size.width > size.height ? size.width : size.height; };

    auto& context = extensionContext().value().get();
    return m_iconsOverride
        .and_then([&](RetainPtr<NSDictionary> icons) -> optional<CocoaImage *> {
            return nilToNullopt(context.extension().bestImageInIconsDictionary(icons.get(), largestDim(size)));
        })
        .or_else([&] -> optional<CocoaImage *> {
            return parent().transform([&](auto parent) { return parent.get().icon(size); });
        })
        .value_or(context.extension().actionIcon(size));
}

void WebExtensionSidebar::setIconsDictionary(NSDictionary *icons) {
    if (!icons || icons.count == 0) {
        m_iconsOverride = nullopt;
        return;
    }
    if (m_iconsOverride && [m_iconsOverride.value() isEqualToDictionary:icons])
        return;

    m_iconsOverride = icons;
    propertiesDidChange();
}

String WebExtensionSidebar::title() const
{
    return m_titleOverride.value_or(
        parent()
            .transform([](const auto parent) { return parent.get().title(); })
            .value_or(fallbackTitle)
    );
}

void WebExtensionSidebar::setTitleOverride(optional<String> titleOverride) {
    m_titleOverride = titleOverride;
    propertiesDidChange();
}

bool WebExtensionSidebar::isEnabled() const {
    return m_isEnabled;
}

void WebExtensionSidebar::setEnabled(bool enabled) {
    m_isEnabled = enabled;
    propertiesDidChange();
}

bool WebExtensionSidebar::canProgrammaticallyOpenSidebar() const {
    return extensionContext().transform([](auto context) -> bool { return !!context.get().extensionController(); })
        .value_or(false);

    // FIXME: <sidebar delegate> also check that the controller delegate responds to whatever selector we use for this
}

void WebExtensionSidebar::openSidebarWhenReady() {
    // FIXME: <sidebar delegate> implement openSidebarWhenReady
}

bool WebExtensionSidebar::canProgrammaticallyCloseSidebar() const {
    return extensionContext().transform([](auto context) -> bool { return !!context.get().extensionController(); })
        .value_or(false);

    // FIXME: <sidebar delegate> also check that the controller delegate responds to whatever selector we use for this
}

String WebExtensionSidebar::sidebarPath() const
{
    return m_sidebarPathOverride.value_or(
        parent().transform([](const auto parent) { return parent.get().sidebarPath(); }).value_or(fallbackPath)
    );
}

void WebExtensionSidebar::setSidebarPathOverride(optional<String> sidebarPath)
{
    m_sidebarPathOverride = sidebarPath;
    propertiesDidChange();
}

WKWebView *WebExtensionSidebar::sidebarWebView()
{
    return m_sidebarWebView.get();
}

}

#endif // ENABLE(WK_WEB_EXTENSIONS_SIDEBAR)
