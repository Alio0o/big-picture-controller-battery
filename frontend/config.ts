// Settings shared by every feature. The backend stores and checks them
// (backend/settings.lua); this keeps a copy and tells the features when one
// changes on the settings page.
import { fromBackend } from './json';

export type Settings = {
	battery_badge: boolean;
	overlay_shortcut: boolean;
	hold_ms: number;
	button: 'Menu' | 'View';
	keys: string;
	game_mute: boolean;
	music: boolean;
	music_file: string;
	music_volume: number;
	music_in_overlay: boolean;
	windows: boolean;
	unavailable_reason?: string;
};

let current: Settings | null = null;
let loading: Promise<Settings> | null = null;
const listeners = new Set<(settings: Settings) => void>();

export function loadSettings(): Promise<Settings> {
	if (current) return Promise.resolve(current);
	loading ??= backend.getSettings()
		.then(value => (current = fromBackend<Settings>(value)))
		.finally(() => { loading = null; });
	return loading;
}

export function settings(): Settings | null {
	return current;
}

// Returns "ok" or the backend's message.
export async function saveSetting<K extends keyof Settings>(key: K, value: Settings[K]): Promise<string> {
	const result = await backend.setSetting(key, String(value));
	if (result === 'ok' && current) {
		current = { ...current, [key]: value };
		for (const fn of listeners) {
			try { fn(current); } catch (error) { console.error('Couch Mode settings listener failed', error); }
		}
	}
	return result;
}

export function onSettings(fn: (settings: Settings) => void): () => void {
	listeners.add(fn);
	return () => { listeners.delete(fn); };
}
