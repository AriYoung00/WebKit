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
#import "WebExtensionSidebar.h"
#import "CocoaHelpers.h"

#if ENABLE(WK_WEB_EXTENSIONS_SIDEBAR)

#import "CocoaHelpers.h"
#import "WKWebExtensionControllerDelegatePrivate.h"
#import "WKWebViewConfigurationPrivate.h"
#import "WKWebViewInternal.h"
#import "WebExtensionContext.h"
#import "WebExtensionTab.h"
#import "WebExtensionWindow.h"
#import "WKNavigationPrivate.h"
#import "WKNavigationDelegate.h"
#import "WKNavigationDelegatePrivate.h"
#import "WKUIDelegatePrivate.h"
#import "WKNavigationAction.h"
#import "WebExtensionWindowIdentifier.h"
#import "_WKWebExtensionSidebar.h"

#import <wtf/BlockPtr.h>

template <typename T>
ALWAYS_INLINE std::optional<Ref<T>> toOptionalRef(RefPtr<T> ptr)
{
    if (ptr)
        return *ptr;
    return std::nullopt;
}

@interface _WKWebExtensionSidebarWebViewDelegate : NSObject <WKNavigationDelegatePrivate /*, WKUIDelegatePrivate*/>
@end

@implementation _WKWebExtensionSidebarWebViewDelegate {
    WeakPtr<WebKit::WebExtensionSidebar> _webExtensionSidebar;
}

- (instancetype)initWithWebExtensionSidebar:(WebKit::WebExtensionSidebar&)sidebar
{
    if (!(self = [super init]))
        return nil;

    _webExtensionSidebar = sidebar;

    return self;
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
    if (!_webExtensionSidebar || !_webExtensionSidebar->extensionContext()) {
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }

    if ([navigationAction.request.URL.absoluteString rangeOfString:@"_generated_background_page.html"].location != NSNotFound) {
        NSLog(@"AAAA intercepted request to navigate to background page");
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }

    Ref context = _webExtensionSidebar->extensionContext().value();
    NSURL *targetURL = navigationAction.request.URL;
    bool isURLForThisExtension = context->isURLForThisExtension(targetURL);

    if (!navigationAction.targetFrame || (navigationAction.targetFrame.isMainFrame && !isURLForThisExtension)) {
        std::optional currentWindow = _webExtensionSidebar->window();
        std::optional currentTab = _webExtensionSidebar->tab();
        if (!currentWindow && currentTab)
            currentWindow = toOptionalRef(currentTab.value()->window());
        else if (!currentWindow && !currentTab)
            currentWindow = toOptionalRef(context->frontmostWindow());

        WebKit::WebExtensionTabParameters tabParameters;
        tabParameters.url = targetURL;
        tabParameters.windowIdentifier = currentWindow
            .transform([](auto const& window) { return window->identifier(); })
            .value_or(WebKit::WebExtensionWindowConstants::CurrentIdentifier);
        tabParameters.index = currentTab
            .transform([](auto const& tab) { return tab->index() + 1; });
        tabParameters.active = true;

        context->openNewTab(tabParameters, [](auto const& newTab) { });

        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }

    if (!navigationAction.targetFrame.isMainFrame) {
        decisionHandler(WKNavigationActionPolicyAllow);
        return;
    }

    ASSERT(navigationAction.targetFrame.isMainFrame);
    ASSERT(isURLForThisExtension);

    decisionHandler(WKNavigationActionPolicyAllow);
}

@end

namespace WebKit {

static NSString * const fallbackPath = @"about:blank";
static NSString * const fallbackTitle = @"";

static std::optional<String> getDefaultSidebarTitleFromExtension(WebExtension& extension)
{
    return toOptional(extension.sidebarTitle());
}

static std::optional<String> getDefaultSidebarPathFromExtension(WebExtension& extension)
{
    return toOptional(extension.sidebarDocumentPath());
}

static std::optional<NSDictionary *> getDefaultIconsDictFromExtension(WebExtension& extensions)
{
    // FIXME: <https://webkit.org/b/276833> implement this
    return std::nullopt;
}

WebExtensionSidebar::WebExtensionSidebar(WebExtensionContext& context, IsDefault isDefault) : WebExtensionSidebar(context, std::nullopt, std::nullopt, isDefault) { };

WebExtensionSidebar::WebExtensionSidebar(WebExtensionContext& context, WebExtensionTab& tab) : WebExtensionSidebar(context, tab, std::nullopt, IsDefault::No) { };

WebExtensionSidebar::WebExtensionSidebar(WebExtensionContext& context, WebExtensionWindow& window) : WebExtensionSidebar(context, std::nullopt, window, IsDefault::No) { };

WebExtensionSidebar::WebExtensionSidebar(WebExtensionContext& context, std::optional<Ref<WebExtensionTab>> tab, std::optional<Ref<WebExtensionWindow>> window, IsDefault isDefault)
    : m_extensionContext(context), m_tab(tab), m_window(window), m_isDefault(isDefault)
{
    ASSERT(!(m_tab && m_window));

    // if this is the default action, initialize with default sidebar path / title if present
    if (isDefaultSidebar()) {
        auto& extension = context.extension();
        m_titleOverride = getDefaultSidebarTitleFromExtension(extension);
        m_sidebarPathOverride = getDefaultSidebarPathFromExtension(extension);
        m_iconsOverride = getDefaultIconsDictFromExtension(extension);
    }
}

std::optional<Ref<WebExtensionContext>> WebExtensionSidebar::extensionContext() const
{
    if (auto *context = m_extensionContext.get())
        return *context;
    return std::nullopt;
}

const std::optional<Ref<WebExtensionTab>> WebExtensionSidebar::tab() const
{
    return m_tab;
}

const std::optional<Ref<WebExtensionWindow>> WebExtensionSidebar::window() const
{
    return m_window;
}

std::optional<Ref<WebExtensionSidebar>> WebExtensionSidebar::parent() const
{
    if (!extensionContext() || isDefaultSidebar())
        return std::nullopt;

    return m_tab.and_then([this](auto const& tab) -> std::optional<Ref<WebExtensionSidebar>> {
        return tab->window() ? m_extensionContext->getSidebar(*(tab->window())) : std::nullopt;
    }).value_or(m_extensionContext->defaultSidebar());
}

void WebExtensionSidebar::propertiesDidChange()
{
    // FIXME: <https://webkit.org/b/277575> notify the delegate that something has changed (implement this)
}

RetainPtr<CocoaImage> WebExtensionSidebar::icon(CGSize size)
{
    if (!extensionContext())
        return nil;

    const auto largestDim = [](CGSize size) {
        return size.width > size.height ? size.width : size.height;
    };

    auto& context = extensionContext().value().get();
    return m_iconsOverride
        .and_then([&](RetainPtr<NSDictionary> icons) -> std::optional<RetainPtr<CocoaImage>> {
            return toOptional(context.extension().bestImageInIconsDictionary(icons.get(), largestDim(size)));
        })
        .or_else([&] -> std::optional<RetainPtr<CocoaImage>> {
            return parent().transform([&](auto const& parent) { return parent.get().icon(size); });
        })
        // using .or_else(..).value() is more efficient than value_or, since value_or will evaluate its argument
        // regardless of whether or not it's used. by switching to or_else(..).value() we instead lazily evaluate
        // the fallback value
        .or_else([&] { return std::optional { RetainPtr(context.extension().actionIcon(size)) }; })
        .value();
}

void WebExtensionSidebar::setIconsDictionary(NSDictionary *icons)
{
    if (!icons || !icons.count) {
        m_iconsOverride = std::nullopt;
        return;
    }

    if (m_iconsOverride && [m_iconsOverride.value() isEqualToDictionary:icons])
        return;

    m_iconsOverride = icons;
    propertiesDidChange();
}

String WebExtensionSidebar::title() const
{
    return m_titleOverride
        .or_else([this] { return parent().transform([](auto const& parent) { return parent->title(); }); })
        .value_or(fallbackTitle);
}

void WebExtensionSidebar::setTitle(std::optional<String> titleOverride)
{
    if (!titleOverride && isDefaultSidebar() && extensionContext())
        m_titleOverride = getDefaultSidebarTitleFromExtension(extensionContext().value()->extension());
    else
        m_titleOverride = titleOverride;

#ifdef __OBJC__
    _WKWebExtensionSidebar *wrapper = API::ObjectImpl<API::Object::Type::WebExtensionSidebar>::wrapper();
    id <_WKWebExtensionSidebarDelegate> delegate = wrapper.delegate;

    if (delegate && [delegate respondsToSelector:@selector(titleWasUpdated)])
        [delegate titleWasUpdated];
#endif
}

bool WebExtensionSidebar::isEnabled() const
{
    return m_isEnabled
        .or_else([this] { return parent().transform([](auto const& parent) { return parent->isEnabled(); }); })
        .value_or(false);
}

void WebExtensionSidebar::setEnabled(bool enabled)
{
    m_isEnabled = enabled;
    propertiesDidChange();
}

bool WebExtensionSidebar::canProgrammaticallyOpenSidebar() const
{
    return extensionContext().transform([](auto const& context) -> bool { return !!context.get().extensionController(); })
        .value_or(false);

    // FIXME: <https://webkit.org/b/277575> also check that the controller delegate responds to whatever selector we use for this
}

void WebExtensionSidebar::openSidebarWhenReady()
{
    // FIXME: <https://webkit.org/b/277575> implement openSidebarWhenReady
    if (!extensionContext())
        return;

    if (m_opensSidebarWhenReady || m_sidebarOpened || m_isOpen || !canProgrammaticallyOpenSidebar() || !opensSidebar())
        return;

    m_opensSidebarWhenReady = true;
    dispatch_async(dispatch_get_main_queue(), makeBlockPtr([this, protectedThis = Ref { *this }]() {
        if (!extensionContext() || !m_opensSidebarWhenReady)
            return;

        ASSERT(webView());

        RefPtr extensionController = extensionContext().value()->extensionController();
        auto delegate = extensionController ? extensionController->delegate() : nil;

        if (!delegate || ![delegate respondsToSelector:@selector(_webExtensionController:presentSidebar:forExtensionContext:completionHandler:)]) {
            closeSidebarWhenReady();
            return;
        }


    }).get());
}

bool WebExtensionSidebar::canProgrammaticallyCloseSidebar() const
{
    return extensionContext().transform([](auto const& context) -> bool { return !!context.get().extensionController(); })
        .value_or(false);

    // FIXME: <https://webkit.org/b/277575> also check that the controller delegate responds to whatever selector we use for this
}

void WebExtensionSidebar::closeSidebarWhenReady()
{
    // FIXME: <https://webkit.org/b/277575> implement closeSidebarWhenReady
}

String WebExtensionSidebar::sidebarPath() const
{
    return m_sidebarPathOverride
        .or_else([this] { return parent().transform([](auto const& parent) { return parent->sidebarPath(); }); })
        .value_or(fallbackPath);
}

void WebExtensionSidebar::setSidebarPath(std::optional<String> sidebarPath)
{
    // If we previously did not have a path override in this sidebar, then the browser is currently holding a reference to
    // our parent's WebView in correspondence to this sidebar. Similarly, if we previously had an override in this sidebar
    // and it has just been cleared, the browser will hold a reference to this sidebar's WebView. Thus, in both of these cases,
    // we need to tell the browser to ask us for a new reference of the appropriate specificity. However, these conditions do not
    // apply to the default sidebar, as it must always have a WebView -- so if we are the default sidebar, never signal the browser
    // to ask for a new WebView reference.
    bool needToUpdateWebView = (static_cast<bool>(sidebarPath) != static_cast<bool>(m_sidebarPathOverride)) && !isDefaultSidebar();

    if (!sidebarPath && isDefaultSidebar() && extensionContext())
        m_sidebarPathOverride = getDefaultSidebarPathFromExtension(extensionContext().value()->extension());
    else
        m_sidebarPathOverride = sidebarPath;

    if (!m_sidebarPathOverride)
        m_webView = nil;

    if (needToUpdateWebView)
        webViewWasUpdated();
    else
        reloadWebView();
}

void WebExtensionSidebar::reloadWebView()
{
    if (!m_webView)
        return;
    NSLog(@"AAAA reloading web view");

    auto url = URL { extensionContext().value()->baseURL(), sidebarPath() };
    [m_webView loadRequest:[NSURLRequest requestWithURL:url]];
}

WKWebView *WebExtensionSidebar::webView()
{
    static _WKWebExtensionSidebarWebViewDelegate *webViewDelegate;

    std::optional<Ref<WebExtensionContext>> maybeContext;
    if (!opensSidebar() || !(maybeContext = extensionContext()))
        return nil;
    Ref<WebExtensionContext> context = WTFMove(maybeContext.value());

    // TODO: ask in code review if this is bad to do here
//    if (!context->isLoaded())
//        context->extensionController()->load(context);

    // If we have no particular path configured for this sidebar, just give the parent's WebView (whose path will apply to this sidebar)
    if (std::optional<Ref<WebExtensionSidebar>> parentRef; !m_sidebarPathOverride && !isDefaultSidebar() && (parentRef = parent()))
        return parentRef.value()->webView();

    if (m_webView)
        return m_webView.get();

    NSLog(@"AAAA performing initial sidebar page load");
    if (!webViewDelegate)
        webViewDelegate = [[_WKWebExtensionSidebarWebViewDelegate alloc] initWithWebExtensionSidebar:*this];

    auto *webViewConfiguration = context->webViewConfiguration(WebExtensionContext::WebViewPurpose::Sidebar);
//    if (!webViewConfiguration)
//        return nil;

    m_webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:webViewConfiguration];
    m_webView.get().inspectable = context->isInspectable();
    m_webView.get().accessibilityLabel = title();
    m_webView.get().navigationDelegate = webViewDelegate;

    reloadWebView();

    return m_webView.get();
}

#ifdef __OBJC__
void WebExtensionSidebar::webViewWasUpdated()
{
    _WKWebExtensionSidebar *wrapper = API::ObjectImpl<API::Object::Type::WebExtensionSidebar>::wrapper();
    id <_WKWebExtensionSidebarDelegate> delegate = wrapper.delegate;

    if (delegate && [delegate respondsToSelector:@selector(webViewWasUpdated)])
        [delegate webViewWasUpdated];
}
#endif

}

#endif // ENABLE(WK_WEB_EXTENSIONS_SIDEBAR)
