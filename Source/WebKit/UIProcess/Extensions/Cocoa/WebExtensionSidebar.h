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

#pragma once

#if ENABLE(WK_WEB_EXTENSIONS_SIDEBAR)

#include "APIObject.h"
#include "CocoaImage.h"
#include <wtf/Forward.h>
#include <wtf/WeakPtr.h>
#include <wtf/text/WTFString.h>

OBJC_CLASS WKWebView;

namespace WebKit {

class WebExtensionContext;
class WebExtensionTab;
class WebExtensionWindow;

using std::reference_wrapper;
using std::optional;
using std::nullopt;

class WebExtensionSidebar : public API::ObjectImpl<API::Object::Type::WebExtensionSidebar>, public CanMakeWeakPtr<WebExtensionSidebar> {
    WTF_MAKE_NONCOPYABLE(WebExtensionSidebar);
    
public:
    enum class IsDefaultSidebar { No, Yes };

    template<typename... Args>
    static Ref<WebExtensionSidebar> create(Args&&... args)
    {
        return adoptRef(*new WebExtensionSidebar(std::forward<Args>(args)...));
    }
    
    explicit WebExtensionSidebar(WebExtensionContext&, IsDefaultSidebar isDefault = IsDefaultSidebar::No);
    explicit WebExtensionSidebar(WebExtensionContext&, WebExtensionTab&);
    explicit WebExtensionSidebar(WebExtensionContext&, WebExtensionWindow&);

    bool operator==(const WebExtensionSidebar&) const;

    optional<Ref<WebExtensionContext const>> extensionContext() const;
    optional<Ref<WebExtensionContext>> extensionContext();
    optional<Ref<WebExtensionTab const>> tab() const;
    optional<Ref<WebExtensionTab>> tab();
    optional<Ref<WebExtensionWindow const>> window() const;
    optional<Ref<WebExtensionWindow>> window();
    optional<Ref<WebExtensionSidebar const>> parent() const;
    optional<Ref<WebExtensionSidebar>> parent();

    void propertiesDidChange();
    
    CocoaImage *icon(CGSize);
    void setIconsDictionary(NSDictionary *);
    
    /// `title()` will return the overridden title of this sidebar, or the title of the first parent sidebar in which the title is set
    String title() const;
    void setTitleOverride(optional<String>);

    bool isEnabled() const;
    void setEnabled(bool);

    bool isOpen() const { return m_isOpen; }
    bool opensSidebar() { return !sidebarPath().isEmpty(); };
    bool canProgrammaticallyOpenSidebar() const;
    void openSidebarWhenReady();

    bool canProgrammaticallyCloseSidebar() const;
    void closeSidebarWhenReady();

    // TODO: Figure out how to allow programmatic close as well

    /// `sidebarPath()` will return the overriden path of this sidebar, or the path of the first parent sidebar in which the path is set
    String sidebarPath() const;
    void setSidebarPathOverride(optional<String>);

    WKWebView *sidebarWebView();

private:
    explicit WebExtensionSidebar(WebExtensionContext& context, optional<reference_wrapper<WebExtensionTab>> tab, optional<reference_wrapper<WebExtensionWindow>> window, IsDefaultSidebar isDefault);
    bool isDefaultSidebar() const { return m_isDefault == IsDefaultSidebar::Yes || (!m_window && !m_tab); };

    optional<RetainPtr<NSDictionary>> m_iconsOverride;
    optional<String> m_titleOverride;
    optional<String> m_sidebarPathOverride;

    WeakRef<WebExtensionContext> m_context;
    const optional<Ref<WebExtensionTab>> m_tab;
    const optional<Ref<WebExtensionWindow>> m_window;

    bool m_isOpen { false };
    bool m_opensSidebarWhenReady { false };
    bool m_sidebarOpened { false };
    bool m_isEnabled { false };
    const IsDefaultSidebar m_isDefault { IsDefaultSidebar::No };

    RetainPtr<WKWebView> m_sidebarWebView;
};

}

#endif // ENABLE(WK_WEB_EXTENSIONS_SIDEBAR)
