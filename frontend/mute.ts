// Mutes the game while the Steam overlay is open (see backend/audio.lua).
// Steam reports the overlay opening and closing together with the game's
// process id; the backend mutes that process in Windows' volume mixer.
import { onSettings, settings } from './config';
import { gameRunning } from './steam';

const REMUTE_MS = 2000; // a game can open a new audio stream while muted
const CHECK_MS = 1000;  // notices a game that quit while the overlay was open

let registration: { unregister?: () => void } | null = null;
let unsubscribeSettings: (() => void) | null = null;
let mutedPid = 0;
let open = false;
let remute: number | null = null;
let check: number | null = null;

function log(result: unknown) {
	if (typeof result === 'string' && result !== 'off' && !result.startsWith('muted 0 ')) console.log('Couch Mode game mute:', result);
}

function mute(pid: number) {
	mutedPid = pid;
	backend.muteGame(pid).then(log).catch(error => console.warn('Couch Mode: muting the game failed', error));
	if (remute === null) remute = window.setInterval(() => {
		if (mutedPid) backend.muteGame(mutedPid).then(log).catch(() => {});
	}, REMUTE_MS);
}

function unmute() {
	if (remute !== null) window.clearInterval(remute);
	remute = null;
	if (!mutedPid) return;
	mutedPid = 0;
	backend.unmuteGame().catch(error => console.warn('Couch Mode: unmuting the game failed', error));
}

function activated(pid: number, appId: number, active: boolean) {
	open = active;
	if (active && settings()?.game_mute !== false && pid > 0) mute(pid);
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
	unsubscribeSettings = onSettings(s => { if (!s.game_mute) unmute(); });
	check = window.setInterval(() => { if (!gameRunning()) { open = false; unmute(); } }, CHECK_MS);
}

export function stopMute() {
	registration?.unregister?.();
	registration = null;
	unsubscribeSettings?.();
	unsubscribeSettings = null;
	if (check !== null) window.clearInterval(check);
	check = null;
	open = false;
	unmute();
}

export function overlayOpen(): boolean {
	return open;
}
