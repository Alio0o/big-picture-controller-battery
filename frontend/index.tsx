import { definePlugin, IconsModule } from 'millennium';
import { startBattery, stopBattery } from './battery';
import { startShortcut, stopShortcut } from './shortcut';
import { SettingsPage } from './settings';

const DISPOSE_KEY = '__bigPictureControllerBattery_dispose';

function stop() {
	stopBattery();
	stopShortcut();
}

export default definePlugin(() => {
	// A reloaded frontend replaces the previous instance in the shared UI.
	(window as any)[DISPOSE_KEY]?.();
	(window as any)[DISPOSE_KEY] = stop;

	try {
		startBattery();
	} catch (error) {
		console.error('Battery badge could not start', error);
	}
	startShortcut();

	// Millennium lists a settings page only when title, icon and content are all set.
	return {
		title: 'Big Picture Controller Battery',
		icon: IconsModule?.Settings ? <IconsModule.Settings /> : <span />,
		content: <SettingsPage />,
		onDismount: stop,
	} as any;
});
