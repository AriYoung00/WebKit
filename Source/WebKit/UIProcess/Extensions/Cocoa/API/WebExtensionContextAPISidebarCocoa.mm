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

#if ENABLE(WK_WEB_EXTENSIONS_SIDEBAR)

#import "WebExtensionSidebar.h"
#import "WKWebExtensionControllerDelegatePrivate.h"

namespace WebKit {

template<typename T>
static Expected<T, WebExtensionError> toExpected(std::optional<T>&& optional, NSString * const errorMessage = @"value not found")
{
    if (optional)
        return WTFMove(optional.value());
    return toWebExtensionError(nil, nil, errorMessage);
}

static Expected<Ref<WebExtensionSidebar>, WebExtensionError> getSidebarWithIdentifiers(std::optional<WebExtensionWindowIdentifier> windowIdentifier, std::optional<WebExtensionTabIdentifier> tabIdentifier, WebExtensionContext& context)
{
    if (windowIdentifier && tabIdentifier)
        return toWebExtensionError(nil, nil, @"cannot specify both windowId and tabId");

    if (windowIdentifier) {
        RefPtr window = context.getWindow(*windowIdentifier);
        if (!window)
            return toWebExtensionError(nil, nil, @"window not found");
        return context.getSidebar(*window).value_or(context.defaultSidebar());
    }

    if (tabIdentifier) {
        RefPtr tab = context.getTab(*tabIdentifier);
        if (!tab)
            return toWebExtensionError(nil, nil, @"tab not found");
        return context.getSidebar(*tab)
            .or_else([&] { return context.getSidebar(*(tab->window())); })
            .value_or(context.defaultSidebar());
    }

    return Ref { context.defaultSidebar() };
}

static Expected<Ref<WebExtensionSidebar>, WebExtensionError> getOrCreateSidebarWithIdentifiers(std::optional<WebExtensionWindowIdentifier> windowIdentifier, std::optional<WebExtensionTabIdentifier> tabIdentifier, WebExtensionContext& context)
{
    if (windowIdentifier && tabIdentifier)
        return toWebExtensionError(nil, nil, @"cannot specify both windowId and tabId");

    if (windowIdentifier) {
        RefPtr window = context.getWindow(*windowIdentifier);
        if (!window)
            return toWebExtensionError(nil, nil, @"window not found");
        return toExpected(context.getOrCreateSidebar(*window), @"could not create sidebar");
    }

    if (tabIdentifier) {
        RefPtr tab = context.getTab(*tabIdentifier);
        if (!tab)
            return toWebExtensionError(nil, nil, @"tab not found");
        return toExpected(context.getOrCreateSidebar(*tab), @"could not create sidebar");
    }

    return Ref { context.defaultSidebar() };
}

void WebExtensionContext::openSidebar(WebExtensionSidebar& sidebar)
{
    ASSERT(isLoaded());
    if (!isLoaded())
        return;

    RefPtr controller = extensionController();
    if (!controller)
        return;

    auto *controllerDelegate = controller->delegate();
    auto *controllerWrapper = controller->wrapper();
    auto *sidebarWrapper = sidebar.wrapper();
    auto *contextWrapper = wrapper();
    if (!(controllerDelegate && controllerWrapper && sidebarWrapper && contextWrapper))
        return;

    [controllerDelegate _webExtensionController:controllerWrapper presentSidebar:sidebarWrapper forExtensionContext:contextWrapper completionHandler:^(NSError *error) { }];
}

void WebExtensionContext::closeSidebar(WebExtensionSidebar& sidebar)
{
    ASSERT(isLoaded());
    if (!isLoaded())
        return;

    RefPtr controller = extensionController();
    if (!controller)
        return;

    auto *controllerDelegate = controller->delegate();
    auto *controllerWrapper = controller->wrapper();
    auto *sidebarWrapper = sidebar.wrapper();
    auto *contextWrapper = wrapper();
    if (!(controllerDelegate && controllerWrapper && sidebarWrapper && contextWrapper))
        return;

    [controllerDelegate _webExtensionController:controllerWrapper closeSidebar:sidebarWrapper forExtensionContext:contextWrapper completionHandler:^(NSError *error) { }];
}

bool WebExtensionContext::canProgrammaticallyOpenSidebar()
{
    if (!extension().hasSidebar())
        return false;

    RefPtr controller = extensionController();
    if (!controller)
        return false;

    auto *controllerDelegate = controller->delegate();
    if (!controllerDelegate)
        return false;

    return [controllerDelegate respondsToSelector:@selector(_webExtensionController:presentSidebar:forExtensionContext:completionHandler:)];
}

bool WebExtensionContext::canProgrammaticallyCloseSidebar()
{
    if (!extension().hasSidebar())
        return false;

    RefPtr controller = extensionController();
    if (!controller)
        return false;

    auto *controllerDelegate = controller->delegate();
    if (!controllerDelegate)
        return false;

    return [controllerDelegate respondsToSelector:@selector(_webExtensionController:closeSidebar:forExtensionContext:completionHandler:)];
}

void WebExtensionContext::sidebarOpen(const std::optional<WebExtensionWindowIdentifier> windowIdentifier, const std::optional<WebExtensionTabIdentifier> tabIdentifier, CompletionHandler<void(Expected<void, WebExtensionError>&&)>&& completionHandler)
{
    RefPtr<WebExtensionTab> tab;

    if (!tabIdentifier && !windowIdentifier) {
        // In the case where we have neither identifier, we must be servicing sidebarAction rather than sidepanel
        // since sidePanel requires one of the identifiers to be set in calls to open.
        // The firefox API specifies that open() will just toggle the sidebar in the active window.
        if (auto window = frontmostWindow())
            tab = window->activeTab();
        else {
            completionHandler(toWebExtensionError(nil, nil, @"no windows are open"));
            return;
        }
    } else {
        // chrome's sidePanel allows both windowIdentifier and tabIdentifier to be specified for sidePanel.open(), so we will discard windowIdentifier if they are both set
        // since firefox's sidebarAction takes no arguments to sidebarAction.open(), this does not break behavior for that API
        auto correctedWindowIdentifier = tabIdentifier ? std::nullopt : windowIdentifier;

        auto maybeSidebar = getOrCreateSidebarWithIdentifiers(correctedWindowIdentifier, tabIdentifier, *this);
        if (!maybeSidebar) {
            completionHandler(toWebExtensionError(nil, nil, @"could not create sidebar"));
            return;
        }
        Ref<WebExtensionSidebar> sidebar = WTFMove(maybeSidebar.value());

        if (auto window = sidebar->window())
            tab = window->get().activeTab();
        else if (auto maybeTab = sidebar->tab())
            tab = RefPtr { maybeTab.value().ptr() };
        else if (auto window = frontmostWindow())
            tab = window->activeTab();
        else {
            completionHandler(toWebExtensionError(nil, nil, @"no windows are open"));
            return;
        }
    }

    if (!tab) {
        completionHandler(toWebExtensionError(nil, nil, @"could not determine active tab"));
        return;
    }

    if (!hasActiveUserGesture(*tab)) {
        completionHandler(toWebExtensionError(nil, nil, @"open can only be called in response to a user gesture"));
        return;
    }

    std::optional<Ref<WebExtensionSidebar>> sidebar = getOrCreateSidebar(*tab);

    if (!sidebar) {
        completionHandler(toWebExtensionError(nil, nil, @"could not get sidebar for active tab"));
        return;
    }

    if (!canProgrammaticallyOpenSidebar()) {
        completionHandler(toWebExtensionError(nil, nil, @"it is not implemented"));
        return;
    }

    openSidebar(sidebar.value().get());
    completionHandler({ });
}

void WebExtensionContext::sidebarClose(CompletionHandler<void(Expected<void, WebExtensionError>&&)>&& completionHandler)
{
    // This method services a firefox-only API which will just close the sidebar in the active window
    auto window = frontmostWindow();
    if (!window) {
        completionHandler(toWebExtensionError(nil, nil, @"no windows are open"));
        return;
    }

    auto tab = window->activeTab();
    if (!tab) {
        completionHandler(toWebExtensionError(nil, nil, @"unable to determine the active tab"));
        return;
    }

    if (!hasActiveUserGesture(*tab)) {
        completionHandler(toWebExtensionError(nil, nil, @"close can only be called in response to a user gesture"));
        return;
    }

    auto maybeSidebar = getOrCreateSidebar(*tab);
    if (!maybeSidebar) {
        completionHandler(toWebExtensionError(nil, nil, @"could not get sidebar for active tab"));
        return;
    }

    Ref sidebar = WTFMove(maybeSidebar.value());
    if (!canProgrammaticallyCloseSidebar()) {
        completionHandler(toWebExtensionError(nil, nil, @"it is not implemented"));
        return;
    }

    closeSidebar(sidebar.get());
    completionHandler({ });
}

void WebExtensionContext::sidebarIsOpen(const std::optional<WebExtensionWindowIdentifier> windowIdentifier, CompletionHandler<void(Expected<bool, WebExtensionError>&&)>&& completionHandler)
{
    // This method services a Firefox-only API which will check if a sidebar is open in the specified window, or the active window if no window is specified
    RefPtr<WebExtensionWindow> window;
    if (windowIdentifier)
        window = getWindow(*windowIdentifier);
    else
        window = frontmostWindow();

    // if no windows are open, then no sidebars are open
    if (!window) {
        completionHandler(false);
        return;
    }

    bool isOpen = false;
    if (auto currentTab = window->activeTab()) {
        if (auto currentTabSidebar = getSidebar(*currentTab))
            isOpen |= currentTabSidebar.value()->isOpen();
    }

    completionHandler(isOpen);
}

void WebExtensionContext::sidebarToggle(CompletionHandler<void(Expected<void, WebExtensionError>&&)>&& completionHandler)
{
    // this method services a Firefox-only API which toggles the sidebar in the currently active window
    auto window = frontmostWindow();
    if (!window) {
        completionHandler(toWebExtensionError(nil, nil, @"no windows are open"));
        return;
    }

    auto tab = window->activeTab();
    if (!tab) {
        completionHandler(toWebExtensionError(nil, nil, @"unable to determine the active tab"));
        return;
    }

    if (!hasActiveUserGesture(*tab)) {
        completionHandler(toWebExtensionError(nil, nil, @"toggle can only be called in response to a user gesture"));
        return;
    }

    auto maybeSidebar = getOrCreateSidebar(*tab);
    if (!maybeSidebar) {
        completionHandler(toWebExtensionError(nil, nil, @"could not create sidebar"));
        return;
    }

    Ref sidebar = WTFMove(maybeSidebar.value());
    if (sidebar->isOpen()) {
        if (!canProgrammaticallyCloseSidebar()) {
            completionHandler(toWebExtensionError(nil, nil, @"it is not implemented"));
            return;
        }

        closeSidebar(sidebar.get());
    } else {
        if (!canProgrammaticallyOpenSidebar()) {
            completionHandler(toWebExtensionError(nil, nil, @"it is not implemented"));
            return;
        }

        openSidebar(sidebar.get());
    }

    completionHandler({ });
}

void WebExtensionContext::sidebarSetIcon(const std::optional<WebExtensionWindowIdentifier> windowIdentifier, const std::optional<WebExtensionTabIdentifier> tabIdentifier, const String& iconJSON, CompletionHandler<void(Expected<void, WebExtensionError>&&)>&& completionHandler)
{
    // FIXME: <https://webkit.org/b/276833> implement icon-related methods
}

void WebExtensionContext::sidebarGetTitle(const std::optional<WebExtensionWindowIdentifier> windowIdentifier, const std::optional<WebExtensionTabIdentifier> tabIdentifier, CompletionHandler<void(Expected<String, WebExtensionError>&&)>&& completionHandler)
{
    auto sidebar = getSidebarWithIdentifiers(windowIdentifier, tabIdentifier, *this);
    if (!sidebar) {
        completionHandler(makeUnexpected(sidebar.error()));
        return;
    }

    completionHandler(sidebar.value()->title());
}

void WebExtensionContext::sidebarSetTitle(const std::optional<WebExtensionWindowIdentifier> windowIdentifier, const std::optional<WebExtensionTabIdentifier> tabIdentifier, const std::optional<String>& title, CompletionHandler<void(Expected<void, WebExtensionError>&&)>&& completionHandler)
{
    auto sidebar = getOrCreateSidebarWithIdentifiers(windowIdentifier, tabIdentifier, *this);
    if (!sidebar) {
        completionHandler(makeUnexpected(sidebar.error()));
        return;
    }
    sidebar.value()->setTitle(title);

    completionHandler({ });
}

void WebExtensionContext::sidebarGetOptions(const std::optional<WebExtensionWindowIdentifier> windowIdentifier, const std::optional<WebExtensionTabIdentifier> tabIdentifier, CompletionHandler<void(Expected<WebExtensionSidebarParameters, WebExtensionError>&&)>&& completionHandler)
{
    auto maybeSidebar = getOrCreateSidebarWithIdentifiers(windowIdentifier, tabIdentifier, *this);
    if (!maybeSidebar) {
        completionHandler(makeUnexpected(maybeSidebar.error()));
        return;
    }

    auto& sidebar = maybeSidebar.value().get();
    completionHandler(WebExtensionSidebarParameters {
        .enabled       = sidebar.isEnabled(),
        .panelPath     = sidebar.sidebarPath(),
        .tabIdentifier = sidebar.tab().transform([](auto tab) { return tab.get().identifier(); }),
    });
}

void WebExtensionContext::sidebarSetOptions(const std::optional<WebExtensionWindowIdentifier> windowIdentifier, const std::optional<WebExtensionTabIdentifier> tabIdentifier, const std::optional<String>& panelSourcePath, const std::optional<bool> enabled, CompletionHandler<void(Expected<void, WebExtensionError>&&)>&& completionHandler)
{
    auto maybeSidebar = getOrCreateSidebarWithIdentifiers(windowIdentifier, tabIdentifier, *this);
    if (!maybeSidebar) {
        completionHandler(makeUnexpected(maybeSidebar.error()));
        return;
    }

    auto& sidebar = maybeSidebar.value().get();
    sidebar.setSidebarPath(panelSourcePath);
    // according to the sidePanel docs, `enabled` is optional with default value `true`
    // we only need to be concerned with chrome's semantics here since sidebarAction does not have any concept of enablement
    // see: https://developer.chrome.com/docs/extensions/reference/api/sidePanel#type-PanelOptions
    sidebar.setEnabled(enabled.value_or(true));
    completionHandler({ });
}

bool WebExtensionContext::isSidebarMessageAllowed()
{
    if (auto *controller = extensionController())
        return controller->isFeatureEnabled(@"WebExtensionSidebarEnabled");
    return false;
}

} // namespace WebKit

#endif // ENABLE(WK_WEB_EXTENSIONS_SIDEBAR)
