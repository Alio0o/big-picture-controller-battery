import { definePlugin, IconsModule } from 'millennium';
import { startBattery, stopBattery } from './battery';
import { loadSettings } from './config';
import { startMusic, stopMusic } from './music';
import { startMute, stopMute } from './mute';
import { startShortcut, stopShortcut } from './shortcut';
import { SettingsPage } from './settings';

const DISPOSE_KEY = '__couchMode_dispose';

let running = false;

function start(name: string, fn: () => void) {
	try {
		fn();
	} catch (error) {
		console.error(`Couch Mode: ${name} could not start`, error);
	}
}

function stop() {
	running = false;
	stopBattery();
	stopShortcut();
	stopMute();
	stopMusic();
}

export default definePlugin(() => {
	// A reloaded frontend replaces the previous instance in the shared UI.
	(window as any)[DISPOSE_KEY]?.();
	(window as any)[DISPOSE_KEY] = stop;
	running = true;

	start('battery badge', startBattery);
	start('overlay shortcut', startShortcut);
	// Game mute and music read their settings before they start.
	loadSettings()
		.catch(error => console.error('Couch Mode: settings could not be read', error))
		.then(() => {
			if (!running) return;
			start('game mute', startMute);
			start('music', startMusic);
		});

	// Millennium lists a settings page only when title, icon and content are all set.
	return {
		title: 'Couch Mode',
		icon: IconsModule?.Settings ? <IconsModule.Settings /> : <span />,
		content: <SettingsPage />,
		onDismount: stop,
	} as any;
});
