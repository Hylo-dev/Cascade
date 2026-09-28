//
//  DisplayPresentation.swift
//  CascadeKit
//

/// DisplayPresentation is the complete content projection for one fixed panel.
/// Provider references are shared, while each surface creates its own local view.
struct DisplayPresentation {

    let primary  : (any NotchLiveActivity)?
    let secondary: (any NotchLiveActivity)?
    let notice   : (any NotchTransientNotice)?
    let expanded : (any NotchLiveActivity)?

    /// expandedIsLiveActivity distinguishes a routed session from the explicit
    /// no-session fallback, even when both use the same provider protocol.
    let expandedIsLiveActivity: Bool

    let showsWidgets            : Bool
    let contextualPage          : (any NotchContextualPage)?
    let contextualPageIsSelected: Bool
    let widgetContentRevision   : UInt64
    let style                   : ExternalNotchStyle

    init(
        primary                 : (any NotchLiveActivity)?,
        secondary               : (any NotchLiveActivity)?,
        notice                  : (any NotchTransientNotice)?,
        expanded                : (any NotchLiveActivity)?,
        expandedIsLiveActivity  : Bool,
        showsWidgets            : Bool,
        contextualPage          : (any NotchContextualPage)? = nil,
        contextualPageIsSelected: Bool = false,
        widgetContentRevision   : UInt64,
        style                   : ExternalNotchStyle
    ) {
        self.primary                  = primary
        self.secondary                = secondary
        self.notice                   = notice
        self.expanded                 = expanded
        self.expandedIsLiveActivity   = expandedIsLiveActivity
        self.showsWidgets             = showsWidgets
        self.contextualPage           = contextualPage
        self.contextualPageIsSelected = contextualPageIsSelected
        self.widgetContentRevision    = widgetContentRevision
        self.style                    = style
    }

    var isExpanded: Bool {
        expanded != nil || showsWidgets || contextualPageIsSelected
    }

    /// visibleActivityRoots mirrors the renderer's real mounted roots. An owner
    /// presents only its expanded root, a notice replaces compact roots locally,
    /// and a compact surface may mount primary plus its detached secondary.
    var visibleActivityRoots: [any NotchActivity] {
        if let expanded {
            return [expanded]
        }

        if showsWidgets || contextualPageIsSelected {
            return []
        }

        if let notice {
            return [notice]
        }

        return [primary, secondary].compactMap { $0 }
    }

    func removingInvalidRoots(
        accepted: Set<ObjectIdentifier>,
        host    : LiveActivityHost
    ) -> DisplayPresentation {
        func validLive(_ activity: (any NotchLiveActivity)?) -> (any NotchLiveActivity)? {
            guard let activity,
                  accepted.contains(ObjectIdentifier(activity)),
                  host.isPresentationValid(activity)
            else {
                return nil
            }

            return activity
        }

        func validNotice(_ activity: (any NotchTransientNotice)?) -> (any NotchTransientNotice)? {
            guard let activity,
                  accepted.contains(ObjectIdentifier(activity)),
                  host.isPresentationValid(activity)
            else {
                return nil
            }

            return activity
        }

        return DisplayPresentation(
            primary                 : validLive(primary),
            secondary               : validLive(secondary),
            notice                  : validNotice(notice),
            expanded                : validLive(expanded),
            expandedIsLiveActivity  : expandedIsLiveActivity,
            showsWidgets            : showsWidgets,
            contextualPage          : contextualPage,
            contextualPageIsSelected: contextualPageIsSelected,
            widgetContentRevision   : widgetContentRevision,
            style                   : style
        )
    }
}
