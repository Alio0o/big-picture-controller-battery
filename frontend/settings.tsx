// Settings page in Millennium's plugin list (desktop Steam > Millennium > Plugins).
//
// Every row is a Steam Field, which Millennium draws as a card: the title
// with its control on the right in one line, and the description under them
// across the whole card (a control beside the description would squeeze it
// into a narrow column). Sliders and text boxes sit full width below. Section
// titles are plain text between the cards, all in one style.
import { DialogButton, Dropdown, Field, SliderField, TextField, Toggle } from 'millennium';
import { ReactNode, useEffect, useRef, useState } from 'react';
import { loadSettings, saveSetting, Settings } from './config';
import { listMusic, MusicList } from './music';

const HOLD_MIN = 200, HOLD_MAX = 2000, HOLD_STEP = 50;
// Steam's slider ignores `step` while dragging, so values are snapped here.
const snap = (v: number) => Math.min(HOLD_MAX, Math.max(HOLD_MIN, Math.round(v / HOLD_STEP) * HOLD_STEP));

const SECTION_GAP = 24;
const BUTTON_STYLE = { minWidth: '120px', padding: '0 20px', whiteSpace: 'nowrap' } as const;

function Section({ title, first }: { title: string; first?: boolean }) {
	return (
		<div style={{ margin: `${first ? 0 : SECTION_GAP}px 0 8px`, fontSize: '1.15em', fontWeight: 600, lineHeight: 1.3 }}>
			{title}
		</div>
	);
}

// A card with the title and its control in one line, the description below
// across the whole card. The card itself is not focusable; the control is.
function Row(props: { label: string; description?: ReactNode; disabled?: boolean; children: ReactNode }) {
	return (
		<Field
			label={
				<div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '16px', minHeight: '40px' }}>
					<span>{props.label}</span>
					<div style={{ flex: '0 0 auto', display: 'flex', alignItems: 'center' }}>{props.children}</div>
				</div>
			}
			description={props.description}
			disabled={props.disabled}
			focusable={false}
			bottomSeparator="standard"
		/>
	);
}

// A row with the control below the label, full width.
function WideRow(props: { label: string; description?: ReactNode; disabled?: boolean; children: ReactNode }) {
	return (
		<Field
			label={props.label}
			description={props.description}
			disabled={props.disabled}
			childrenLayout="below"
			childrenContainerWidth="max"
			bottomSeparator="standard"
		>
			{props.children}
		</Field>
	);
}

function musicDescription(music: MusicList | null) {
	if (!music) return 'Checking...';
	const folder = music.folder ? `Put music files in ${music.folder}.` : '';
	if (!music.chosen) return `${music.error || 'No music yet.'} ${music.error?.startsWith('Put music') ? '' : folder}`.trim();
	const others = music.files > 1 ? ` ${music.files} files in the folder; Browse picks another.` : '';
	return `${music.chosen}.${others} ${folder}`.trim();
}

export function SettingsPage() {
	const [settings, setSettings] = useState<Settings | null>(null);
	const [error, setError] = useState('');
	const [keysDraft, setKeysDraft] = useState('');
	const [music, setMusic] = useState<MusicList | null>(null);
	const [browsing, setBrowsing] = useState(false);
	const pending = useRef<Record<string, number>>({});
	const [access, setAccess] = useState<'on' | 'off' | 'waiting' | ''>('');

	const checkMusic = () => { listMusic().then(setMusic).catch(e => setMusic({ folder: '', tracks: [], files: 0, chosen: '', error: String(e) })); };

	useEffect(() => {
		loadSettings()
			.then(s => { setSettings(s); setKeysDraft(s.keys); })
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

	// The backend waits while Windows' dialog is open, then returns the file
	// name in the music folder (a file from elsewhere is copied in).
	const browse = async () => {
		setBrowsing(true);
		try {
			const result = await backend.browseMusic();
			if (result.startsWith('error: ')) setError(result.slice(7));
			else if (result) save('music_file', result, 0, checkMusic);
			else checkMusic();
		} catch (e) {
			setError(String(e));
		} finally {
			setBrowsing(false);
		}
	};

	if (!settings) return <Field label={error || 'Loading settings...'} />;
	if (!settings.windows) return <Field label="Not available" description={settings.unavailable_reason} />;

	const shortcut = settings.overlay_shortcut;
	return (
		<>
			{error && <Field label="Not saved" description={error} bottomSeparator="standard" />}

			<Section title="Controller battery" first />
			<Row label="Battery next to the clock" description="Shows the Bluetooth controller's battery in Big Picture and in the game overlay.">
				<Toggle value={settings.battery_badge} onChange={checked => save('battery_badge', checked)} />
			</Row>

			<Section title="Hold for overlay" />
			<Row label="Hold to open the Steam overlay" description="Hold a controller button in a game to open the overlay. Useful when the guide button is left to Windows Game Bar.">
				<Toggle value={shortcut} onChange={checked => save('overlay_shortcut', checked)} />
			</Row>
			<WideRow label="Hold time" description={`${settings.hold_ms} ms`} disabled={!shortcut}>
				<SliderField
					value={settings.hold_ms}
					min={HOLD_MIN}
					max={HOLD_MAX}
					step={HOLD_STEP}
					disabled={!shortcut}
					bottomSeparator="none"
					onChange={v => save('hold_ms', snap(v), 400)}
				/>
			</WideRow>
			<Row label="Button" disabled={!shortcut}>
				<Dropdown
					rgOptions={[{ label: 'Menu', data: 'Menu' }, { label: 'View', data: 'View' }]}
					selectedOption={settings.button}
					disabled={!shortcut}
					onChange={option => save('button', option.data)}
				/>
			</Row>
			<WideRow label="Overlay keys" description="Must match Steam > Settings > In Game > Overlay shortcut keys, for example Shift+Tab." disabled={!shortcut}>
				<TextField
					value={keysDraft}
					disabled={!shortcut}
					onChange={e => { setKeysDraft(e.target.value); save('keys', e.target.value, 800); }}
				/>
			</WideRow>
			<Row
				label="Xbox mode controller access"
				description={
					access === 'on' ? 'On. The shortcut also works in Windows Xbox mode.'
					: access === 'waiting' ? 'Waiting for Windows...'
					: 'Off. In Windows Xbox mode, Windows hides the controller from this plugin, so the shortcut does nothing. Turning this on needs administrator rights once.'
				}
			>
				<DialogButton
					style={BUTTON_STYLE}
					disabled={access === '' || access === 'waiting'}
					onClick={() => changeAccess(access === 'on' ? 'off' : 'on')}
				>
					{access === 'on' ? 'Remove' : 'Turn on'}
				</DialogButton>
			</Row>

			<Section title="Game mute" />
			<Row label="Mute the game while the overlay is open" description="The game's sound comes back when the overlay closes. Steam's own sounds and videos keep playing.">
				<Toggle value={settings.game_mute} onChange={checked => save('game_mute', checked)} />
			</Row>

			<Section title="Music" />
			<Row label="Music in Big Picture" description="Plays your music everywhere in Big Picture. It fades out on the store, while a video or trailer plays, while a game runs, and when another program is in front.">
				<Toggle value={settings.music} onChange={checked => save('music', checked)} />
			</Row>
			<Row label="Music in the game overlay" description="Also plays while the overlay is open over a game, with the game muted. Needs game mute." disabled={!settings.music}>
				<Toggle value={settings.music_in_overlay} disabled={!settings.music} onChange={checked => save('music_in_overlay', checked)} />
			</Row>
			<Row label="Music file" description={musicDescription(music)}>
				<DialogButton style={BUTTON_STYLE} disabled={browsing} onClick={browse}>
					{browsing ? 'Choosing...' : 'Browse...'}
				</DialogButton>
			</Row>
			<WideRow label="Music volume" description={`${settings.music_volume}%`}>
				<SliderField
					value={settings.music_volume}
					min={0}
					max={100}
					step={5}
					bottomSeparator="none"
					onChange={v => save('music_volume', Math.round(v / 5) * 5, 300)}
				/>
			</WideRow>
		</>
	);
}
