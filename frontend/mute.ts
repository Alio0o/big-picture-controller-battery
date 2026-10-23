// Mutes the game while the Steam overlay is open (see backend/audio.lua).
// Steam reports the overlay opening and closing together with the game's
// process id; the backend mutes that process in Windows' volume mixer.
import { onSettings, settings } from './config';
import { gameRunning } from './steam';
import { contextKind, subscribePopups } from './windows';

const REMUTE_MS = 2000; // a game can open a new audio stream while muted
const CHECK_MS = 1000;  // notices a game that quit while the overlay was open

let registration: { unregister?: () => void } | null = null;
let unsubscribeSettings: (() => void) | null = null;
let mutedPid = 0;
let muting = false;
let open = false;
let remute: number | null = null;
let check: number | null = null;
let unsubscribeWindows: (() => void) | null = null;

// Logs when the overlay window shows or hides, to compare with Steam's
// overlay event when the mute does not happen.
function watchOverlayWindow(context: any) {
	const doc: Document | undefined = context?.m_popup?.document;
	if (contextKind(context) !== 'overlay' || !doc || (doc as any).__couchModeWatched) return;
	(doc as any).__couchModeWatched = true;
	const report = () => console.log(`Couch Mode: overlay window ${doc.visibilityState}`);
	doc.addEventListener('visibilitychange', report);
	report();
}

function log(result: unknown) {
	if (typeof result === 'string' && result !== 'off' && !result.startsWith('muted 0 ')) console.log('Couch Mode game mute:', result);
}

function mute(pid: number) {
	mutedPid = pid;
	muting = true;
	backend.muteGame(pid)
		.then(result => console.log('Couch Mode game mute:', result))
		.catch(error => console.warn('Couch Mode: muting the game failed', error));
	if (remute === null) remute = window.setInterval(() => {
		if (muting) backend.muteGame(mutedPid).then(log).catch(() => {});
	}, REMUTE_MS);
}

function unmute() {
	if (remute !== null) window.clearInterval(remute);
	remute = null;
	if (!muting) return;
	muting = false;
	mutedPid = 0;
	backend.unmuteGame().catch(error => console.warn('Couch Mode: unmuting the game failed', error));
}

function activated(pid: number, appId: number, active: boolean) {
	open = active;
	// The backend also mutes everything else Steam started, so a launcher's
	// game is muted even when pid is the launcher or 0.
	if (active && settings()?.game_mute !== false) mute(pid);
	else if (!active) unmute();
	console.log(`Couch Mode: overlay ${active ? 'opened' : 'closed'} (app ${appId}, process ${pid})`);
}

export function startMute() {
	const overlay = (window as any).SteamClient?.Overlay;
	if (typeof overlay?.RegisterForOverlayActivated !== 'function') {
		console.warn('Couch Mode: SteamClient.Overlay.RegisterForOverlayActivated is missing, so the game is not muted while the overlay is open.');
		return;
	}
	registration = overlay.RegisterForOverlayActivated(activated);
	console.log('Couch Mode: listening for the game overlay');
	unsubscribeSettings = onSettings(s => { if (!s.game_mute) unmute(); });
	try { unsubscribeWindows = subscribePopups(watchOverlayWindow); } catch { /* only for the log */ }
	check = window.setInterval(() => { if (!gameRunning()) { open = false; unmute(); } }, CHECK_MS);
}

export function stopMute() {
	registration?.unregister?.();
	registration = null;
	unsubscribeSettings?.();
	unsubscribeSettings = null;
	unsubscribeWindows?.();
	unsubscribeWindows = null;
	if (check !== null) window.clearInterval(check);
	check = null;
	open = false;
	unmute();
}

export function overlayOpen(): boolean {
	return open;
}
