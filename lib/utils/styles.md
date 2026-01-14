Based on the project requirements and coding standards for the selfhost-stack, here is the content for the styles.md file.

Project Style and Technical Standards
This document defines the official style guides and technical standards for the selfhost-stack project. All contributions, refactors, and automated verifications must align with these sources to ensure a consistent, professional, and production-ready environment.

1. Wording and Documentation
All user-facing text, README files, and technical documentation must adhere to professional clarity standards.

Primary Source: Google Developer Style Guide

Active Voice: Use the active voice throughout all documentation and UI labels.

Standard Terminology: Use "Sign in" instead of "Login" to maintain consistency with modern web standards.

Punctuation Constraint: Do not use em dashes (—). Use colons or separate sentences to maintain readability.

2. UI/UX and Visual Design
The dashboard and all service portals must provide a cohesive visual experience.

Primary Source: Material Design 3 (M3)

8dp Grid System: Adhere strictly to the 8dp grid for all layout spacing, padding, and margins.

Typography and Elevation: Use standard M3 typography scales and component elevation levels for all UI elements.

Status Indicators: Use proper Material 3 chips to display service "Online" or "Offline" statuses.

3. Coding Standards
All scripts and backend logic must follow these language-specific guides to maintain a maintainable codebase.

Bash/Shell Scripts
Primary Source: Google Shell Style Guide

Variable Scoping: Always use the local keyword for variables within functions.

Constants: Use readonly for all constant values.

Safety Headers: Every script must include set -euo pipefail to ensure robust error handling.

Python Utilities
Primary Source: Google Python Style Guide

Compliance: Adhere to PEP 8 standards and Google-specific naming conventions for the Hub API and internal utilities.

JavaScript Assets
Primary Source: Google JavaScript Style Guide

Structure: Follow standardized formatting for all dashboard interactions and automated test suites.

4. Technical and Network Standards
Configuration overrides for core services are justified by the following internet standards to ensure security and performance.

DNS Privacy: RFC 7816 (DNS Query Minimization)

DNS Security: RFC 8198 (Aggressive Caching of DNSSEC-Validated Answers)

Networking Architecture: The stack utilizes a split-tunneling model where only the WireGuard port is exposed. This requires key-based authentication for secure remote access.

HTTPS Requirements: A valid SSL certificate is mandatory for DNS-over-HTTPS (DOH), DNS-over-QUIC (DOQ), and VERT to function correctly.

5. Verification and Compliance
All changes must be verified against these standards using the project's automated suite.

Automated Audit: The test/verify_ui.js suite audits the interface for overlapping elements, text overflows, and grid spacing violations.

Log Verification: Testing processes must parse console outputs and Docker logs to identify and resolve any warnings or errors.