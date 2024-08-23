/*
 * Copyright (C) 2023 Apple Inc. All rights reserved.
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
#import "_WKWebExtensionSidebarInternal.h"

#if ENABLE(WK_WEB_EXTENSIONS_SIDEBAR)

#import "WebExtensionSidebar.h"
#import "WebExtensionContext.h"
#import "WebExtensionTab.h"
#import <wtf/CompletionHandler.h>
#import <wtf/BlockPtr.h>

@implementation _WKWebExtensionSidebar

WK_OBJECT_DEALLOC_IMPL_ON_MAIN_THREAD(_WKWebExtensionSidebar, WebExtensionSidebar, _webExtensionSidebar);

- (WKWebExtensionContext *)webExtensionContext
{
    return _webExtensionSidebar->extensionContext()
        .transform([](auto const& context) { return context->wrapper(); })
        .value_or(nil);
}

- (NSString *)title
{
    NSString * tabString;
    uint64_t tabId;
    if (auto tab = _webExtensionSidebar->tab()) {
        tabString = tab.value().get().url().string();
        tabId = tab.value().get().identifier().toRawValue();
    }
    else {
        tabString = @"nullopt";
        tabId = 0;
    }
    NSLog(@"AAAA Getting title for sidebar with tab url '%@', id %llu, title is '%s'", tabString, tabId, _webExtensionSidebar->title().ascii().data());
    return _webExtensionSidebar->title();
}

- (NSImage *)iconForSize:(CGSize)size
{
    return _webExtensionSidebar->icon(size).get();
}

- (BOOL)isEnabled
{
    return _webExtensionSidebar->isEnabled();
}

- (BOOL)opensSidebar
{
    return _webExtensionSidebar->opensSidebar();
}

- (WKWebView *)webView
{
    return _webExtensionSidebar->webView();
}

- (void)willOpenSidebar
{
    _webExtensionSidebar->openSidebarWhenReady();
}

- (void)willCloseSidebar
{
    _webExtensionSidebar->closeSidebarWhenReady();
}

- (id<WKWebExtensionTab>)associatedTab
{
    if (auto tab = _webExtensionSidebar->tab())
        return tab.value()->delegate();
    return nil;
}


- (API::Object&)_apiObject
{
    return *_webExtensionSidebar;
}

- (WebKit::WebExtensionSidebar&) _webExtensionSidebar
{
    return *_webExtensionSidebar;
}


@end
#endif
