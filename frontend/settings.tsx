// Settings page in Millennium's plugin list (desktop Steam > Millennium > Plugins).
import { DropdownItem, Field, SliderField, TextField, ToggleField } from 'millennium';
import { useEffect, useRef, useState } from 'react';
import { fromBackend } from './json';
import { renderable } from './safe';

type Settings = {
	overlay_shortcut: boolean;
	hold_ms: number;
	button: 'Menu' | 'View';
	keys: string;
	windows: boolean;
	unavailable_reason?: string;
};

const HOLD_MIN = 200, HOLD_MAX = 2000, HOLD_STEP = 50;
// Steam's slider ignores `step` while dragging, so values are snapped here.
const snap = (v: number) => Math.min(HOLD_MAX, Math.max(HOLD_MIN, Math.round(v / HOLD_STEP) * HOLD_STEP));

export function SettingsPage() {
	const [settings, setSettings] = useState<Settings | null>(null);
	const [error, setError] = useState('');
	const [keysDraft, setKeysDraft] = useState('');
	const pending = useRef<Record<string, number>>({});

	useEffect(() => {
		backend.getSettings()
			.then(value => { const s = fromBackend<Settings>(value); setSettings(s); setKeysDraft(s.keys); })
			.catch(e => setError(String(e)));
		return () => Object.values(pending.current).forEach(id => window.clearTimeout(id));
	}, []);

	// Saves after a short pause, so a slider drag writes once.
	const save = (key: keyof Settings, value: string | number | boolean, delay = 0) => {
		setSettings(s => (s ? { ...s, [key]: value } : s));
		window.clearTimeout(pending.current[key]);
		pending.current[key] = window.setTimeout(async () => {
			try {
				const result = await backend.setSetting(key, String(value));
				setError(result === 'ok' ? '' : result);
			} catch (e) {
				setError(String(e));
			}
		}, delay);
	};

	if (!renderable(DropdownItem, Field, SliderField, TextField, ToggleField))
		return <div style={{ padding: '12px' }}>Settings are not available in this Steam window. Open them from desktop Steam &gt; Millennium &gt; Plugins.</div>;
	if (!settings) return <Field label={error || 'Loading settings...'} />;
	if (!settings.windows) return <Field label="Not available" description={settings.unavailable_reason} />;

	const on = settings.overlay_shortcut;
	return (
		<>
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
			{error && <Field label="Not saved" description={error} />}
		</>
	);
}
