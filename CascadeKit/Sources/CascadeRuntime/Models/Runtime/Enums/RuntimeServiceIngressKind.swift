//
//  RuntimeServiceIngressKind.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// RuntimeServiceIngressKind names the dedicated service bodies that share the incarnation's single
/// ingress slot. Kind is part of the exact claim; completion sequence belongs to publication, not
/// consumer service.
enum RuntimeServiceIngressKind: Hashable, Sendable { case invocation, completion, control, sourceOutput }
