# CareDesk MVP — RustDesk Integration into Existing App

## Goal

Integrate the Customdesk (RustDesk fork) binary into the **existing** Electron desktop app and NestJS backend to enable caregiver → elder remote desktop connections. No new backend. No new client. No Supabase. We wire RustDesk into what we already have.

---

## What Already Works (DO NOT Rebuild)

| Layer | What's Done |
|-------|-------------|
| **Backend — Auth** | JWT login/register, OTP email verification, role-based guards (`ELDER` / `CAREGIVER`) |
| **Backend — Pairing** | 8-digit PIN (bcrypt-hashed, prefix-indexed), optimistic locking, `autoAccept` toggle |
| **Backend — Presence** | In-memory user online/offline tracking via `PresenceService` |
| **Backend — Users** | CRUD, role enforcement, `User` model with `ELDER`/`CAREGIVER` enum |
| **Desktop — Auth UI** | Role selection → Signup → OTP verification → Login → Dashboard |
| **Desktop — Elder** | PIN generation screen, "CONNECTED/NOT CONNECTED" dashboard |
| **Desktop — Caregiver** | Paired elder list table, "Add User" modal (PIN entry), search, tabs |
| **Database** | PostgreSQL via Prisma 7 — `User` and `Pairing` models with proper migrations |

---

## What We're Dropping

| Item | Why |
|------|-----|
| `backend/src/rdp/` module (gateway + service) | Custom video-frame-relay over Socket.IO. Not scalable, not performant. RustDesk handles the actual P2P connection. |
| Any Supabase/Firebase plan | We already have a NestJS backend + PostgreSQL |
| Any Python CLI plan | We already have an Electron app with full auth/pairing UI |

---

## Architecture (MVP)

```
┌─────────────────────────┐                           ┌─────────────────────────┐
│   Elder's Desktop App   │                           │  Caregiver's Desktop App│
│   (Electron + React)    │                           │  (Electron + React)     │
│                         │                           │                         │
│  ┌───────────────────┐  │                           │  ┌───────────────────┐  │
│  │ Renderer (React)  │  │                           │  │ Renderer (React)  │  │
│  │  - Auth UI ✅     │  │                           │  │  - Auth UI ✅     │  │
│  │  - Pairing UI ✅  │  │                           │  │  - Pairing UI ✅  │  │
│  │  - Dashboard ✅   │  │                           │  │  - Dashboard ✅   │  │
│  │  - Connect btn 🔨 │  │                           │  │  - Connect btn 🔨 │  │
│  └────────┬──────────┘  │                           │  └────────┬──────────┘  │
│           │ IPC 🔨      │                           │           │ IPC 🔨      │
│  ┌────────▼──────────┐  │                           │  ┌────────▼──────────┐  │
│  │ Main Process      │  │                           │  │ Main Process      │  │
│  │  - RustDesk mgr 🔨│  │                           │  │  - RustDesk mgr 🔨│  │
│  │  - Binary spawn   │  │                           │  │  - Binary spawn   │  │
│  └────────┬──────────┘  │                           │  └────────┬──────────┘  │
│           │              │                           │           │              │
│  ┌────────▼──────────┐  │    RustDesk P2P / Relay   │  ┌────────▼──────────┐  │
│  │  rustdesk binary  │◄─┼───────────────────────────┼──►  rustdesk binary  │  │
│  │  (--service mode) │  │   (public relay or self-   │  │  (--connect mode) │  │
│  └───────────────────┘  │    hosted hbbs/hbbr)       │  └───────────────────┘  │
└─────────────┬───────────┘                           └─────────────┬───────────┘
              │                                                     │
              │          ┌───────────────────────────┐              │
              └──────────►   NestJS Backend (API)    ◄──────────────┘
                         │                           │
                         │  - Auth (JWT) ✅          │
                         │  - Pairing (PIN) ✅       │
                         │  - Presence ✅            │
                         │  - RustDesk creds 🔨      │
                         │  - Connection logs 🔨     │
                         │                           │
                         └─────────┬─────────────────┘
                                   │
                         ┌─────────▼─────────────────┐
                         │   PostgreSQL (Prisma 7)   │
                         │   - users ✅              │
                         │   - pairings ✅           │
                         │   + rustdesk fields 🔨    │
                         │   + connection_logs 🔨    │
                         └───────────────────────────┘

✅ = exists     🔨 = build now
```

---

## What We Build (8 Tasks)

### Task 1 — Build Customdesk Binary for macOS

**Where:** `Customdesk/`
**Time:** 30 min

```bash
cd /Users/taahabz/Projects/Work/softaims/GiGi/Customdesk

# Install deps (if not already)
brew install nasm cmake gcc

# Build release binary
cargo build --release

# Binary lands at:
# target/release/rustdesk

# Verify
./target/release/rustdesk --get-id
./target/release/rustdesk --help
```

Key CLI commands we use:

| Command | Side | Purpose |
|---------|------|---------|
| `rustdesk --get-id` | Elder | Get machine's RustDesk ID |
| `rustdesk --password "xxx"` | Elder | Set permanent password |
| `rustdesk --service` | Elder | Run as background service |
| `rustdesk --connect <ID>` | Caregiver | Connect to elder's desktop |

---

### Task 2 — Add RustDesk Fields to Prisma Schema

**Where:** `backend/prisma/schema.prisma`
**Time:** 15 min

Add RustDesk credential fields to the existing `User` model:

```prisma
model User {
  id           String   @id @default(cuid())
  email        String   @unique
  passwordHash String
  role         Role     @default(ELDER)
  createdAt    DateTime @default(now())
  updatedAt    DateTime @updatedAt

  // RustDesk integration (elder only)
  rustdeskId       String?   @unique  // e.g. "482910375"
  rustdeskPassword String?            // encrypted permanent password

  // Relations
  caregiverPairings Pairing[] @relation("CaregiverPairings")
  elderPairings     Pairing[] @relation("ElderPairings")

  @@map("users")
}
```

Add a `ConnectionLog` model:

```prisma
model ConnectionLog {
  id         String    @id @default(cuid())
  pairingId  String
  pairing    Pairing   @relation(fields: [pairingId], references: [id], onDelete: Cascade)
  startedAt  DateTime  @default(now())
  endedAt    DateTime?

  @@index([pairingId])
  @@map("connection_logs")
}
```

Update `Pairing` to include the relation:

```prisma
model Pairing {
  // ... existing fields ...
  connectionLogs ConnectionLog[]
}
```

Run migration:
```bash
cd backend
npx prisma migrate dev --name add-rustdesk-fields
```

---

### Task 3 — Backend: RustDesk Credential Endpoints

**Where:** `backend/src/users/` (extend existing module)
**Time:** 30 min

Add two endpoints to the existing Users controller:

#### `PATCH /api/users/rustdesk-credentials` (JWT, ELDER only)
- Elder's app calls this after first-time RustDesk setup
- Body: `{ rustdeskId: string, rustdeskPassword: string }`
- Stores credentials on the authenticated user's record
- The `rustdeskPassword` should be encrypted before storage (use `bcrypt` or AES — not plain text)

#### `GET /api/users/elder-credentials/:elderId` (JWT, CAREGIVER only)
- Caregiver requests a specific elder's RustDesk credentials to connect
- Validates that an active pairing exists between this caregiver and the elder
- Returns `{ rustdeskId, rustdeskPassword }` (decrypted)
- Creates a `ConnectionLog` entry

These are the **only new endpoints**. Everything else (auth, pairing, user CRUD) stays as-is.

---

### Task 4 — Backend: Delete the RDP Module

**Where:** `backend/src/rdp/`
**Time:** 5 min

Remove these files entirely:
- `rdp.gateway.ts`
- `rdp.module.ts`
- `rdp.service.ts`

Remove `RdpModule` from imports in `app.module.ts`.

The custom video-frame-relay gateway is replaced by RustDesk's native P2P protocol.

---

### Task 5 — Desktop: IPC Bridge (Preload Script)

**Where:** `desktop/src/preload.js`
**Time:** 30 min

The preload script is currently **empty**. We need to expose RustDesk operations to the renderer:

```js
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('rustdesk', {
  // Get this machine's RustDesk ID
  getId: () => ipcRenderer.invoke('rustdesk:get-id'),

  // Set permanent password for remote access
  setPassword: (password) => ipcRenderer.invoke('rustdesk:set-password', password),

  // Start RustDesk service (elder background mode)
  startService: () => ipcRenderer.invoke('rustdesk:start-service'),

  // Stop RustDesk service
  stopService: () => ipcRenderer.invoke('rustdesk:stop-service'),

  // Connect to a remote machine (caregiver → elder)
  connect: (rustdeskId) => ipcRenderer.invoke('rustdesk:connect', rustdeskId),

  // Check if RustDesk binary exists
  isAvailable: () => ipcRenderer.invoke('rustdesk:is-available'),

  // Check if service is running
  isServiceRunning: () => ipcRenderer.invoke('rustdesk:is-service-running'),
});
```

---

### Task 6 — Desktop: RustDesk Manager (Main Process)

**Where:** `desktop/src/main.js` (or new `desktop/src/rustdesk/rustdesk.manager.js`)
**Time:** 1 hr

Handle IPC calls in the main process by spawning the bundled RustDesk binary:

```js
import { ipcMain } from 'electron';
import { execFile, spawn } from 'child_process';
import path from 'path';
import fs from 'fs';

// Path to bundled RustDesk binary
const RUSTDESK_BIN = path.join(__dirname, '..', 'bin', 'rustdesk');

let serviceProcess = null;

export function registerRustdeskIPC() {

  ipcMain.handle('rustdesk:is-available', async () => {
    return fs.existsSync(RUSTDESK_BIN);
  });

  ipcMain.handle('rustdesk:get-id', async () => {
    return new Promise((resolve, reject) => {
      execFile(RUSTDESK_BIN, ['--get-id'], { timeout: 10000 }, (err, stdout) => {
        if (err) return reject(err);
        resolve(stdout.trim());
      });
    });
  });

  ipcMain.handle('rustdesk:set-password', async (_event, password) => {
    return new Promise((resolve, reject) => {
      execFile(RUSTDESK_BIN, ['--password', password], { timeout: 15000 }, (err) => {
        if (err) return reject(err);
        resolve(true);
      });
    });
  });

  ipcMain.handle('rustdesk:start-service', async () => {
    if (serviceProcess) return true; // already running
    serviceProcess = spawn(RUSTDESK_BIN, ['--service'], {
      detached: true,
      stdio: 'ignore',
    });
    serviceProcess.unref();
    return true;
  });

  ipcMain.handle('rustdesk:stop-service', async () => {
    if (serviceProcess) {
      serviceProcess.kill();
      serviceProcess = null;
    }
    return true;
  });

  ipcMain.handle('rustdesk:connect', async (_event, rustdeskId) => {
    return new Promise((resolve, reject) => {
      const proc = spawn(RUSTDESK_BIN, ['--connect', rustdeskId]);
      proc.on('close', (code) => resolve(code));
      proc.on('error', (err) => reject(err));
    });
  });

  ipcMain.handle('rustdesk:is-service-running', async () => {
    return serviceProcess !== null && !serviceProcess.killed;
  });
}
```

Call `registerRustdeskIPC()` in `main.js` inside `app.whenReady()`.

**Binary bundling:** Copy the compiled `Customdesk/target/release/rustdesk` binary to `desktop/bin/rustdesk`. Add `bin/` to the Electron Forge package config's `extraResource` or `asar.unpack` so it ships with the app.

---

### Task 7 — Desktop: Elder Auto-Setup Flow

**Where:** `desktop/src/components/elder/ElderDashboard.jsx`
**Time:** 45 min

When an Elder logs in and lands on their dashboard:

1. **Check** if they already have `rustdeskId` stored (call `GET /api/users/me` — already exists)
2. **If no `rustdeskId`** → run first-time setup:
   - Call `window.rustdesk.isAvailable()` → error if binary missing
   - Call `window.rustdesk.getId()` → get this machine's RustDesk ID
   - Generate a random 16-char password client-side
   - Call `window.rustdesk.setPassword(password)` → set it on the binary
   - Call `window.rustdesk.startService()` → start background service
   - Call `PATCH /api/users/rustdesk-credentials` with `{ rustdeskId, rustdeskPassword }`
   - Show success: "Your device is ready for remote assistance"
3. **If already has `rustdeskId`** → just ensure service is running:
   - Call `window.rustdesk.startService()`
   - Show: "CONNECTED SUCCESSFULLY" (existing UI)

**macOS Permissions Note:** The first `startService()` call will trigger macOS prompts for Accessibility and Screen Recording. Show a helper message guiding the elder through this.

---

### Task 8 — Desktop: Caregiver "Remote Control" Button

**Where:** `desktop/src/components/caregiver/CaregiverDashboard.jsx`
**Time:** 30 min

The "Remote Control" button already exists in the table rows but has **no click handler**. Wire it up:

1. On click → call `GET /api/users/elder-credentials/:elderId` (new endpoint from Task 3)
2. Receive `{ rustdeskId, rustdeskPassword }`
3. Call `window.rustdesk.connect(rustdeskId)`
4. RustDesk opens its native remote desktop window
5. Show a "Connecting to [elder name]..." status while spawning

The password can be passed via RustDesk's `--password` flag or injected into the config file at `~/Library/Application Support/RustDesk/config/RustDesk.toml` before connecting.

---

## Full Flow (End to End)

### Setup (One Time)

```
Elder                              Backend                          Caregiver
  │                                   │                                │
  │── Register (signup + OTP) ───────►│                                │
  │◄── JWT token ─────────────────────│                                │
  │                                   │                                │
  │── Generate PIN ──────────────────►│                                │
  │◄── 8-digit PIN ──────────────────│                                │
  │                                   │                                │
  │         (elder tells caregiver    │                                │
  │          the PIN by phone/text)   │                                │
  │                                   │                                │
  │                                   │◄── Register (signup + OTP) ───│
  │                                   │── JWT token ──────────────────►│
  │                                   │                                │
  │                                   │◄── Pair with PIN ─────────────│
  │                                   │── Success ───────────────────►│
  │                                   │                                │
  │── RustDesk auto-setup ──────────►│                                │
  │   (getId + setPassword + store)  │                                │
  │◄── Stored ────────────────────────│                                │
  │                                   │                                │
```

### Connection (Every Time)

```
Caregiver                          Backend                          Elder
  │                                   │                                │
  │── Click "Remote Control" ────────►│                                │
  │   GET /users/elder-credentials    │                                │
  │◄── { rustdeskId, password } ──────│                                │
  │                                   │                                │
  │── rustdesk --connect <id> ────────┼──── P2P / Relay ──────────────►│
  │   (RustDesk handles the rest)     │   (rustdesk --service is       │
  │                                   │    already running on elder)   │
  │◄══════════ Remote Desktop Session ═══════════════════════════════►│
  │                                   │                                │
```

---

## macOS-Specific Notes

### Permissions (Elder Only)

RustDesk on macOS requires these one-time permissions:
- **Accessibility** — System Settings → Privacy & Security → Accessibility
- **Screen Recording** — System Settings → Privacy & Security → Screen Recording

The elder's app should display a guided prompt on first setup explaining how to grant these.

### Binary Location

```
desktop/
├── bin/
│   └── rustdesk          ← compiled Customdesk binary (copied from Customdesk/target/release/)
├── src/
│   └── ...
```

In production packaging, use Electron Forge's `extraResource` to bundle:

```js
// forge.config.js
packagerConfig: {
  extraResource: ['./bin/rustdesk'],
}
```

### Config File Location

```
~/Library/Application Support/RustDesk/config/RustDesk.toml
```

---

## What We're NOT Doing (Deferred)

| Deferred Item | Why |
|---------------|-----|
| Self-hosted relay server (hbbs/hbbr) | Public relays work for MVP. Deploy later for reliability. |
| Video calling (WebRTC) | RustDesk handles the visual connection. Separate video call is Phase 2. |
| Watch-Together (Netflix) | Phase 2 feature. |
| Session recording | Not needed for MVP |
| Socket.IO presence (live online/offline) | Presence service exists but isn't wired to the desktop. Phase 2. |
| Windows/Linux builds | macOS first. Same architecture works cross-platform. |
| Password encryption at rest | Store rustdeskPassword with AES encryption in Phase 2. Bcrypt is one-way so not suitable here. |
| Flutter mobile app | Desktop MVP first. |
| Elder consent prompt per-session | `autoAccept` field exists on Pairing. Wire up consent UI in Phase 2. |

---

## File Changes Summary

### Backend

| File | Action |
|------|--------|
| `prisma/schema.prisma` | Add `rustdeskId`, `rustdeskPassword` to `User`. Add `ConnectionLog` model. |
| `src/users/users.controller.ts` | Add `PATCH /rustdesk-credentials`, `GET /elder-credentials/:elderId` |
| `src/users/users.service.ts` | Add `updateRustdeskCredentials()`, `getElderCredentials()` |
| `src/rdp/rdp.gateway.ts` | **DELETE** |
| `src/rdp/rdp.service.ts` | **DELETE** |
| `src/rdp/rdp.module.ts` | **DELETE** |
| `src/app.module.ts` | Remove `RdpModule` import |

### Desktop

| File | Action |
|------|--------|
| `src/preload.js` | Implement `contextBridge` with `rustdesk` API |
| `src/main.js` | Add `registerRustdeskIPC()` — spawn/manage RustDesk binary |
| `src/components/elder/ElderDashboard.jsx` | Add auto-setup flow (getId → setPassword → startService → POST creds) |
| `src/components/caregiver/CaregiverDashboard.jsx` | Wire "Remote Control" button (fetch creds → `rustdesk --connect`) |
| `bin/rustdesk` | Bundled binary (copied from `Customdesk/target/release/rustdesk`) |
| `forge.config.js` | Add `extraResource: ['./bin/rustdesk']` |

---

## Task Checklist

- [ ] `cargo build --release` compiles clean in `Customdesk/` on macOS
- [ ] `./target/release/rustdesk --get-id` returns an ID
- [ ] Prisma migration runs (`rustdeskId`, `rustdeskPassword`, `ConnectionLog`)
- [ ] `PATCH /api/users/rustdesk-credentials` works (test with curl/Postman)
- [ ] `GET /api/users/elder-credentials/:elderId` works (validates pairing)
- [ ] `backend/src/rdp/` is deleted, app still compiles
- [ ] `preload.js` exposes `window.rustdesk` API
- [ ] `main.js` handles all `rustdesk:*` IPC calls
- [ ] Elder login → auto-setup → RustDesk ID stored in backend
- [ ] Caregiver clicks "Remote Control" → RustDesk window opens to elder's screen
- [ ] macOS permissions (Accessibility + Screen Recording) granted on elder machine
- [ ] Connection log appears in database

---

**Version:** MVP 1.0
**Date:** February 9, 2026
**Target:** macOS, Electron desktop app, existing NestJS backend
**Estimated Time:** ~4 hours
**Goal:** Caregiver clicks "Remote Control" → sees elder's screen via RustDesk
