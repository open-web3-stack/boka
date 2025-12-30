import Codec
import Foundation
import PolkaVM
import TracingUtils
import Utils

// MARK: - Host Calls Re-exports

/// This file serves as the main entry point for all host call implementations.
///
/// Host calls are organized into separate files by functional category:
/// - GeneralHostCalls.swift - Gas, fetch, lookups, state I/O
/// - RefineHostCalls.swift - Machine operations, memory management
/// - AccumulateHostCalls.swift - Object creation and state management
/// - DebugHostCalls.swift - Debug logging
///
/// All host call classes are automatically imported from their respective files,
/// maintaining backward compatibility with existing code.

// Note: All host call implementations are now in separate category files.
// Swift automatically imports all public classes from those files.
// No explicit re-exports needed - imports from GeneralHostCalls.swift,
// RefineHostCalls.swift, AccumulateHostCalls.swift, and DebugHostCalls.swift
// are available through the module.
