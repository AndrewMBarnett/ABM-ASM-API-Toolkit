Absolutely! Here's an updated and polished GitHub README including your **new configuration options** and a **sample output section**.

---

# Apple School/Business Manager Device Export Tool

A command-line tool to fetch and export device information from **Apple School Manager (ASM)** or **Apple Business Manager (ABM)** using OAuth 2.0 authentication. Supports exporting devices in **JSON** and **CSV** formats.

---

## Table of Contents

* [Overview](#overview)
* [Features](#features)
* [Requirements](#requirements)
* [Setup](#setup)
* [Usage](#usage)
* [Configuration Options](#configuration-options)
* [Sample Output](#sample-output)
* [Tips & Troubleshooting](#tips--troubleshooting)
* [License](#license)

---

## Overview

This script connects to Apple’s device management APIs, fetches device information, and saves it locally in JSON and CSV formats. It supports both **Apple School Manager** and **Apple Business Manager** environments.

---

## Features

* Fetch devices with full details via Apple API
* Export data in JSON and CSV formats
* Modular configuration for ASM or ABM accounts
* Interactive prompts for credentials, JWT, and output directory
* Handles OAuth 2.0 authentication via JWT

---

## Requirements

* macOS or Linux environment
* `bash` or `zsh` shell
* [jq](https://stedolan.github.io/jq/) (JSON parser)
* `curl`

Install dependencies on macOS using Homebrew:

```bash
brew install jq curl
```

---

## Setup

1. Clone this repository:

```bash
git clone https://github.com/<username>/apple-device-export.git
cd apple-device-export
```

2. Make the script executable:

```bash
chmod +x export_devices.sh
```

3. Prepare your Apple API credentials:

   * **Client ID** from ASM or ABM
   * **Client Assertion (JWT)**, either in a file or pasted directly

---

## Usage

Run the script:

```bash
./export_devices.sh
```

The script will prompt for any missing configuration, including:

* Apple Manager type (School or Business)
* Client ID
* JWT token (direct or file)
* Output directory

After execution, the following files are generated:

* `devices.json` – raw API output
* `devices.csv` – CSV-formatted device list

---

## Configuration Options

You can pre-configure the following variables at the top of the script, or leave them empty to be prompted:

```bash
# ============================================================================
# CONFIGURATION - UPDATE THESE VALUES (or leave empty to be prompted)
# ============================================================================

# Path to your client assertion JWT file (generated separately)
CLIENT_ASSERTION_FILE=""

# Or set the JWT directly
CLIENT_ASSERTION=""

# Your Client ID from ASM
CLIENT_ID=""

# Output directory - where to save the CSV and JSON files
OUTPUT_DIR=""

# Apple Manager Type (school | business)
APPLE_MANAGER_TYPE=""
```

The script automatically adjusts the **API Base URL** and **Scope** based on the chosen Apple Manager type.

---

## Sample Output

### JSON (`devices.json`)

```json
[
  {
    "id": "G9XLG9255F",
    "serialNumber": "C02X12345678",
    "deviceName": "John's iPad",
    "model": "iPad Pro (11-inch)",
    "osVersion": "iPadOS 17.2",
    "assignedUser": "student.john@example.com"
  },
  {
    "id": "Y3C7K9C02K",
    "serialNumber": "C02X87654321",
    "deviceName": "Teacher MacBook",
    "model": "MacBook Pro (14-inch)",
    "osVersion": "macOS 14.1",
    "assignedUser": "teacher.jane@example.com"
  }
]
```

### CSV (`devices.csv`)

```csv
id,serialNumber,deviceName,model,osVersion,assignedUser
G9XLG9255F,C02X12345678,John's iPad,iPad Pro (11-inch),iPadOS 17.2,student.john@example.com
Y3C7K9C02K,C02X87654321,Teacher MacBook,MacBook Pro (14-inch),macOS 14.1,teacher.jane@example.com
```

---

## Tips & Troubleshooting

### 1. Rate Limiting (HTTP 429)

* Apple APIs may throttle requests if too many are made too quickly.
* Wait a few seconds and retry, or run the script in smaller batches.

### 2. Invalid or Missing JWT Token

* Ensure JWT is correct and not expired.
* Verify the Client ID matches your Apple Manager account.

### 3. Output Directory

* Must exist and be writable.
* Press Enter to use the current directory.

### 4. Dependencies

* Ensure `jq` and `curl` are installed.

### 5. Switching Between ASM and ABM

* Choose the Apple Manager type at the start.
* The script adjusts API URLs and scope accordingly.

### 6. Debugging

* Enable verbose output by adding `set -x` at the top of the script.
* Logs show which devices are fetched and any API errors.

---
