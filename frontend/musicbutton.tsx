// Music pause button in the top bar, left of the battery badge.
//
// Where it can, the button is a Steam Focusable rendered into the top bar's
// own controller row, so the D-pad reaches it after the network icon and A
// presses it. That row is Steam's focus node, read from the React tree of
// the top bar; it is not a public API, so if Steam changes it the button
// falls back to a plain element that works with the mouse, touch and keyboard
// only.
import { Focusable } from 'millennium';
import { useEffect, useState } from 'react';
import { onSettings, saveSetting, settings, Settings } from './config';

export const MUSIC_ID = 'couch-mode-music';
// Steam's top bar CSS sizes header icons, so the size is set inline. 18px
// with the view box trimmed to the note gives a ~15px glyph like the
// network icon next to it.
const ICON = 18;
const VIEW_BOX = '1.5 1.5 21 21';
// Steam's top bar styles a focused item through this class (white box, dark icon).
const FOCUS_CLASS = 'gpfocus';

type Nav = { Context: any; node: any };
type Placed = { host: HTMLElement; root: any; node: any };

const placed = new Map<Document, Placed>();
let saving = false;
let warned = false;

// Pauses or resumes the music everywhere; the setting survives restarts.
async function toggleMusic() {
	if (saving) return;
	saving = true;
	try {
		const result = await saveSetting('music_paused', !settings()?.music_paused);
		if (result !== 'ok') console.warn('Couch Mode: music pause not saved:', result);
	} catch (error) {
		console.warn('Couch Mode: music pause not saved', error);
	} finally {
		saving = false;
	}
}

const title = (paused: boolean) => (paused ? 'Music paused. Resume music' : 'Pause music');

function Note({ paused }: { paused: boolean }) {
	return (
		<svg viewBox={VIEW_BOX} width={ICON} height={ICON} aria-hidden="true" fill="none" stroke="currentColor"
			strokeLinecap="round" strokeLinejoin="round" style={{ flex: '0 0 auto', width: `${ICON}px`, height: `${ICON}px` }}>
			<path d="M9 18V5l11-2v13M9 18a3 3 0 1 1-6 0a3 3 0 0 1 6 0Zm11-2a3 3 0 1 1-6 0a3 3 0 0 1 6 0Z" strokeWidth="1.5" />
			{paused && <path d="M3 3l18 18" strokeWidth="2" />}
		</svg>
	);
}

function MusicButton({ className }: { className: string }) {
	const [s, setS] = useState<Settings | null>(settings());
	const [focused, setFocused] = useState(false);
	useEffect(() => onSettings(setS), []);
	if (!s?.music) return null;
	const paused = !!s.music_paused;
	return (
		<Focusable
			className={className}
			role="button"
			aria-label={title(paused)}
			aria-pressed={paused}
			title={title(paused)}
			noFocusRing
			focusClassName={FOCUS_CLASS}
			onFocus={() => setFocused(true)}
			onBlur={() => setFocused(false)}
			onActivate={() => void toggleMusic()}
			onClick={() => void toggleMusic()}
			style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', alignSelf: 'stretch', padding: '0 8px', cursor: 'pointer', flex: '0 0 auto',
				// The same white box as Steam's focused top bar items, in case its class is not applied.
				...(focused ? { background: 'rgb(255, 255, 255)', color: 'rgb(0, 0, 0)' } : {}) }}
		>
			<Note paused={paused} />
		</Focusable>
	);
}

// The focus node Steam gives the top bar row, from the React context just
// above the row's element. Null when Steam's tree does not look as expected.
function findNav(row: HTMLElement): Nav | null {
	try {
		const key = Object.keys(row).find(k => k.startsWith('__reactFiber'));
		let fiber = key ? (row as any)[key] : null;
		for (let i = 0; fiber && i < 8; i++, fiber = fiber.return) {
			const node = fiber.memoizedProps?.value;
			if (fiber.tag === 10 && node?.m_element === row && Array.isArray(node.m_rgChildren) && typeof node.AddChild === 'function')
				return { Context: fiber.type, node };
		}
	} catch { /* fall through */ }
	return null;
}

// The plain element: works with the mouse, touch and keyboard, not the D-pad.
function makeFallback(doc: Document, className: string) {
	const button = doc.createElement('div');
	button.className = className;
	button.setAttribute('role', 'button');
	button.tabIndex = 0;
	Object.assign(button.style, {
		display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '0 8px',
		alignSelf: 'stretch', cursor: 'pointer', userSelect: 'none', flex: '0 0 auto', outline: 'none',
	});
	const highlight = (on: boolean) => {
		button.style.background = on ? 'rgb(255, 255, 255)' : '';
		button.style.color = on ? 'rgb(0, 0, 0)' : '';
	};
	button.addEventListener('mouseenter', () => highlight(true));
	button.addEventListener('mouseleave', () => highlight(doc.activeElement === button));
	button.addEventListener('focus', () => highlight(true));
	button.addEventListener('blur', () => highlight(false));
	button.addEventListener('click', event => { event.stopPropagation(); void toggleMusic(); });
	button.addEventListener('keydown', event => {
		if (event.key !== 'Enter' && event.key !== ' ') return;
		event.preventDefault();
		event.stopPropagation();
		void toggleMusic();
	});
	return button;
}

function renderFallback(button: HTMLElement) {
	const paused = !!settings()?.music_paused;
	if (button.title === title(paused)) return;
	button.title = title(paused);
	button.setAttribute('aria-label', title(paused));
	button.setAttribute('aria-pressed', String(paused));
	const ns = 'http://www.w3.org/2000/svg';
	const svg = button.ownerDocument.createElementNS(ns, 'svg');
	for (const [k, v] of Object.entries({ viewBox: VIEW_BOX, width: String(ICON), height: String(ICON), 'aria-hidden': 'true', fill: 'none',
		stroke: 'currentColor', 'stroke-linecap': 'round', 'stroke-linejoin': 'round' })) svg.setAttribute(k, v);
	svg.style.cssText = `flex: 0 0 auto; width: ${ICON}px; height: ${ICON}px`;
	const paths = [['M9 18V5l11-2v13M9 18a3 3 0 1 1-6 0a3 3 0 0 1 6 0Zm11-2a3 3 0 1 1-6 0a3 3 0 0 1 6 0Z', '1.5']];
	if (paused) paths.push(['M3 3l18 18', '2']);
	for (const [d, width] of paths) {
		const path = button.ownerDocument.createElementNS(ns, 'path');
		path.setAttribute('d', d);
		path.setAttribute('stroke-width', width);
		svg.append(path);
	}
	button.replaceChildren(svg);
}

export function removeMusicButton(doc: Document) {
	const entry = placed.get(doc);
	placed.delete(doc);
	try { entry?.root?.unmount(); } catch { /* the window may be gone */ }
	entry?.host.remove();
}

// Puts the button in the row before `before` and returns the element that
// takes space, or null while music is off.
export function placeMusicButton(doc: Document, row: HTMLElement, before: Element, className: string): HTMLElement | null {
	const nav = findNav(row);
	let entry = placed.get(doc);
	// Steam rebuilt the row, or the row's focus node appeared or went away.
	if (entry && entry.node !== (nav?.node ?? null)) {
		removeMusicButton(doc);
		entry = undefined;
	}
	if (!entry) {
		const host = doc.createElement('div');
		host.id = MUSIC_ID;
		const dom = (window as any).SP_REACTDOM;
		if (nav && typeof dom?.createRoot === 'function') {
			host.style.display = 'contents';
			const root = dom.createRoot(host);
			const tree = <nav.Context value={nav.node}><MusicButton className={className} /></nav.Context>;
			// Synchronously, so the button can be measured right away.
			if (typeof dom.flushSync === 'function') dom.flushSync(() => root.render(tree));
			else root.render(tree);
			entry = { host, root, node: nav.node };
		} else {
			if (!warned) { warned = true; console.log('Couch Mode: top bar focus row not found; the music button works with the mouse only.'); }
			host.append(makeFallback(doc, className));
			entry = { host, root: null, node: null };
		}
		placed.set(doc, entry);
	}
	const { host } = entry;
	if (host.parentElement !== row || host.nextElementSibling !== before) row.insertBefore(host, before);
	if (!settings()?.music) { host.style.display = 'none'; return null; }
	host.style.display = entry.root ? 'contents' : '';
	const button = host.firstElementChild as HTMLElement | null;
	if (!entry.root && button) renderFallback(button);
	return button;
}

// Hides the button when the row is full.
export function hideMusicButton(doc: Document) {
	const entry = placed.get(doc);
	if (entry) entry.host.style.display = 'none';
}
