// Drives the overlay shortcut in the backend (see backend/shortcut.lua).
// The Lua backend cannot run a timer of its own, so the frontend calls it.

const FAST_MS = 40;    // a game is running and a controller is connected
const IDLE_MS = 1000;  // no game, no controller, or the feature is off

let timer: number | null = null;
let alive = false;

// Steam keeps a list of running apps, including non-Steam games started from
// Steam. If it is not available, assume a game may be running.
function gameRunning(): boolean {
	const apps = (window as any).SteamUIStore?.RunningApps;
	return Array.isArray(apps) ? apps.length > 0 : true;
}

async function tick() {
	if (!alive) return;
	let next = IDLE_MS;
	if (gameRunning()) {
		try {
			const result = await backend.pollShortcut();
			if (result === 'ok') next = FAST_MS;
			else if (result !== 'off' && result !== 'idle') console.log('Overlay shortcut:', result);
		} catch (error) {
			console.warn('Overlay shortcut poll failed', error);
		}
	}
	if (alive) timer = window.setTimeout(tick, next);
}

export function startShortcut() {
	alive = true;
	void tick();
}

export function stopShortcut() {
	alive = false;
	if (timer !== null) window.clearTimeout(timer);
	timer = null;
}
