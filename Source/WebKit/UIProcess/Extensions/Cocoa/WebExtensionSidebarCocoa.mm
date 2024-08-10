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

#import <wtf/BlockPtr.h>

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

- (void)_webView:(WKWebView *)webView navigationDidFinishDocumentLoad:(WKNavigation *)navigation
{
    NSLog(@"AAAA did navigation to %@", navigation._request.URL);
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView
{
    NSLog(@"AAAA sidebar web view just terminated");
}

- (void)webViewDidClose:(WKWebView *)webView
{
    NSLog(@"AAAA sidebar web view just closed");
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    NSLog(@"AAAA sidebar failed provisional navigation to %@", navigation._request.URL);
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    NSLog(@"AAAA sidebar failed non-provisional navigation to %@", navigation._request.URL);
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
    if ([navigationAction.request.URL.absoluteString rangeOfString:@"_generated_background_page.html"].location != NSNotFound) {
        NSLog(@"AAAA intercepted request to navigate to background page");
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }

    NSLog(@"AAAA sidebar wants to navigate to %@", navigationAction.request.URL);
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
    : m_context(context), m_tab(tab), m_window(window), m_isDefault(isDefault)
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
    if (m_context.ptr())
        return m_context.get();
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
    if (!m_context.ptr() || isDefaultSidebar())
        return std::nullopt;

    return m_tab.and_then([this](auto const& tab) -> std::optional<Ref<WebExtensionSidebar>> {
        if (auto window = tab->window())
            return m_context->getSidebar(*window);
        return std::nullopt;
    })
        .value_or(m_context->defaultSidebar());
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
        .value_or(context.extension().actionIcon(size));
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
    return m_titleOverride.value_or(
        parent().transform([](auto const& parent) { return parent.get().title(); }).value_or(fallbackTitle)
    );
}

void WebExtensionSidebar::setTitle(std::optional<String> titleOverride)
{
    m_titleOverride = titleOverride;
    propertiesDidChange();
}

bool WebExtensionSidebar::isEnabled() const
{
    return m_isEnabled;
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

        ASSERT(m_webView);

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
    return m_sidebarPathOverride.value_or(
        parent().transform([](auto const& parent) { return parent.get().sidebarPath(); }).value_or(fallbackPath)
    );
}

void WebExtensionSidebar::setSidebarPath(std::optional<String> sidebarPath)
{
    m_sidebarPathOverride = sidebarPath;
    propertiesDidChange();
}

WKWebView *WebExtensionSidebar::webView()
{
    static _WKWebExtensionSidebarWebViewDelegate *webViewDelegate;

    if (!opensSidebar() || !extensionContext())
        return nil;

    if (m_webView)
        return m_webView.get();

    if (!webViewDelegate)
        webViewDelegate = [[_WKWebExtensionSidebarWebViewDelegate alloc] initWithWebExtensionSidebar:*this];

    auto *webViewConfiguration = extensionContext().value()->webViewConfiguration(WebExtensionContext::WebViewPurpose::Sidebar);
    m_webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:webViewConfiguration];
    m_webView.get().inspectable = extensionContext().value()->isInspectable();
    m_webView.get().accessibilityLabel = title();
    m_webView.get().navigationDelegate = webViewDelegate;

    auto url = URL { extensionContext().value()->baseURL(), sidebarPath() };

    NSString *urlString = url.string();
    NSLog(@"AAAA loading url: %@", urlString);

    [m_webView loadRequest:[NSURLRequest requestWithURL:url]];

    return m_webView.get();
}

}

#endif // ENABLE(WK_WEB_EXTENSIONS_SIDEBAR)
