# CareDesk: Elder-Caregiver Remote Desktop Solution

## Architecture Plan

---

## 1. Overview

Build a remote desktop solution where **Caregivers** can securely access **Elders'** computers for support, using RustDesk's core technology with a custom integration layer.

```
┌─────────────────┐         ┌─────────────────┐         ┌─────────────────┐
│                 │         │                 │         │                 │
│  Elder's PC     │◄───────►│  Your Backend   │◄───────►│  Caregiver's PC │
│  (RustDesk)     │   API   │  (Database)     │   API   │  (RustDesk CLI) │
│                 │         │                 │         │                 │
└─────────────────┘         └─────────────────┘         └─────────────────┘
        │                           │                           │
        │                           │                           │
        └───────────────────────────┼───────────────────────────┘
                                    │
                            ┌───────▼───────┐
                            │               │
                            │ RustDesk      │
                            │ Relay Server  │
                            │ (Self-hosted) │
                            │               │
                            └───────────────┘
```

---

## 2. User Flow

### Elder Setup Flow

```
1. Elder downloads your custom RustDesk app
2. App auto-starts and generates unique RustDesk ID
3. Elder creates account in your app (email/phone)
4. App sends to your backend:
   - Elder's user info
   - RustDesk ID (e.g., "123 456 789")
   - Permanent password (auto-generated or user-set)
5. Elder gets a PIN code to share with caregiver
6. Elder shares PIN with caregiver (verbally, SMS, etc.)
```

### Caregiver Connection Flow

```
1. Caregiver logs into your app
2. Enters Elder's PIN code
3. Your backend validates PIN and returns:
   - Elder's RustDesk ID
   - Connection password (temporary or permanent)
4. Caregiver clicks "Connect"
5. Your app launches RustDesk CLI:
   rustdesk --connect <elder-id> --password <password>
6. Remote desktop session starts
```

---

## 3. Technical Components

### A. Elder Side (RustDesk Service)

| Component | Purpose |
|-----------|---------|
| RustDesk Service | Runs in background, accepts incoming connections |
| Custom Wrapper | Communicates with your backend API |
| Auto-start | Ensures RustDesk is always available |

**Key RustDesk Config Options:**
```toml
# Located at: ~/.config/rustdesk/RustDesk.toml (Linux/Mac)
# Or: %APPDATA%\RustDesk\config\RustDesk.toml (Windows)

[options]
# Set permanent password
permanent-password = "encrypted_password_here"

# Lock settings (prevent elder from changing)
allow-remote-config-modification = false

# Auto-accept connections (optional, for trusted caregivers)
# approve-mode = "click"  # or "password"
```

### B. Caregiver Side (CLI Client)

**Connection Commands:**

```bash
# Basic connection
rustdesk --connect 123456789 --password "secret"

# With relay server (your self-hosted)
rustdesk --connect 123456789 --password "secret" --relay relay.yourserver.com

# Port forwarding (for specific services)
rustdesk --port-forward 123456789:8080:22:localhost
```

### C. Your Backend API

**Required Endpoints:**

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/elder/register` | POST | Register elder + RustDesk ID |
| `/api/elder/pin/generate` | POST | Generate pairing PIN |
| `/api/caregiver/pair` | POST | Pair caregiver with elder via PIN |
| `/api/connection/request` | POST | Get credentials to connect |
| `/api/connection/log` | POST | Log connection for audit |

**Database Schema:**

```sql
-- Elders table
CREATE TABLE elders (
    id UUID PRIMARY KEY,
    email VARCHAR(255),
    name VARCHAR(255),
    rustdesk_id VARCHAR(20) NOT NULL,      -- e.g., "123456789"
    rustdesk_password_hash VARCHAR(255),    -- encrypted
    pairing_pin VARCHAR(6),                 -- temporary PIN
    pin_expires_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Caregivers table
CREATE TABLE caregivers (
    id UUID PRIMARY KEY,
    email VARCHAR(255),
    name VARCHAR(255),
    created_at TIMESTAMP DEFAULT NOW()
);

-- Pairings (elder-caregiver relationships)
CREATE TABLE pairings (
    id UUID PRIMARY KEY,
    elder_id UUID REFERENCES elders(id),
    caregiver_id UUID REFERENCES caregivers(id),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(elder_id, caregiver_id)
);

-- Connection logs (audit trail)
CREATE TABLE connection_logs (
    id UUID PRIMARY KEY,
    pairing_id UUID REFERENCES pairings(id),
    started_at TIMESTAMP,
    ended_at TIMESTAMP,
    duration_seconds INT,
    ip_address VARCHAR(45)
);
```

---

## 4. Implementation Options

### Option A: CLI Wrapper (Simplest)

Create a simple wrapper that calls RustDesk CLI.

**Pros:** Quick to implement, uses existing RustDesk  
**Cons:** Less control, separate window opens

```python
# Python example for your app
import subprocess
import requests

def connect_to_elder(caregiver_id, elder_pin):
    # 1. Get credentials from your backend
    response = requests.post('https://yourapi.com/api/connection/request', json={
        'caregiver_id': caregiver_id,
        'elder_pin': elder_pin
    })
    data = response.json()
    
    # 2. Launch RustDesk CLI
    subprocess.run([
        'rustdesk',
        '--connect', data['rustdesk_id'],
        '--password', data['password']
    ])
```

### Option B: Library Integration (Recommended)

Build a Rust library from RustDesk's core components.

**Pros:** Full control, embed in your app, custom UI  
**Cons:** More development effort

```rust
// Custom library structure
pub struct CareDesk {
    backend_url: String,
    auth_token: String,
}

impl CareDesk {
    pub async fn connect_to_elder(&self, pin: &str) -> Result<Session> {
        // 1. Fetch credentials from your backend
        let creds = self.fetch_credentials(pin).await?;
        
        // 2. Use RustDesk's Client::start internally
        let session = Client::start(
            &creds.rustdesk_id,
            &creds.key,
            &creds.token,
            ConnType::DEFAULT_CONN,
            handler
        ).await?;
        
        Ok(session)
    }
}
```

### Option C: Flutter App with Embedded RustDesk (Best UX)

Fork the Flutter UI and customize for your use case.

**Pros:** Best user experience, single app, cross-platform  
**Cons:** Most development effort

---

## 5. Self-Hosted Server (Recommended)

For security and reliability, self-host RustDesk server.

### Docker Setup

```yaml
# docker-compose.yml
version: '3'
services:
  hbbs:
    image: rustdesk/rustdesk-server:latest
    command: hbbs -r your-domain.com:21117
    ports:
      - 21115:21115
      - 21116:21116
      - 21116:21116/udp
      - 21118:21118
    volumes:
      - ./data:/root

  hbbr:
    image: rustdesk/rustdesk-server:latest
    command: hbbr
    ports:
      - 21117:21117
      - 21119:21119
    volumes:
      - ./data:/root
```

### Configure Clients to Use Your Server

```toml
# In RustDesk config
[options]
custom-rendezvous-server = "your-domain.com"
relay-server = "your-domain.com"
key = "your-public-key-here"
```

---

## 6. Security Considerations

### Must Have

| Security Measure | Implementation |
|------------------|----------------|
| **Encrypted passwords** | Never store plain text, use bcrypt/argon2 |
| **Temporary tokens** | Connection passwords expire after use |
| **PIN expiration** | Pairing PINs expire in 10-15 minutes |
| **Connection consent** | Elder can approve/deny each connection |
| **Audit logging** | Log all connection attempts |
| **TLS everywhere** | HTTPS for API, encrypted RustDesk connections |

### Nice to Have

| Feature | Purpose |
|---------|---------|
| **Session recording** | Review sessions if needed |
| **Time restrictions** | Only allow connections during certain hours |
| **Notification** | Alert elder when caregiver connects |
| **Emergency disconnect** | Elder can instantly end session |

---

## 7. Development Phases

### Phase 1: MVP (2-3 weeks)

- [ ] Fork and customize RustDesk
- [ ] Build backend API (Node.js/Python/Rust)
- [ ] Create database schema
- [ ] Implement elder registration flow
- [ ] Implement PIN pairing
- [ ] CLI wrapper for caregiver connection
- [ ] Self-host RustDesk server

### Phase 2: Polish (2-3 weeks)

- [ ] Custom branded Elder app (simplified UI)
- [ ] Custom Caregiver app (with contact list)
- [ ] Connection logging and history
- [ ] Push notifications
- [ ] Auto-update mechanism

### Phase 3: Production (2-3 weeks)

- [ ] Security audit
- [ ] Load testing
- [ ] Documentation
- [ ] App store submissions (if mobile)
- [ ] Customer support tools

---

## 8. File Structure for Custom Build

```
Customdesk/
├── src/
│   ├── caredesk/              # NEW: Your custom module
│   │   ├── mod.rs
│   │   ├── api_client.rs      # Backend API communication
│   │   ├── pairing.rs         # PIN pairing logic
│   │   ├── session.rs         # Session management
│   │   └── config.rs          # Custom configuration
│   ├── cli.rs                 # MODIFY: Add caredesk commands
│   └── ...
├── caredesk-backend/          # NEW: Your backend service
│   ├── src/
│   │   ├── main.rs
│   │   ├── routes/
│   │   ├── models/
│   │   └── db/
│   ├── Cargo.toml
│   └── docker-compose.yml
└── docs/
    └── CAREDESK_PLAN.md       # This file
```

---

## 9. CLI Commands Reference (For Electron Integration)

RustDesk has **built-in CLI commands** you can call from your Electron app!

### Build CLI Version

```bash
cd Customdesk
cargo build --release --features cli
```

### Available CLI Commands (Elder Side)

| Command | Purpose | Requires Root/Admin |
|---------|---------|---------------------|
| `--get-id` | Get the RustDesk ID | No |
| `--set-id <ID>` | Set custom ID | Yes |
| `--password <PASS>` | Set permanent password | Yes |
| `--service` | Start as background service | Yes |
| `--option <key>` | Get config option value | Yes |
| `--option <key> <value>` | Set config option | Yes |

### Elder Side: Get ID & Set Password

```bash
# Get the RustDesk ID (works without admin)
./rustdesk --get-id
# Output: 123456789

# Set permanent password (requires admin/root)
# On macOS/Linux: sudo ./rustdesk --password "MySecurePass123"
# On Windows (run as admin): rustdesk.exe --password "MySecurePass123"
./rustdesk --password "MySecurePass123"
# Output: Done!

# Start the service (so caregiver can connect)
./rustdesk --service
```

### Caregiver Side: Connect to Elder

```bash
# Connect with password
./rustdesk --connect 123456789 --password "MySecurePass123"

# Connect with relay (your server)
./rustdesk --connect 123456789 --password "MySecurePass123" --relay

# Port forwarding (if needed)
./rustdesk --port-forward 123456789:8080:22:localhost
```

### Config File Locations

| Platform | Config Path |
|----------|-------------|
| Windows | `%APPDATA%\RustDesk\config\RustDesk.toml` |
| macOS | `~/Library/Application Support/RustDesk/config/RustDesk.toml` |
| Linux | `~/.config/rustdesk/RustDesk.toml` |

---

## 10. Electron Integration Code

### Elder App (Node.js/Electron)

```javascript
// elder-rustdesk.js
const { execSync, spawn } = require('child_process');
const path = require('path');
const os = require('os');

class ElderRustDesk {
    constructor(apiBaseUrl) {
        this.apiBaseUrl = apiBaseUrl;
        this.rustdeskPath = this.getRustDeskPath();
    }

    getRustDeskPath() {
        // Path to bundled RustDesk CLI in your Electron app
        const platform = os.platform();
        if (platform === 'win32') {
            return path.join(process.resourcesPath, 'rustdesk', 'rustdesk.exe');
        } else if (platform === 'darwin') {
            return path.join(process.resourcesPath, 'rustdesk', 'rustdesk');
        } else {
            return path.join(process.resourcesPath, 'rustdesk', 'rustdesk');
        }
    }

    // Get RustDesk ID (no admin required)
    getId() {
        try {
            const output = execSync(`"${this.rustdeskPath}" --get-id`, { 
                encoding: 'utf8',
                timeout: 5000 
            });
            return output.trim();
        } catch (error) {
            console.error('Failed to get RustDesk ID:', error);
            return null;
        }
    }

    // Set permanent password (requires admin - use electron-sudo or similar)
    async setPassword(password) {
        const sudo = require('sudo-prompt');
        const options = { name: 'CareDesk Setup' };
        
        return new Promise((resolve, reject) => {
            const command = `"${this.rustdeskPath}" --password "${password}"`;
            sudo.exec(command, options, (error, stdout, stderr) => {
                if (error) {
                    reject(error);
                } else {
                    resolve(stdout.includes('Done'));
                }
            });
        });
    }

    // Start RustDesk service in background
    startService() {
        const service = spawn(this.rustdeskPath, ['--service'], {
            detached: true,
            stdio: 'ignore'
        });
        service.unref();
        return service.pid;
    }

    // Register elder with your backend
    async registerWithBackend(elderInfo) {
        const rustdeskId = this.getId();
        if (!rustdeskId) {
            throw new Error('Could not get RustDesk ID');
        }

        // Generate a secure password
        const password = this.generatePassword();
        
        // Set the permanent password
        await this.setPassword(password);

        // Register with your backend
        const response = await fetch(`${this.apiBaseUrl}/api/elder/register`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                ...elderInfo,
                rustdesk_id: rustdeskId,
                rustdesk_password: password  // Encrypt this in production!
            })
        });

        const data = await response.json();
        
        // Start the service
        this.startService();

        return {
            elderId: data.elder_id,
            rustdeskId: rustdeskId,
            pairingPin: data.pairing_pin
        };
    }

    generatePassword(length = 16) {
        const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789!@#$%';
        let password = '';
        for (let i = 0; i < length; i++) {
            password += chars.charAt(Math.floor(Math.random() * chars.length));
        }
        return password;
    }
}

module.exports = ElderRustDesk;
```

### Caregiver App (Node.js/Electron)

```javascript
// caregiver-rustdesk.js
const { spawn } = require('child_process');
const path = require('path');
const os = require('os');

class CaregiverRustDesk {
    constructor(apiBaseUrl, authToken) {
        this.apiBaseUrl = apiBaseUrl;
        this.authToken = authToken;
        this.rustdeskPath = this.getRustDeskPath();
        this.currentSession = null;
    }

    getRustDeskPath() {
        const platform = os.platform();
        if (platform === 'win32') {
            return path.join(process.resourcesPath, 'rustdesk', 'rustdesk.exe');
        } else if (platform === 'darwin') {
            return path.join(process.resourcesPath, 'rustdesk', 'rustdesk');
        } else {
            return path.join(process.resourcesPath, 'rustdesk', 'rustdesk');
        }
    }

    // Pair with elder using PIN
    async pairWithElder(pin) {
        const response = await fetch(`${this.apiBaseUrl}/api/caregiver/pair`, {
            method: 'POST',
            headers: { 
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${this.authToken}`
            },
            body: JSON.stringify({ pin })
        });

        if (!response.ok) {
            throw new Error('Invalid or expired PIN');
        }

        return await response.json(); // { elder_id, elder_name, ... }
    }

    // Connect to elder's desktop
    async connectToElder(elderId) {
        // 1. Get connection credentials from backend
        const response = await fetch(`${this.apiBaseUrl}/api/connection/request`, {
            method: 'POST',
            headers: { 
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${this.authToken}`
            },
            body: JSON.stringify({ elder_id: elderId })
        });

        if (!response.ok) {
            throw new Error('Not authorized to connect to this elder');
        }

        const { rustdesk_id, password, session_id } = await response.json();

        // 2. Launch RustDesk connection
        this.currentSession = spawn(this.rustdeskPath, [
            '--connect', rustdesk_id,
            '--password', password
        ]);

        // 3. Log session start
        this.logSessionStart(session_id);

        // 4. Handle session end
        this.currentSession.on('close', (code) => {
            this.logSessionEnd(session_id);
            this.currentSession = null;
        });

        return session_id;
    }

    async logSessionStart(sessionId) {
        await fetch(`${this.apiBaseUrl}/api/connection/log`, {
            method: 'POST',
            headers: { 
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${this.authToken}`
            },
            body: JSON.stringify({ 
                session_id: sessionId, 
                event: 'start' 
            })
        });
    }

    async logSessionEnd(sessionId) {
        await fetch(`${this.apiBaseUrl}/api/connection/log`, {
            method: 'POST',
            headers: { 
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${this.authToken}`
            },
            body: JSON.stringify({ 
                session_id: sessionId, 
                event: 'end' 
            })
        });
    }

    disconnect() {
        if (this.currentSession) {
            this.currentSession.kill();
            this.currentSession = null;
        }
    }
}

module.exports = CaregiverRustDesk;
```

### Usage in Electron Main Process

```javascript
// main.js (Electron main process)
const { app, BrowserWindow, ipcMain } = require('electron');
const ElderRustDesk = require('./elder-rustdesk');
const CaregiverRustDesk = require('./caregiver-rustdesk');

const API_URL = 'https://api.yourapp.com';

// Elder registration
ipcMain.handle('elder:register', async (event, elderInfo) => {
    const elder = new ElderRustDesk(API_URL);
    return await elder.registerWithBackend(elderInfo);
});

// Caregiver pairing
ipcMain.handle('caregiver:pair', async (event, { pin, authToken }) => {
    const caregiver = new CaregiverRustDesk(API_URL, authToken);
    return await caregiver.pairWithElder(pin);
});

// Caregiver connect
ipcMain.handle('caregiver:connect', async (event, { elderId, authToken }) => {
    const caregiver = new CaregiverRustDesk(API_URL, authToken);
    return await caregiver.connectToElder(elderId);
});
```

---

## 11. Packaging RustDesk with Electron

### Directory Structure

```
your-electron-app/
├── src/
├── resources/
│   └── rustdesk/
│       ├── rustdesk.exe          # Windows binary
│       ├── rustdesk              # macOS/Linux binary
│       └── sciter.dll            # Windows: Sciter library (if using legacy UI)
├── package.json
└── electron-builder.yml
```

### electron-builder.yml

```yaml
appId: com.yourcompany.caredesk
productName: CareDesk

files:
  - "**/*"
  - "!**/node_modules/*/{CHANGELOG.md,README.md,README,readme.md,readme}"

extraResources:
  - from: "resources/rustdesk"
    to: "rustdesk"
    filter:
      - "**/*"

mac:
  target: dmg
  extraResources:
    - from: "resources/rustdesk/rustdesk-mac"
      to: "rustdesk/rustdesk"

win:
  target: nsis
  extraResources:
    - from: "resources/rustdesk/rustdesk.exe"
      to: "rustdesk/rustdesk.exe"
```

### Building RustDesk Binaries

```bash
# Build for current platform
cd Customdesk
cargo build --release --features cli

# Copy to your Electron resources
# Windows
cp target/release/rustdesk.exe ../your-electron-app/resources/rustdesk/

# macOS  
cp target/release/rustdesk ../your-electron-app/resources/rustdesk/

# Linux
cp target/release/rustdesk ../your-electron-app/resources/rustdesk/
```

---

## 12. Next Steps

1. **Build RustDesk CLI** - `cargo build --release --features cli`
2. **Test CLI commands** manually first
3. **Set up your backend API** with the endpoints
4. **Integrate into Electron** using the code above
5. **Test the full flow**: Elder register → Get PIN → Caregiver pair → Connect

---

## Questions to Answer

Before starting development:

1. **What platforms?** Windows only? Mac? Mobile?
2. **Existing backend?** What language/framework?
3. **User authentication?** Email? Phone? OAuth?
4. **Consent model?** Auto-accept? Approval each time?
5. **Billing?** Free? Subscription? Per-connection?

---

**Document Version:** 1.0  
**Created:** February 2026  
**Project:** CareDesk (Elder-Caregiver RDP Solution)
