# Omarchy Plugin Specification & Publishing Guide

This document provides a complete technical reference for the **Workspace Taskbar** plugin, details the metadata requirements based on Omarchy's top-performing plugins, and outlines the step-by-step process for publishing to GitHub and the official Omarchy Marketplace.

---

## 1. Analysis of Top Omarchy Plugins

A study of the most downloaded and featured community plugins (`io.github.tymurbogach.any-monitor` and `dejan94.todos`) reveals the standard structure expected of production-ready Omarchy bar plugins:

### Required Project Structure
```
omarchy-workspace-taskbar/
├── manifest.json            # Machine-readable plugin metadata and entry points
├── WorkspaceTaskbar.qml     # Root QML component implementing BarWidget
├── preview.png              # Visual preview displayed in GUI marketplaces (Bazaar/Omaplug)
├── README.md                # User-facing documentation and configuration
├── PUBLISHING.md            # Technical specifications and maintenance guide
├── LICENSE                  # Open-source license (MIT recommended)
└── .gitignore               # Excludes caches, temporary files, and editor artifacts
```

### Key Learnings from Top Plugins
1. **Namespace Isolation**: Top plugins use reverse-DNS or author-prefixed IDs (e.g., `dejan94.todos`, `io.github.tymurbogach.any-monitor`). Reserved namespaces like `omarchy.*` are strictly prohibited.
2. **Metadata Completeness**: Both `manifest.json` top-level keys and the kind-specific metadata block (such as `"barWidget": { ... }`) must be provided for rich display in graphical app stores.
3. **No External Runtime Dependencies**: Code relies entirely on Quickshell and Omarchy built-in modules (`qs.Commons`, `qs.Ui`, `Quickshell.Hyprland`).
4. **Security & Cleanliness**: Absolute paths and symlinks inside the package are rejected by the validator to prevent privilege escalation.

---

## 2. Complete Metadata Reference (`manifest.json`)

The Omarchy plugin daemon (`omarchy-shell` / `PluginRegistry.qml`) and CLI validator (`omarchy plugin validate`) strictly enforce the following schema:

```json
{
  "schemaVersion": 1,
  "id": "rahulcodepython.workspace-taskbar",
  "name": "Workspace Taskbar",
  "version": "1.0.0",
  "author": "Rahul Das",
  "license": "MIT",
  "homepage": "https://github.com/rahulcodepython/omarchy-workspace-taskbar",
  "description": "Interactive horizontal taskbar displaying open window pills for the active workspace with click-to-focus and scrolling column centering.",
  "kinds": [
    "bar-widget"
  ],
  "entryPoints": {
    "barWidget": "WorkspaceTaskbar.qml"
  },
  "barWidget": {
    "displayName": "Workspace Taskbar",
    "description": "Every window on the active workspace as a clickable pill; click to focus and center.",
    "category": "Window Management",
    "allowMultiple": false,
    "defaultSection": "left"
  }
}
```

### Field-by-Field Breakdown

| Field | Type | Required | Description |
|---|---|---|---|
| `schemaVersion` | `number` | **Yes** | Must be numeric `1`. String `"1"` will fail schema validation. |
| `id` | `string` | **Yes** | Unique identifier (`^[A-Za-z0-9][A-Za-z0-9._-]*$`). Must NOT start with `omarchy.` and must NOT contain path traversal (`..` or `/`). |
| `name` | `string` | **Yes** | Human-readable plugin title shown in menus, logs, and catalogs. |
| `version` | `string` | **Yes** | SemVer format (e.g., `"1.0.0"`). Used by `omarchy plugin update` to compare versions. |
| `author` | `string` | **Yes** | Author's name or public GitHub handle. |
| `license` | `string` | Recommended | SPDX license identifier (`MIT`, `GPL-3.0-or-later`, `Apache-2.0`). |
| `homepage` | `string` | Recommended | Public URL linking to the project's repository or documentation. |
| `description` | `string` | Recommended | Short, clear description of the plugin's functionality. |
| `kinds` | `string[]` | **Yes** | Non-empty array of plugin types: `"bar-widget"`, `"bar"`, `"menu"`, `"overlay"`, `"panel"`, or `"service"`. |
| `entryPoints` | `object` | **Yes** | Map of kind names to relative file paths. For `"bar-widget"`, the key must be `"barWidget"`. Absolute paths and `..` are forbidden. |
| `barWidget` | `object` | Optional | Kind-specific placement & catalog settings (see below). |

### `barWidget` Sub-Object

| Field | Type | Description |
|---|---|---|
| `displayName` | `string` | Name shown in the Omarchy bar customizer. |
| `description` | `string` | Brief description displayed when choosing widgets. |
| `category` | `string` | Grouping category (`"Window Management"`, `"System"`, `"Productivity"`, `"Compositor"`). |
| `allowMultiple` | `boolean` | `false` if only one instance should appear on the bar. |
| `defaultSection` | `string` | Default dock position when enabled without explicit placement. Must be one of: `"left"`, `"centerBegin"`, `"center"`, `"centerEnd"`, `"tray"`, or `"right"`. |

---

## 3. Local Development & Validation

### Validate Manifest and Files
Omarchy provides a built-in schema validator that tests against all shell safety invariants:

```bash
omarchy plugin validate ~/Workspace/omarchy-workspace-taskbar
```
A successful validation exits with status `0` and outputs no errors.

### Security Invariants Checked
- Manifest is valid JSON with `schemaVersion: 1`.
- ID does not collide with reserved first-party namespaces.
- All declared entry points are safe relative paths that actually exist on disk.
- **Zero symlinks**: Symlinks are rejected to avoid pointing into unauthorized directories.

---

## 4. End-to-End Publishing Process

### Step 1: Initialize and Commit Locally
Ensure all files are committed to the repository:

```bash
cd ~/Workspace/omarchy-workspace-taskbar
git add .
git commit -m "feat: initial release of workspace taskbar v1.0.0"
git tag -a v1.0.0 -m "Release v1.0.0"
```

### Step 2: Push to GitHub
1. Create a new public repository named `omarchy-workspace-taskbar` on [GitHub](https://github.com/new).
2. Push your commits and tags:

```bash
git branch -M main
git remote add origin https://github.com/rahulcodepython/omarchy-workspace-taskbar.git
git push -u origin main --tags
```

### Step 3: Test Real-World Installation
Verify that remote users can cleanly install and enable the widget:

```bash
# Install and enable directly from git
omarchy plugin add https://github.com/rahulcodepython/omarchy-workspace-taskbar.git --enable

# Verify status in plugin list
omarchy plugin list
```

### Step 4: Submit to the Omarchy Marketplace
To list the plugin in the GUI browser (Omaplug / Bazaar) and registry:

1. Visit [plugins.omarchy.org/publish.html](https://plugins.omarchy.org/publish.html) (or the official Omarchy Community Plugins directory repository).
2. Submit your GitHub repository URL:
   `https://github.com/rahulcodepython/omarchy-workspace-taskbar`
3. The registry CI pipeline will:
   - Clone your repository.
   - Run `omarchy plugin validate .` to verify schema conformance.
   - Extract `preview.png` for store thumbnails.
   - Publish the entry to the community catalog.

---

## 5. Maintenance & Versioning

When publishing updates:
1. Increment the `"version"` field in `manifest.json` following Semantic Versioning (e.g., `"1.0.1"` or `"1.1.0"`).
2. Commit and tag the release (`git tag -a v1.1.0 -m "Release v1.1.0"`).
3. Push to GitHub (`git push origin main --tags`).
4. Users can update instantly using:
   ```bash
   omarchy plugin update rahulcodepython.workspace-taskbar
   ```
