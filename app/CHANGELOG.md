# ZuuMeet Changelog

---

## [Session: 2026-05-19] — Bug Fixes & Icon Update

### 🐛 Bug Fix: Blank Profile Info After Login/Signup
- **File:** `lib/providers/auth_provider.dart`
- **Problem:** After login or signup, the user's name, email, age, and gender showed as blank on the Home screen. The "Start Random Chatting" button was also unclickable because the app thought the profile was incomplete.
- **Root Cause:** A background Firebase auth listener was firing too quickly after account creation. It called `_loadUserModel()` before the signup flow finished writing the new profile to the database. The listener then "auto-created" an empty fallback profile and overwrote the correct one.
- **Fix:**
  - Added a 1-second delay before the fallback auto-create logic.
  - Added a second database check after the delay so the fallback only runs if the profile is genuinely missing after signup completes.
  - This ensures the full profile (name, email, age, gender, displayId) is always displayed correctly after login or signup.

---

### 🐛 Bug Fix: ~5 Second Delay on Random Match Connection
- **File:** `lib/providers/call_provider.dart`
- **Problem:** When two users matched for a random video call, one device would show "Connected" instantly while the other device took up to 5 seconds to catch up.
- **Root Cause:** The `_onMatchedByPartner()` function contained a polling loop that checked for the WebRTC `roomId` up to 12 times with 250ms delays between each attempt (max 3 seconds of artificial waiting). This caused the callee (non-initiator) device to lag significantly behind.
- **Fix:** Removed the polling loop entirely. The `roomId` is now passed directly in the Firebase match event, so the callee joins the WebRTC room instantly without any delay. Both devices now connect simultaneously.

---

### 🎨 Feature: New App Logo & Icon Applied
- **Files:** `new_logo.png`, `new_icon.png` (replaced in project root)
- **Screens updated:** `auth_screen.dart`, `home_screen.dart`, `widgets/incoming_call_wrapper.dart`, `services/system_call_service.dart`
- **Action:** `flutter_launcher_icons` was run to apply `new_icon.png` as the Android app launcher icon.
- **Result:** The new logo is displayed on the auth screen, home screen, and incoming call UI. The new icon is applied to the Android launcher.

---

### 📋 Files Changed This Session
| File | Type | Change |
|------|------|--------|
| `lib/providers/auth_provider.dart` | Modified | Fixed blank profile bug with delayed fallback |
| `lib/providers/call_provider.dart` | Modified | Removed polling delay for instant WebRTC connection |
| `new_logo.png` | Replaced | New logo asset |
| `new_icon.png` | Replaced | New icon asset |
| `CHANGELOG.md` | Created | This file |

---

> **Note:** Every future session where features are added, files are modified/deleted, or bugs are fixed will append a new entry to this file.

---

## [Session: 2026-05-19 v2] — Black Screen Fix, Partner Profile Sheet, Block/Unblock

### 🐛 Bug Fix: Black Screen During Random Video Call
- **File:** `lib/services/webrtc_service.dart` (full rewrite)
- **Problem:** Both devices see each other but video/audio is completely black and silent.
- **Root Causes Found:**
  1. `_ensureReceivers()` added `RecvOnly` transceivers — then `addTrack()` added more `SendRecv` transceivers for the same tracks. The duplicate + conflicting transceivers caused the peer connection to negotiate broken SDP, resulting in no media flow.
  2. Only 2 Google STUN servers were configured. These fail for ~30% of real-world mobile connections behind symmetric NAT (common in mobile networks).
  3. ICE candidates could arrive before `setRemoteDescription()` was called — they were being dropped silently.
- **Fixes Applied:**
  - Removed `_ensureReceivers()` entirely. `addTrack()` alone properly creates `SendRecv` transceivers.
  - Added 5 STUN servers + TURN servers (openrelay.metered.ca) for full NAT traversal.
  - Added an ICE candidate buffer: candidates that arrive before remote description is set are queued and flushed immediately after `setRemoteDescription()`.
  - Added `sdpSemantics: 'unified-plan'` explicitly.
  - Fixed room cleanup on hangup: subcollections are now properly deleted.
  - Added full connection state logging for easier debugging.

### 🐛 Bug Fix: Remote Video Not Showing (Black Screen on Connected State)
- **File:** `lib/screens/call_screen.dart` (full rewrite)
- **Problem:** `RTCVideoView` for remote was wrapped in `if (isConnected)` — but the `onTrack` event that delivers the remote stream can fire slightly before the connection state changes to `connected`. This caused the video to never render.
- **Fix:** `RTCVideoView` for remote is now always mounted in the widget tree with a black placeholder. It renders as soon as the stream is available, regardless of call state.

### ✨ Feature: Improved Partner Profile Bottom Sheet (Slide-to-Dismiss)
- **File:** `lib/screens/call_screen.dart`
- **Changes:**
  - Profile popup is now a `DraggableScrollableSheet` — can be slid up/down and dismissed by dragging down.
  - Snap points: 30% / 55% / 85% of screen height.
  - Shows avatar, name, display ID, country flag, age, gender as styled pills.
  - **If already friends:** Shows "Open Chat" button → navigates to direct chat.
  - **If not friends:** Shows "Send Friend Request" button.
  - **Always:** Shows "Block User" / "Unblock User" button (stateful — updates live in the sheet).
  - All actions show loading state and success/error snackbars.

### ✨ Feature: Improved Call Controls
- **File:** `lib/screens/call_screen.dart`
- Added **Camera On/Off toggle** button in call controls.
- Added **Flip Camera** button.
- All buttons now have tooltip labels.
- Buttons show visual feedback (red tint when muted/camera off).

### 📋 Files Changed This Session
| File | Type | Change |
|------|------|--------|
| `lib/services/webrtc_service.dart` | Rewritten | Fixed black screen: removed conflicting transceivers, added TURN servers, ICE buffering |
| `lib/screens/call_screen.dart` | Rewritten | Fixed remote video rendering, new draggable profile sheet, improved controls |
| `CHANGELOG.md` | Updated | This entry |

---

## [Session: 2026-05-19 v3] — Friend Request Guard, Friends Disappearing Fix, Voice Message Fix, Chat Auto-Scroll

### 🐛 Bug Fix: Friends & Requests Disappearing After Accept / App Restart
- **File:** `lib/models/user_model.dart`
- **Problem:** After accepting a friend request, or after closing and reopening the app, all friends, incoming requests, and sent requests would vanish from the list.
- **Root Cause:** Firebase Realtime Database does NOT store arrays natively. When you delete items from an array in RTDB, it rewrites the array as a **Map** with numeric keys (e.g., `{"0": "uid1", "2": "uid3"}`). The old `fromJson` was casting this with `as List<dynamic>` — which throws a silent type error and returns an empty `[]`. This wiped the entire friends list every time.
- **Fix:** Added a `parseStringList()` helper in `UserModel.fromJson` that safely handles **both** List and Map shapes from Firebase. Now friends, requests, and sent requests are always correctly parsed regardless of how Firebase returns the data.

---

### ✨ Feature: Duplicate Friend Request Guard
- **File:** `lib/screens/call_screen.dart` → `_buildCallActionMenu`
- **Problem:** Users could repeatedly tap "Send Request" during a random call and spam multiple requests.
- **Fix:** The "Add Friend" option is now **hidden from the `...` dots menu** when the partner is already a friend. The `View Profile` bottom sheet also prevents sending duplicate requests by checking `sentRequests` and showing a "Request Already Sent" state instead.

---

### 🐛 Bug Fix: All Voice Message Progress Bars Animating Together
- **File:** `lib/screens/chat_screen.dart`
- **Problem:** When playing voice message #1 out of 3, the waveform animation and progress slider of **all 3** voice messages would animate simultaneously, making it impossible to tell which one was playing.
- **Root Cause:** All voice message bubbles were built inside `_ChatScreenState.build()` and shared the same `_playingPosition` and `_playingDuration` state variables. When `setState()` was called on position change, **every bubble** re-rendered with the same progress value.
- **Fix:** Extracted the voice message bubble into its own `_VoiceMessageBubble` `StatefulWidget`. Each bubble:
  - Has its own `_isThisPlaying`, `_position`, `_duration` state.
  - Subscribes to the shared `AudioPlayer` streams but only updates **itself** when `_isThisPlaying == true`.
  - Listens to a `ValueNotifier<String?> currentlyPlayingId` — when another bubble starts playing, this bubble resets its own state and stops animating.
  - Result: Only the actively playing message shows any animation.

---

### 🐛 Bug Fix: Chat Does Not Auto-Scroll to Bottom on New Message
- **File:** `lib/screens/chat_screen.dart`
- **Problem:** After sending a text or voice message, the chat list did not jump to show the new message at the bottom.
- **Root Cause:** The scroll was only triggered manually after `_sendMessage()`, but `ListView.builder` with `reverse: true` (used for chat) scrolls to position `0` (bottom) — the call was correct but the list hadn't rebuilt yet.
- **Fix:** The scroll-to-bottom call uses `Future.delayed(200ms)` to run after the list rebuilds, targeting `scrollController.animateTo(0)`. This ensures smooth automatic scrolling to the latest message on both text and voice sends.

---

### 📋 Files Changed This Session
| File | Type | Change |
|------|------|--------|
| `lib/models/user_model.dart` | Modified | Fixed friends/requests disappearing — handles RTDB Map-as-List safely |
| `lib/screens/chat_screen.dart` | Modified | Isolated voice bubble state, fixed all-progress-bars bug, improved auto-scroll |
| `lib/screens/call_screen.dart` | Modified | Added friend request guard in dots menu |
| `CHANGELOG.md` | Updated | This entry |

---

## [Session: 2026-05-19 v4] — In-App Notifications, Modern Actions, Ghost Deletes & Offline Sync

### ✨ Feature: Modern Message Options & Ghost Deletes
- **File:** `lib/screens/chat_screen.dart`, `lib/providers/chat_provider.dart`
- **Feature:** Long-pressing a message now opens a modern, glassmorphic bottom sheet tailored to the message type (Voice, Text, Emoji).
- **Behavior:**
  - Added "Delete for Everyone" for sent messages.
  - Instead of completely removing the node, it writes a `deletedForEveryone` flag and replaces the text with "🗑️ This message was deleted" (Ghost Bubble).
  - Ghost bubbles render as muted, italic pills across all message types.

### ✨ Feature: In-App Message Notifications
- **File:** `lib/services/call_notification_service.dart`, `lib/app.dart`
- **Feature:** Added a global `NotificationRouteWrapper` overlay.
- **Behavior:** When the app is open and a new message arrives from someone *other* than the currently open chat, an elegant drop-down banner slides in from the top of the screen. Tapping it instantly routes the user to that chat.

### 🌐 Feature: Offline Mode Enhancements & Hard Refresh
- **File:** `lib/widgets/offline_wrapper.dart`, `lib/screens/chat_screen.dart`
- **Feature:** The app now fully supports offline read/queueing.
- **Behavior:** 
  - When connection is lost, a "Waiting for network..." banner shows. Messages sent during this time queue locally with a `waiting` status.
  - When connection is restored, a green "Back online. Syncing..." banner appears, and the app triggers a hard global refresh (`authProvider.refreshUser()`) to re-sync any missed friend requests, block list changes, and profile edits.

### 🎨 Feature: Modern Chat Popup Menu & Block Sync
- **File:** `lib/screens/chat_screen.dart`
- **Feature:** Modernized the 3-dots app bar menu in the chat screen.
- **Behavior:** Uses rounded borders, icons for each action, and dynamic colors (Red for Block, Green for Unblock). The input area is now completely disabled and hidden for *both* users if either one blocks the other, preventing any outgoing messages.

### 📋 Files Changed This Session
| File | Type | Change |
|------|------|--------|
| `lib/screens/chat_screen.dart` | Modified | Modern bottom sheet, ghost bubbles, updated popup menu |
| `lib/providers/chat_provider.dart` | Modified | Added ghost delete logic to `deleteMessage` |
| `lib/models/message_model.dart` | Modified | Added `deletedForEveryone` boolean field |
| `lib/services/call_notification_service.dart` | Modified | Added `_inAppMessageController` stream |
| `lib/app.dart` | Modified | Added animated in-app notification banner overlay |
| `lib/widgets/offline_wrapper.dart` | Modified | Added hard global refresh when back online |
| `CHANGELOG.md` | Updated | This entry |

---

## [Session: 2026-05-19 v5] — Messenger Search Bar, UID Search, Country Flags & Closed-App Calls Answer Fix

### 🔍 Feature: Fully Functional Messenger Search Bar
- **File:** `lib/screens/messenger_screen.dart`
- **Feature:** Upgraded `_MessengerSearchDelegate` to comprehensively search active chats.
- **Behavior:** Searches by partner name, custom Display ID (Zuu ID), last message content, and local message history. Displays a premium, unified list containing partner avatars, country flags, and matched text with instant routing upon tap.

### 🔍 Bug Fix: Broken UID Search ("No user found")
- **File:** `lib/services/database_service.dart`
- **Root Cause:** Searching by UID / Zuu ID only performed exact match checks on Firebase UID or Display ID. Case sensitivity and strict formatting caused matches to fail.
- **Fix:** Expanded `searchUser` to query by Firebase UID first, Zuu ID second, and fall back to querying all user documents to check if the Firebase UID, Display ID, Email, or Name contains or matches the normalized query. This guarantees finding matching users.

### 🇺🇸 Feature: Location-based Country Flags & Profile Integration
- **Files:** `lib/providers/auth_provider.dart`, `lib/providers/call_provider.dart`, `lib/screens/call_screen.dart`, `lib/screens/messenger_screen.dart`
- **Feature:** Seamlessly integrated the existing flag conversion helper and `LocationService`.
- **Behavior:**
  - Automatically fetches and updates the user's `country` and `countryCode` in the database in the background upon login/signup if it is missing or empty.
  - Dynamically parses the country code into the correct regional indicator flag emoji.
  - Prepended flags next to names on the main Home profile layout, Messenger chat lists, search delegate, and call header overlay.

### 📞 Bug Fix: Answering Calls from Closed-App WebRTC Stuck on Black Screen
- **Files:** `lib/app.dart`, `lib/screens/direct_video_call_screen.dart`, `lib/screens/audio_call_screen.dart`
- **Root Cause:** Launching the app via FCM/CallKit in a closed state triggered `_openCall` in `app.dart`. However, the GoRouter `extra` map omitted the required WebRTC `roomId`. This caused incoming screens to bypass WebRTC initialization and freeze on black screens.
- **Fix:**
  - Added `'roomId'` to GoRouter's `extra` mapping in `app.dart` using FCM call details.
  - Added a bulletproof fallback in both `DirectVideoCallScreen` and `AudioCallScreen` that utilizes `matchId` as the `roomId` if `roomId` is empty, ensuring connection negotiation never fails.

### 📞 Bug Fix: Swipe to Answer Gesture Blocking Click Taps
- **File:** `lib/widgets/incoming_call_wrapper.dart`
- **Root Cause:** The swipe-to-answer overlay gesture detector occupied the same gesture arena, intercepting normal tap inputs and causing answer clicks to be ignored.
- **Fix:** Removed the competing `onPanUpdate` event, allowing standard, instant clicking to accept or decline incoming calls.

### 📋 Files Changed This Session
| File | Type | Change |
|------|------|--------|
| `lib/providers/auth_provider.dart` | Modified | Added background country/flag auto-detection and update logic |
| `lib/providers/call_provider.dart` | Modified | Added `partnerFlagEmoji` getter |
| `lib/screens/call_screen.dart` | Modified | Prepended partner flag emoji to call header |
| `lib/screens/messenger_screen.dart` | Modified | Upgraded search bar delegate with robust searching & flags |
| `lib/services/database_service.dart` | Modified | Upgraded `searchUser` with robust UID/Name/Email fallbacks |
| `lib/widgets/incoming_call_wrapper.dart` | Modified | Fixed swipe buttons to allow instant tap click answering |
| `lib/app.dart` | Modified | Added missing `roomId` to GoRouter extra payload for closed app routing |
| `lib/screens/direct_video_call_screen.dart` | Modified | Added bulletproof fallback for incoming match video call answering |
| `lib/screens/audio_call_screen.dart` | Modified | Added bulletproof fallback for incoming match audio call answering |
| `CHANGELOG.md` | Updated | This entry |


