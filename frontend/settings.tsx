// Settings page in Millennium's plugin list (desktop Steam > Millennium > Plugins).
import { ButtonItem, DialogControlsSectionHeader, DropdownItem, Field, SliderField, TextField, ToggleField } from 'millennium';
import { useEffect, useRef, useState } from 'react';
import { loadSettings, saveSetting, Settings } from './config';
import { listMusic, MusicList } from './music';

const HOLD_MIN = 200, HOLD_MAX = 2000, HOLD_STEP = 50;
// Steam's slider ignores `step` while dragging, so values are snapped here.
const snap = (v: number) => Math.min(HOLD_MAX, Math.max(HOLD_MIN, Math.round(v / HOLD_STEP) * HOLD_STEP));

function musicDescription(music: MusicList | null) {
	if (!music) return 'Checking...';
	if (music.tracks.length === 0) return music.error || 'No music found.';
	const names = music.tracks.slice(0, 3).map(t => t.name).join(', ');
	const more = music.tracks.length > 3 ? ` and ${music.tracks.length - 3} more` : '';
	return `${music.tracks.length} file${music.tracks.length === 1 ? '' : 's'}: ${names}${more}`;
}

export function SettingsPage() {
	const [settings, setSettings] = useState<Settings | null>(null);
	const [error, setError] = useState('');
	const [keysDraft, setKeysDraft] = useState('');
	const [pathDraft, setPathDraft] = useState('');
	const [music, setMusic] = useState<MusicList | null>(null);
	const pending = useRef<Record<string, number>>({});
	const [access, setAccess] = useState<'on' | 'off' | 'waiting' | ''>('');

	const checkMusic = () => { setMusic(null); listMusic().then(setMusic).catch(e => setMusic({ folder: '', tracks: [], error: String(e) })); };

	useEffect(() => {
		loadSettings()
			.then(s => { setSettings(s); setKeysDraft(s.keys); setPathDraft(s.music_path); })
			.catch(e => setError(String(e)));
		backend.getXboxModeAccess().then(v => setAccess(v === 'on' ? 'on' : 'off')).catch(() => {});
		checkMusic();
		return () => Object.values(pending.current).forEach(id => window.clearTimeout(id));
	}, []);

	// Saves after a short pause, so a slider drag writes once.
	const save = <K extends keyof Settings>(key: K, value: Settings[K], delay = 0, then?: () => void) => {
		setSettings(s => (s ? { ...s, [key]: value } : s));
		window.clearTimeout(pending.current[key]);
		pending.current[key] = window.setTimeout(async () => {
			try {
				const result = await saveSetting(key, value);
				setError(result === 'ok' ? '' : result);
				if (result === 'ok') then?.();
			} catch (e) {
				setError(String(e));
			}
		}, delay);
	};

	// Windows shows its own admin prompt; reg.exe then runs on its own, so check again a few times.
	const changeAccess = async (state: 'on' | 'off') => {
		const result = await backend.setXboxModeAccess(state).catch(() => 'error');
		if (result !== 'started') { setError(result === 'cancelled' ? 'Windows did not get permission.' : 'Could not change Xbox mode access.'); return; }
		setError('');
		setAccess('waiting');
		for (let i = 0; i < 10; i++) {
			await new Promise(r => window.setTimeout(r, 1000));
			const now = await backend.getXboxModeAccess().catch(() => 'off');
			if (now === state) { setAccess(now); return; }
		}
		setAccess(state === 'on' ? 'off' : 'on');
		setError('Xbox mode access did not change.');
	};

	if (!settings) return <Field label={error || 'Loading settings...'} />;
	if (!settings.windows) return <Field label="Not available" description={settings.unavailable_reason} />;

	const on = settings.overlay_shortcut;
	return (
		<>
			{error && <Field label="Not saved" description={error} />}

			<DialogControlsSectionHeader>Controller battery</DialogControlsSectionHeader>
			<ToggleField
				label="Battery next to the clock"
				description="Shows the Bluetooth controller's battery in Big Picture and in the game overlay."
				checked={settings.battery_badge}
				onChange={checked => save('battery_badge', checked)}
			/>

			<DialogControlsSectionHeader>Hold for overlay</DialogControlsSectionHeader>
			<ToggleField
				label="Hold to open Steam overlay"
				description="Hold a controller button in a game to open the Steam overlay. Useful when the guide button is left to Windows Game Bar."
				checked={on}
				onChange={checked => save('overlay_shortcut', checked)}
			/>
			<SliderField
				label="Hold time"
				description={`${settings.hold_ms} ms`}
				value={settings.hold_ms}
				min={HOLD_MIN}
				max={HOLD_MAX}
				step={HOLD_STEP}
				disabled={!on}
				onChange={v => save('hold_ms', snap(v), 400)}
			/>
			<DropdownItem
				label="Button"
				disabled={!on}
				rgOptions={[{ label: 'Menu', data: 'Menu' }, { label: 'View', data: 'View' }]}
				selectedOption={settings.button}
				onChange={option => save('button', option.data)}
			/>
			<TextField
				label="Overlay keys"
				description="Must match Steam > Settings > In Game > Overlay shortcut keys. For example Shift+Tab."
				value={keysDraft}
				disabled={!on}
				onChange={e => { setKeysDraft(e.target.value); save('keys', e.target.value, 800); }}
			/>
			<ButtonItem
				label="Xbox mode controller access"
				description={
					access === 'on' ? 'On. The shortcut also works in Windows Xbox mode.'
					: access === 'waiting' ? 'Waiting for Windows...'
					: 'Off. In Windows Xbox mode, Windows hides the controller from this plugin, so the shortcut does nothing. Turning this on needs administrator rights once.'
				}
				disabled={access === '' || access === 'waiting'}
				onClick={() => changeAccess(access === 'on' ? 'off' : 'on')}
			>
				{access === 'on' ? 'Remove' : 'Turn on'}
			</ButtonItem>

			<DialogControlsSectionHeader>Game mute</DialogControlsSectionHeader>
			<ToggleField
				label="Mute the game while the overlay is open"
				description="The game's sound comes back when the overlay closes. Steam's own sounds and videos keep playing."
				checked={settings.game_mute}
				onChange={checked => save('game_mute', checked)}
			/>

			<DialogControlsSectionHeader>Home music</DialogControlsSectionHeader>
			<ToggleField
				label="Music on Home and Library"
				description="Plays your own music in Big Picture. It fades out on the store and other pages, while a video plays, while a game runs, and when Big Picture is not in front."
				checked={settings.music}
				onChange={checked => save('music', checked)}
			/>
			<TextField
				label="Music file or folder"
				description={`Empty means ${music?.folder && !settings.music_path ? music.folder : 'a Couch Mode folder in your Music folder'}. ${musicDescription(music)}`}
				value={pathDraft}
				onChange={e => { setPathDraft(e.target.value); save('music_path', e.target.value.trim(), 800, checkMusic); }}
			/>
			<SliderField
				label="Music volume"
				description={`${settings.music_volume}%`}
				value={settings.music_volume}
				min={0}
				max={100}
				step={5}
				onChange={v => save('music_volume', Math.round(v / 5) * 5, 300)}
			/>
		</>
	);
}
