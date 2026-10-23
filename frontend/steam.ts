// Small reads from Steam's own UI state.

// Steam keeps a list of running apps, including non-Steam games started from
// Steam. If it is not available, assume a game may be running.
export function gameRunning(): boolean {
	const apps = (window as any).SteamUIStore?.RunningApps;
	return Array.isArray(apps) ? apps.length > 0 : true;
}
