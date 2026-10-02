//
//  PluginHostTests.swift
//  CascadeTests
//

import Testing

/// PluginHostTests gathers the suites that talk to the real PluginHost bundled in the test host.
/// They share its one process, so they run one test at a time: a test that kills the host, or
/// starts a plugin while another test's dispatch is in flight, would otherwise end that dispatch
/// and make an unrelated test wait out a restart.
@Suite(.serialized)
enum PluginHostTests {}
